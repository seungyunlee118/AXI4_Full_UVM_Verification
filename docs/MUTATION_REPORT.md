# Mutation campaign — does the testbench catch real bugs?

A passing regression shows that the testbench ran. It does not show that the
testbench would notice a bug. To measure that, `sim/xcelium/mutate.py` injects
one deliberate bug at a time into `rtl/Axi_ram_v2.v`, the revision that is
supposed to be correct. It then reruns the regression on that copy and records
whether anything failed.

```
cd sim/xcelium
python3 mutate.py            # 25 mutants, 4 at a time, about 70 s on Xcelium 24.09
python3 mutate.py --list     # the catalogue
```

Each mutant is a single exact text substitution. An unmutated baseline has to
pass first. A mutant counts as **killed** when a testbench check fails: a
scoreboard mismatch or bad response, an assertion, the drain check, or the
watchdog timeout. A tool problem (crash, wall-clock limit) counts as not judged.
Score = killed / (total − equivalent).

## Result: 60% → 100%

| | Killed | Score |
|---|---|---|
| First run, testbench as it was | 15 / 25 | **60.0%** |
| After the fixes below | 25 / 25 | **100.0%** |

No mutant was declared equivalent.

## What the 10 survivors showed

The first run's survivors fell into three groups. Each group points to
something the testbench never checked or never exercised.

### 1. Responses were never checked — R01–R04

| Mutant | Bug |
|---|---|
| R01 | BRESP = SLVERR on every write |
| R02 | RRESP = SLVERR on every read |
| R03 | BID always 0 |
| R04 | RID always 0 |

The scoreboard compared data bytes only. The response code was sampled into
coverage but never checked. The monitor did not capture BID or RID at all.
A slave that reported every access as an error, or answered with the wrong ID,
passed every test.

**Fix.**
- The scoreboard now requires OKAY on every burst (`SB_RESP`). Every access is
  legal and inside the 64 KB memory, so any other response is wrong.
- The monitor keeps the first non-OKAY beat of a read, not just the last one.
- New assertions `a_bid_in_order` and `a_rid_in_order`. Both DUTs complete in
  order, so a B answers the oldest write without a B, and every R beat belongs
  to the oldest open read.

### 2. The master was always ready — Q04, Q05, D05

| Mutant | Bug |
|---|---|
| Q04 | B response retired without BREADY |
| Q05 | R beat advances without RREADY |
| D05 | read data reloads every cycle, even while R is stalled |

The driver tied BREADY and RREADY high. The slave never had to hold a response,
so its stall logic never ran and these bugs could not show. The protocol checker
also lacked stability checks for `bid`, `rid` and `rdata`.

**Fix.**
- The driver now drives BREADY and RREADY from a `ready_pct` knob (default 100,
  so the existing tests are unchanged). It counts completions on
  VALID && READY.
- New assertions `a_bid_stable`, `a_rid_stable` and `a_rdata_stable`.

### 3. Never more in flight than the slave could hold — Q01–Q03

| Mutant | Bug |
|---|---|
| Q01 | AWREADY ignores a full AW queue |
| Q02 | ARREADY ignores a full AR queue |
| Q03 | write burst starts with no free B slot |

The deepest test kept 4 bursts in flight, which is exactly `Axi_ram_v2`'s queue
depth. The queues could fill but never overflow. With B always accepted at
once, the B queue never filled either, so the credit check never mattered.

**Fix.** New `axi4_stress_test`: 32 short write bursts, then 32 reads, with 8
bursts in flight and BREADY/RREADY high only 30% of the time. On v2 it reaches
8 writes and 6 reads in flight. It passes on both DUTs.

Q01 is a good example of the checks working together. The overflow drops a
write, so the next B comes back with another write's ID, and `a_bid_in_order`
reports `BID 0x2e, but the oldest open write has AWID 0x19`.

## Also found along the way

- **Mutant A06** (read-side WRAP base) is killed only by the mid-window WRAP
  burst that `axi4_cov_seq` gained in this round. Before that burst existed,
  no read in the suite actually wrapped.
- **Mutants L01 and L03** make a burst never finish, which blocks the
  sequence. Without the watchdog added to `axi4_base_test`
  (`uvm_top.set_timeout(2ms)`), those runs would sit at UVM's 9200 s default
  until the wall-clock limit. They would then count as not judged rather than
  as detected.
- **Assertion messages printed post-edge values.** An action block runs after
  the clock edge, so `BID %0h` printed the next queue entry (`0xx`) instead of
  the value the assertion judged. The messages now use `$sampled()`.

## Final campaign

Seed 1, Xcelium 24.09. "First failing run" is the earliest failing check in the
first failing test.

| ID | Injected bug | Result | First failing run |
|---|---|---|---|
| A01 | WRAP addressed like INCR (the original v1 bug) | KILLED | wrap_test: SB_MISMATCH |
| A02 | WRAP drops the window base | KILLED | wrap_test: SB_MISMATCH |
| A03 | WRAP window twice the burst size | KILLED | wrap_test: SB_MISMATCH |
| A04 | address step ignores AxSIZE (always 4 bytes) | KILLED | stress_test: SB_MISMATCH |
| A05 | FIXED bursts increment like INCR | KILLED | directed_test: SB_MISMATCH |
| A06 | read WRAP base not aligned to the window | KILLED | cov_test: SB_MISMATCH |
| A07 | write WRAP base not aligned to the window | KILLED | wrap_test: SB_MISMATCH |
| D01 | write ignores WSTRB (every lane written) | KILLED | directed_test: SB_MISMATCH |
| D02 | WSTRB lanes reversed | KILLED | directed_test: SB_MISMATCH |
| D03 | every lane written with lane 0's byte | KILLED | directed_test: SB_MISMATCH |
| D04 | read returns the next word | KILLED | directed_test: SB_MISMATCH |
| D05 | read data reloads every cycle, even while R is stalled | KILLED | stress_test: AXI_SVA |
| L01 | RLAST one beat early | KILLED | directed_test: AXI_SVA |
| L02 | read burst one beat too long | KILLED | directed_test: AXI_SVA |
| L03 | write engine takes one beat fewer than AWLEN | KILLED | directed_test: FATAL:PH_TIMEOUT |
| L04 | a B response per W beat (B before WLAST) | KILLED | directed_test: AXI_SVA |
| R01 | BRESP = SLVERR on every write | KILLED | directed_test: SB_RESP |
| R02 | RRESP = SLVERR on every read | KILLED | directed_test: SB_RESP |
| R03 | BID always 0 | KILLED | directed_test: AXI_SVA |
| R04 | RID always 0 | KILLED | directed_test: AXI_SVA |
| Q01 | AWREADY ignores a full AW queue | KILLED | stress_test: AXI_SVA |
| Q02 | ARREADY ignores a full AR queue | KILLED | stress_test: AXI_SVA |
| Q03 | write burst starts with no free B slot | KILLED | stress_test: AXI_SVA |
| Q04 | B response retired without BREADY | KILLED | stress_test: AXI_SVA |
| Q05 | R beat advances without RREADY | KILLED | stress_test: AXI_SVA |

## Limits

- One seed per mutant. The stress test's back-pressure is random, so the queue
  mutants (Q01–Q05) depend on that seed producing enough stalls. They were
  killed on seed 1. Use `-s 1 2 3` for a stricter campaign.
- The ID-ordering assertions assume an in-order slave, which both DUTs are.
  AXI only requires order per ID, so a slave that reorders across IDs would
  need per-ID tracking instead.
- The catalogue covers v2's own logic. It does not mutate the open-source v1,
  whose known WRAP bug is already guarded by `axi4_wrap_test` (XFAIL on v1).

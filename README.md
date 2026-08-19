# Pipelined L1 Cache with UVM Verification

A 4-way set-associative L1 data cache written from scratch in SystemVerilog,
together with a UVM testbench that checks it against an independent cycle-accurate
golden model. The environment drives constrained-random and directed traffic,
reconstructs every burst on the memory bus with a passive monitor, and compares
every read and every eviction/fill against the model. It closes 100% functional
coverage and 100% FSM coverage, and the scoreboard caught a real addressing bug in
an early RTL revision.

The design is simulated with AMD Vivado XSim (built-in UVM 1.2) on both Windows
and Linux (WSL2). A single testbench targets the cache through a burst memory
interface, and the same suite works as a regression guard across design changes.

```
make regress     44/44 pass   (11 tests x 4 seeds)
                 UVM_ERROR 0, UVM_FATAL 0, SVA failures 0
                 merged functional coverage 100%
                 FSM coverage 100% on the stress test, >= 97.5% elsewhere
```

## Design under test

The DUT is a self-authored L1 data cache controller (`rtl/l1_cache_core.sv`) with
its tag and data arrays modelled as registered-read SRAM macros. It is 4-way set
associative, write-back / write-allocate, with tree-PLRU replacement and 16-byte
lines that are filled and evicted as bursts.

| | |
|---|---|
| Organisation | 4-way set associative |
| Capacity | 64 sets x 4 ways x 16 B = 4 KB (256 lines) |
| Policy | write-back, write-allocate |
| Replacement | tree-PLRU, 3 bits per set; invalid ways filled first |
| Writes | byte enables (`cpu_req_be[3:0]`) |
| Address split | tag `[31:10]`, set `[9:4]`, word `[3:2]`, byte `[1:0]` |
| Arrays | registered-read SRAM: address in cycle N, data in cycle N+1 |
| Memory | burst interface, separate request / write-data / read-data channels, 4 beats |
| Latency | read hit = 1 cycle; miss = fill, plus a write-back if the victim is dirty |

The parts that made this non-trivial to verify, and which the testbench
deliberately targets:

- **A read-after-write hazard through the pipeline.** Registered arrays return the
  value that was there before a same-cycle write, so a write immediately followed
  by a read of the same location needs forwarding, and the forwarding has to work
  per byte because a store may touch only some lanes.
- **PLRU victim selection.** With four ways sharing a set, the wrong victim
  silently degrades hit rate, so the model tracks and checks which way is replaced.
- **Burst fill and eviction.** The memory side is a multi-beat protocol, so beat
  count, ordering and `LAST` all have to be right.
- **Reset in the middle of traffic,** including mid-burst, where an in-flight
  write-back can be cut in half.

## Architecture

<!-- Block diagram of the UVM environment. -->
<img width="893" height="527" alt="UVM environment block diagram" src="https://github.com/user-attachments/assets/605ab956-8489-4566-8bd6-9132d8ddcdcb" />

| Component | Purpose |
|-----------|---------|
| `l1_cache_item` | One CPU request: address, rw, byte enables, write data; annotated by the model with hit/way/victim for coverage. |
| `l1_cache_cpu_driver` | CPU master. Drives the request handshake through a clocking block; supports true back-to-back (VALID never drops between accepted requests). |
| `l1_cache_cpu_monitor` | Passive. Publishes on two ports: every accepted request in issue order, and every read response. |
| `l1_cache_mem_driver` | Reactive burst memory model. One timing item per burst gives randomised fill latency, request backpressure and inter-beat gaps. |
| `l1_cache_mem_monitor` | Passive. Reconstructs each memory burst (all beats) and broadcasts it. |
| `l1_cache_reset_agent` | Owns `rst_n`, does the power-on reset, and can re-assert it mid-traffic; announces every reset so the model flushes in step with the DUT. |
| `l1_cache_scoreboard` | Golden cache model: mirrors tags, valid/dirty, data and PLRU for all four ways plus main memory. Predicts hit/miss, read data, and every eviction/fill burst, and checks them. |
| `l1_cache_coverage`, `l1_cache_fsm_cov` | Functional covergroup (fed from the model) and a white-box FSM covergroup bound into the controller. |
| `l1_cache_if`, `l1_cache_config` | Interface with clocking blocks and the bound-in SVA checker; a single config object for all knobs. |

The scoreboard mirrors the DUT and predicts, for every request, hit or miss and
which way, the exact read data down to the byte, and whether the PLRU victim is
dirty and must be written back (to which address, with which four beats) followed
by the fill. Because the DUT is pipelined, a read miss can retire in the same
cycle the next request is accepted, so read expectations are snapshotted when the
request is issued and checked when the data comes back. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full pipeline, FSM and
scoreboard diagrams, and the study notes under `docs/` for a file-by-file
walkthrough.

## Repository layout

```
rtl/
  l1_cache_pkg.sv       parameters, address helpers, PLRU functions (single source of truth)
  l1_cache_core.sv      controller: 2-stage pipeline, miss FSM, forwarding
  l1_cache_top.sv       core + 4 tag SRAMs + 4 data SRAMs
  sram_macro.sv         registered-read SRAM models (plain and byte-enabled)
tb/
  l1_cache_if.sv        interface: clocking blocks + bound-in SVA
  l1_cache_config.sv    one config object for topology, memory timing, reset knobs
  tb_top.sv             interface + DUT + FSM-cov bind + run_test()
  tb_classes.svh        include order for the class-based TB
  agent/                sequence items, CPU / memory / reset agents
  env/                  scoreboard (golden model), coverage, FSM coverage, env
  seqs/                 stimulus and memory-responder sequences
  tests/                base test + 11 scenario tests
sim/vivado/
  Makefile              Linux / WSL2 XSim flow
  run.sh, regress.sh    thin wrappers over the Makefile
  run.bat, regress.bat  Windows XSim flow
  setup_env.sh          locates Vivado (PATH / VIVADO_ROOT / common install dirs)
  wsl_local.sh          mirror source to native FS for fast WSL2 builds
  files.f               compile order
docs/
  ARCHITECTURE.md       diagrams: block, pipeline, FSM, PLRU, forwarding, scoreboard
  STUDY_*.md            file-by-file study notes
```

## Running

The build finds the Vivado tools through `setup_env.sh`, which uses XSim if it is
already on `PATH`, otherwise sources `$VIVADO_ROOT/settings64.sh`, otherwise probes
common install locations. Vivado's precompiled UVM 1.2 is pulled in with `-L uvm`,
so there is nothing to compile yourself.

Linux (WSL2), using the Makefile:

```
export VIVADO_ROOT=/opt/Xilinx/Vivado/2025.2   # or source settings64.sh yourself
cd sim/vivado
make                                 # default test
make TEST=l1_cache_stress_test SEED=42
make regress                         # all tests x 4 seeds, then merged coverage
make wave                            # rebuild with VCD dumping, then run
```

On WSL2, XSim I/O over the `/mnt/c` mount is slow, so `./wsl_local.sh regress`
rsyncs the source (no build artifacts) into a native path and builds there.

Windows, using the batch script:

```
call "C:\AMDDesignTools\<version>\Vivado\settings64.bat"
cd sim\vivado
run.bat                              :: default test, seed 1
run.bat l1_cache_stress_test 42      :: pick a test and a seed
regress.bat                          :: full regression + merged coverage
```

A run passes when the report shows `UVM_ERROR : 0`, `UVM_FATAL : 0`, and the
scoreboard reports zero mismatches. Sequence, transaction count and test are
overridable at runtime with `+SEQ=...`, `+NUM_TRANS=...` and `+UVM_TESTNAME=...`.

## Tests

| Test | Description |
|------|-------------|
| `l1_cache_smoke_test` | short sanity run, gentle memory |
| `l1_cache_random_test` | mixed read/write over 8 tags per set (default) |
| `l1_cache_thrash_test` | whole-address-space random, almost all misses |
| `l1_cache_eviction_test` | 6 tags per set, so the PLRU evicts continuously |
| `l1_cache_b2b_test` | true back-to-back, VALID never drops |
| `l1_cache_line_test` | multi-word line and spatial locality |
| `l1_cache_be_test` | byte enables and per-byte forwarding |
| `l1_cache_stress_test` | slow memory, heavy backpressure on both channels |
| `l1_cache_passive_test` | passive CPU agent, stimulus from a BFM in the test |
| `l1_cache_reset_test` | mid-traffic reset, memory bus quiesced first |
| `l1_cache_reset_async_test` | reset at an arbitrary moment, including mid-burst |

## Results

A clean regression reports zero errors and zero mismatches on all 11 tests across
four seeds. The per-test coverage numbers are low on purpose - each test aims at a
narrow scenario - while the merged number across the whole regression is 100%.

A dirty miss on the bus (write-back burst followed by the fill burst):

<!-- miss-path waveform capture; drop the image here -->
<!-- <img alt="dirty miss waveform" src="docs/wave_miss.png" /> -->

### Bug found: combinational array reads returned the wrong line

An early RTL revision modelled the SRAM read port combinationally
(`assign rdata = mem[raddr]`). That contradicts the pipeline, which issues the
address in S1 and expects the data in S2, and it closes a loop through the stall
path (`stall -> raddr -> rdata -> hit -> stall`).

A plain write-then-read-back test does not reliably expose it, because on a steady
stream of hits the address happens to be stable. The failure shows up on the
allocate-to-hit turnaround, where the freshly filled line is read on the same
cycle the next request drives a new index onto the array:

```
fill a line, then read the just-filled word back
  expected : the data written by the fill
  DUT      : the *next* request's index was already on the array,
             so a different line's data came back
```

The scoreboard flagged this as 675 read mismatches in a single run (about 45% of
all reads). Making the read port registered fixed the timing and broke the loop;
a one-deep, per-byte forwarding path then covers the genuine read-after-write case.

### Testbench bugs that passed silently

The more interesting finds were in the testbench itself, each of which produced a
green regression while being wrong:

- Assertions used `$error`, which does not increment `UVM_ERROR`, so a run with
  failing assertions still reported zero errors. Switching them to
  `uvm_report_error` fixed it, confirmed by forcing an assertion to fail and
  checking the run was then flagged (685 errors, marked FAIL).
- A memory-driver reset used `disable fork` between `get_next_item` and
  `item_done`; it also killed the sequencer's own processes and corrupted the
  handshake. Replaced with an explicit abort check at every wait point.
- A `for` body with `bit [31:0] base = f(i);` was evaluated once by XSim, so 24
  distinct lines collapsed into one and the passive test reported 191 hits, 1 miss
  and still passed. Declaration and assignment are now split.
- The address helpers used single-letter argument names; when a call site had a
  local of the same name, XSim passed 0, and the eviction test generated zero
  evictions while passing. Formals renamed to `addr_in` / `tag_in` / `idx_in`.

### Functional and FSM coverage

`l1_cache_random_test` and `l1_cache_stress_test` close the functional covergroup
at 100%; the merged number across the regression is 100%. Coverpoints cover
direction, hit/miss, eviction, cold vs conflict miss, way, word within the line,
set reach and byte-enable shape, with six crosses. The white-box FSM covergroup
reaches 100%, exercising every state and legal transition and confirming that none
of its twelve `illegal_bins` transitions ever occur. Structurally unreachable
situations are excluded with `ignore_bins` rather than left as open holes.

## Protocol checking (SVA)

`tb/l1_cache_if.sv` carries a set of assertions bound into the testbench without
touching the RTL. They cover the handshake rules (VALID held until READY, payload
stable while stalled), no unknown values on qualified fields, line alignment on
memory requests, and burst-beat accounting - each burst must deliver exactly
`len+1` beats with `LAST` only on the last one. The assertions were validated by
deliberately inverting one and confirming the regression then failed with the
expected error count, so a passing run means the checks are active rather than
vacuous.

## Tooling notes

The environment runs on the free Vivado XSim tier. Two things to know: XSim
silently ignores `cover property` (it prints `XSIM 43-4127` at elaboration), so the
SVA cover statements are kept for portability but the numbers come from
covergroups; and functional coverage is saved per run with `-cov_db_name` and
merged with `xcrg` at the end of the regression. All HDL, filelists and shell
scripts are stored with LF endings (enforced by `.gitattributes`); a CRLF shell
script fails on Linux with `bad interpreter: /bin/bash^M`, so if you hit that, run
`sed -i 's/\r$//' sim/vivado/*.sh`.

## Limitations and next steps

- **No register model.** The DUT has no memory-mapped registers, so a RAL has
  nothing to abstract. Doing it meaningfully would mean first adding a CSR block
  (enable, software flush, hit/miss counters) - a design change, not a testbench
  one.
- **Non-blocking misses (MSHR)** are the biggest architectural item left, and are
  left out on purpose rather than half-finished: hit-under-miss makes read
  responses go out of order, which breaks both the monitor's queue matching and
  the scoreboard's in-order snapshot, so it needs response IDs and an ID-matching
  scoreboard.
- Async reset poisons at most one line per reset (data checks skipped there, every
  protocol / ordering / length check stays live).
- Code coverage (statement / branch / toggle) is not collected yet; `xelab -cc`
  plus `xcrg` would add it. There is no gate-level or formal run.
- Smaller RTL items: parameterise ways/sets/line size, critical-word-first fill,
  and a write buffer so a dirty eviction does not serialise in front of the fill.

## License and attribution

The RTL, the UVM environment, the SVA checker, the build scripts and the
documentation were all written for this project.

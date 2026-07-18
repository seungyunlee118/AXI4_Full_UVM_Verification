# AXI4-Full UVM Verification Environment

A complete, coverage-driven **UVM testbench** for an **AXI4-Full memory slave**,
built from scratch and run on **AMD Vivado XSim**. It includes a golden
reference model, an SVA protocol checker, functional coverage, and a pipelined
driver that exercises multiple outstanding transactions.

**It found a real bug in the RTL.**

## Highlights

| | Result |
|---|---|
| 🐛 **Bug found** | `axi_ram.v` addresses **WRAP bursts like INCR** — wrapped beats are written past the end of the wrap window. Caught by the scoreboard, reproduced by a dedicated test. |
| ✅ **Fix verified** | The *same unmodified test* passes on the upgraded `axi_ram_v2.v` — the bug is now a permanent regression guard. |
| 📊 **Coverage** | **100 %** functional coverage (82 bursts, 269 beats checked), with structurally unreachable bins justified via `ignore_bins`. |
| 🔍 **Protocol** | ~25 SVA assertions `bind`-ed into the testbench: handshake stability, payload stability, WLAST/RLAST position, illegal encodings. |
| ⚡ **Outstanding** | Pipelined driver measures real bus concurrency: `axi_ram` peaks at **2**, `axi_ram_v2` sustains **4**. |
| 🧪 **Regression** | 8 tests × 2 DUTs — all clean except the intended WRAP failure on v1. |

```
=========== AXI4 functional coverage ===========
  bursts sampled : 82
          cp_dir  100.00 %      x_burst_size  100.00 %
        cp_burst  100.00 %      x_burst_len   100.00 %
         cp_size  100.00 %      x_dir_burst   100.00 %
          cp_len  100.00 %
         cp_resp  100.00 %
       cp_region  100.00 %
         cp_strb  100.00 %
           TOTAL  100.00 %
===============================================
```

## The bug, in one picture

```
WRAP write @0x0A08, 4 beats x 4 B   (wrap window 0x0A00..0x0A0F)

  correct AXI : 0x0A08, 0x0A0C, 0x0A00, 0x0A04    <- wraps inside the window
  axi_ram     : 0x0A08, 0x0A0C, 0x0A10, 0x0A14    <- keeps incrementing
                                    ^^^^^^^^^^ outside the window
```

Reading the window back with **INCR** exposes it: `0x0A00`/`0x0A04` come back as
zeros → **24 byte mismatches**.

> A WRAP write followed by a WRAP read-back **passes** even on the broken DUT —
> it is consistently wrong on both sides, so it reads from the same wrong places
> it wrote to. Only an *asymmetric* check (write WRAP, read INCR) reveals it.
> See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Architecture

```
             sequence ──▶ sequencer ──▶ driver ──▶ ┌───────────┐
                                                   │  axi4_if  │──▶ DUT
   scoreboard ◀── analysis port ── monitor ◀────── └───────────┘     ▲
   coverage   ◀───────┘                                  SVA checker ┘
```

| Component | Role |
|-----------|------|
| `axi4_seq_item` | One AXI burst; constraints for legal stimulus (4 KB, alignment, WRAP lengths) |
| `axi4_driver` | Pipelined AXI master — one thread per channel, configurable outstanding depth |
| `axi4_monitor` | Passive, **outstanding-aware** reconstruction of bursts from the pins |
| `axi4_ref_model` | Golden byte-granular memory modelling strobes and *correct* burst addressing |
| `axi4_scoreboard` | Compares every addressed read byte against the model |
| `axi4_coverage` | Covergroup + per-coverpoint report |
| `axi4_sva` | Protocol assertions, `bind`-ed in without touching RTL or TB |

Full detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) ·
Development log & findings: [docs/PROJECT_LOG.md](docs/PROJECT_LOG.md) ·
DUT analysis: [docs/axi_ram_dut_analysis.pdf](docs/axi_ram_dut_analysis.pdf)

## Quick start

```bat
call "C:\AMDDesignTools\<version>\Vivado\settings64.bat"   :: once per shell
cd sim

run_xsim.bat                          :: default test (write + read-back)
run_xsim.bat axi4_cov_test            :: coverage closure run
run_xsim.bat axi4_wrap_test           :: reproduces the bug on v1  -> 24 mismatches
run_xsim.bat axi4_wrap_test v2        :: same test on v2           -> passes
run_xsim.bat axi4_outstanding_test v2 :: 4 concurrent bursts on the bus
run_xsim.bat axi4_base_test gui       :: waveforms
```

Success = `[MON] WRITE/READ seen: …` lines plus `UVM_ERROR : 0` / `UVM_FATAL : 0`.

### Tests

| test | purpose |
|------|---------|
| `axi4_base_test` | random write + read-back (default) |
| `axi4_write_test` / `axi4_read_test` | single-direction traffic |
| `axi4_rand_test` | mixed random read/write |
| `axi4_directed_test` | corner cases: single beat, max burst, 4 KB edge, narrow, FIXED |
| `axi4_cov_test` | coverage closure — deterministic sweeps + random mix |
| `axi4_outstanding_test` | pipelined bursts; reports peak concurrency on the bus |
| `axi4_wrap_test` | **reproduces the WRAP bug** (fails on v1 by design, passes on v2) |

Add `v2` to any command to target `axi_ram_v2` instead of `axi_ram`.

## Directory layout

```
├── rtl/
│   ├── axi_ram.v              # DUT v1 — AXI4-Full RAM slave (Alex Forencich, MIT)
│   └── Axi_ram_v2.v           # DUT v2 — proper WRAP + outstanding transactions
├── tb/
│   ├── axi4_if.sv             # AXI4 interface (5 channels, clocking, modports)
│   ├── axi4_sva.sv            # SVA protocol checker, bind-ed into tb_top
│   ├── axi4_pkg.sv            # UVM package: widths, enums, class includes
│   ├── tb_top.sv              # UVM top: interface + DUT + run_test()
│   └── uvm/
│       ├── axi4_seq_item.svh      # transaction (uvm_sequence_item)
│       ├── axi4_agent_cfg.svh     # agent config (vif, active/passive, outstanding)
│       ├── axi4_driver.svh        # pipelined AXI master driver
│       ├── axi4_monitor.svh       # outstanding-aware monitor + analysis port
│       ├── axi4_agent.svh         # agent (sequencer / driver / monitor)
│       ├── axi4_ref_model.svh     # golden memory model
│       ├── axi4_scoreboard.svh    # byte-level checker
│       ├── axi4_coverage.svh      # functional coverage collector
│       ├── axi4_env.svh           # environment
│       ├── axi4_sequences.svh     # stimulus sequences
│       └── axi4_base_test.svh     # tests
├── sim/
│   ├── run_xsim.bat           # Vivado XSim build + run (primary)
│   ├── wave.tcl               # waveform setup for GUI runs
│   ├── run.bat                # Questa compile-check
│   └── cov_report.bat         # xcrg report (needs a PRO licence)
└── docs/
    ├── ARCHITECTURE.md
    ├── PROJECT_LOG.md
    └── axi_ram_dut_analysis.pdf
```

## DUT summary

- Full AXI4 slave: 5 channels (AW / W / B / AR / R)
- `DATA_WIDTH=32`, `ADDR_WIDTH=16`, `STRB_WIDTH=4`, `ID_WIDTH=8`
- Write path: 3-state FSM (IDLE / BURST / RESP); read path: 2-state FSM
- Known limitations: WRAP addressing (v1), hardcoded `BRESP`/`RRESP` = `OKAY`,
  `LOCK`/exclusive access ignored

## Notes on tooling

Coverage collection and UVM run on the **free Vivado Basic tier**. Two things do
not: Vivado's `xcrg` HTML coverage report (PRO tier only — the testbench prints
its own per-coverpoint report instead), and Questa FPGA **Starter** Edition,
which has no `svverification` licence and so cannot run `randomize()`, UVM or
covergroups at all. `sim/run.bat` still uses Questa as a fast compile/syntax
check. Details in [docs/PROJECT_LOG.md](docs/PROJECT_LOG.md).

## License & attribution

- `rtl/axi_ram.v` is from Alex Forencich's
  [verilog-axi](https://github.com/alexforencich/verilog-axi) project, under the
  **MIT License**; the original copyright header is kept intact in the file.
- `rtl/Axi_ram_v2.v` is a derivative work built on that module (proper WRAP
  addressing + outstanding transaction support) and carries the same notice.
- Everything else — the UVM environment, the SVA checker, the run scripts and
  the documentation — was written for this project.

# AXI4-Full UVM Verification Project

A step-by-step UVM verification environment for an **AXI4-Full memory slave**
(`axi_ram.v` from Alex Forencich's [verilog-axi](https://github.com/alexforencich/verilog-axi)
library). Primary simulator: **AMD Vivado XSim** (free, supports UVM +
constrained random + coverage).

> Note: the machine's only Questa license is the free **FPGA Starter Edition**,
> which cannot run `randomize()`, UVM, or covergroups. See
> [docs/PROJECT_LOG.md](docs/PROJECT_LOG.md) for the license investigation and
> the decision to use XSim. `sim/run.bat` (Questa) still works if you have a
> verification-licensed Questa.

The goal is to grow a complete, coverage-driven UVM testbench week by week and,
along the way, to actually find the DUT's real limitations (WRAP bursts,
outstanding transactions, hardcoded responses).

## Directory layout

```
axi4_full_uvm/
├── rtl/
│   ├── axi_ram.v          # DUT — AXI4-Full RAM slave (Alex Forencich, MIT)
│   └── Axi_ram_v2.v       # local variant / experiments
├── tb/
│   ├── axi4_if.sv         # AXI4 interface (5 channels, clocking, modports)
│   ├── axi4_pkg.sv        # UVM package: widths, enums, includes all classes
│   ├── tb_top.sv          # UVM top: interface + DUT + run_test()
│   └── uvm/               # UVM classes
│       ├── axi4_seq_item.svh   # transaction (uvm_sequence_item)
│       ├── axi4_agent_cfg.svh  # agent config (vif handle, active/passive)
│       ├── axi4_driver.svh     # AXI master driver
│       ├── axi4_monitor.svh    # passive monitor + analysis port
│       ├── axi4_agent.svh      # agent (sequencer/driver/monitor)
│       ├── axi4_env.svh        # environment
│       ├── axi4_sequences.svh  # write/read/rand/wr_rd sequences
│       └── axi4_base_test.svh  # base test + write/read/rand tests
├── sim/
│   ├── run_xsim.bat       # Vivado XSim build + run (primary; -L uvm)
│   └── run.bat            # Questa compile-check (Starter can't run UVM)
├── docs/
│   ├── axi_ram_dut_analysis.pdf   # detailed DUT analysis (12 pages)
│   ├── ARCHITECTURE.md            # UVM testbench architecture + diagram
│   └── PROJECT_LOG.md             # plan, weekly roadmap, sim cheatsheets
├── .gitignore
└── README.md
```

## Quick start

**Vivado XSim (primary):**
```bat
call "C:\AMDDesignTools\2026.1\Vivado\settings64.bat"   :: once per shell
cd sim
run_xsim.bat                    :: default test (write + readback)
run_xsim.bat axi4_rand_test     :: mixed random read/write
run_xsim.bat axi4_write_test gui:: a specific test in the GUI
```
Requires the node-locked license at `C:\Users\<user>\.Xilinx\Xilinx.lic`
(Vivado Basic tier includes the `Vivado_Simulation` feature).

**Questa (only with a verification license):**
```bat
cd sim
run.bat                 :: compiles on Starter, but randomize() needs a license
```

Success = per-transaction `[MON] WRITE/READ seen: …` lines and a report summary
with `UVM_ERROR : 0` / `UVM_FATAL : 0`.

## DUT summary

- Interface: full AXI4 (5 channels: AW / W / B / AR / R)
- Default params: `DATA_WIDTH=32`, `ADDR_WIDTH=16`, `STRB_WIDTH=4`, `ID_WIDTH=8`
- Write path: 3-state FSM (IDLE / BURST / RESP)
- Read path: 2-state FSM
- Known limitations (verification targets): WRAP burst handling, no outstanding
  transactions, hardcoded `BRESP`/`RRESP`, several ignored signals

See [docs/axi_ram_dut_analysis.pdf](docs/axi_ram_dut_analysis.pdf) for the full
breakdown.

## Roadmap

| Week | Focus | Status |
|------|-------|--------|
| 1 | Sanity TB — DUT compiles & runs under clk/reset | ✅ done |
| 2 | SystemVerilog interface + transaction class | ✅ (item upgraded to UVM in Wk3) |
| 3 | UVM: agent (driver / sequencer / monitor), env, tests | ✅ **runs on XSim, UVM_ERROR 0** |
| 4 | Scoreboard + reference model, directed tests | ✅ **found a real DUT bug** |
| 5 | Functional coverage + coverage report | ⬜ |

### Result so far

The scoreboard checks every read byte against an independent golden model.
Clean regression (`axi4_base_test`, `axi4_directed_test`) passes with
`UVM_ERROR : 0`; `axi4_wrap_test` reproduces a genuine DUT bug — **WRAP bursts
are addressed like INCR**, so wrapped beats are written past the end of the
window (24 byte mismatches). See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

See [docs/PROJECT_LOG.md](docs/PROJECT_LOG.md) for details and the Questa
command cheatsheet.

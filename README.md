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
│   ├── axi4_pkg.sv        # AXI enums + axi4_txn transaction class
│   ├── axi4_if.sv         # AXI4 interface (5 channels, clocking, modports)
│   └── tb_top.sv          # TB top: interface + DUT + randomization smoke test
├── sim/
│   ├── run_xsim.bat       # Vivado XSim build + run (primary)
│   └── run.bat            # Questa compile + run (needs verification license)
├── docs/
│   ├── axi_ram_dut_analysis.pdf   # detailed DUT analysis (12 pages)
│   └── PROJECT_LOG.md             # plan, weekly roadmap, Questa cheatsheet
├── .gitignore
└── README.md
```

## Quick start

**Vivado XSim (primary):**
```bat
call "C:\Xilinx\Vivado\<ver>\settings64.bat"   :: once per shell
cd sim
run_xsim.bat            :: batch mode
run_xsim.bat gui        :: GUI mode with waveforms
```

**Questa (only with a verification license):**
```bat
cd sim
run.bat                 :: compiles on Starter, but randomize() needs a license
```

Success = 6 randomized `axi4_txn#N …` lines, then `s_axi_awready = 1` and
`s_axi_arready = 1` after reset, no compile errors, clean `$finish`.

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
| 2 | SystemVerilog interface + transaction class | 🟡 code done, run pending Vivado |
| 3 | UVM: agent (driver / sequencer / monitor), base test | ⬜ |
| 4 | Scoreboard + reference model, directed tests | ⬜ |
| 5 | Functional coverage + coverage report | ⬜ |

See [docs/PROJECT_LOG.md](docs/PROJECT_LOG.md) for details and the Questa
command cheatsheet.

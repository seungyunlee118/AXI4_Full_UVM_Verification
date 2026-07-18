# AXI4-Full UVM Verification Project

A step-by-step UVM verification environment for an **AXI4-Full memory slave**
(`axi_ram.v` from Alex Forencich's [verilog-axi](https://github.com/alexforencich/verilog-axi)
library). Built and simulated with **Siemens Questa**.

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
│   └── tb_top.sv          # Week 1 sanity testbench
├── sim/
│   └── run.bat            # Questa compile + run script (batch / gui)
├── docs/
│   ├── axi_ram_dut_analysis.pdf   # detailed DUT analysis (12 pages)
│   └── PROJECT_LOG.md             # plan, weekly roadmap, Questa cheatsheet
├── .gitignore
└── README.md
```

## Quick start (Questa)

```bat
cd sim
run.bat            :: batch mode — check transcript for awready=1, arready=1
run.bat gui        :: GUI mode — waveforms auto-added, run -all
```

Success = `s_axi_awready = 1` and `s_axi_arready = 1` after reset, no compile
errors, clean `$finish`.

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
| 2 | SystemVerilog interface + transaction class | ▶ next |
| 3 | UVM: agent (driver / sequencer / monitor), base test | ⬜ |
| 4 | Scoreboard + reference model, directed tests | ⬜ |
| 5 | Functional coverage + coverage report | ⬜ |

See [docs/PROJECT_LOG.md](docs/PROJECT_LOG.md) for details and the Questa
command cheatsheet.

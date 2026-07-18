# Project Log — AXI4-Full UVM Verification

> Migrated from a Claude web chat (2026-07). This file preserves the plan,
> decisions, and Questa command reference so work can continue in this repo.

## Toolchain decision

- **Simulator: Siemens Questa** (chosen over other options — user is already
  familiar with it, industry standard, resume-relevant).
- DUT: `axi_ram.v` from Alex Forencich's `verilog-axi` (MIT license).
- Waveform dump via `$dumpfile("waves.vcd")` + `$dumpvars`.

## Weekly roadmap

| Week | Deliverable |
|------|-------------|
| 1 | Sanity testbench — `tb_top.sv` drives clk/reset, no AXI traffic; confirm DUT is alive (`awready=1, arready=1`). **DONE.** |
| 2 | SystemVerilog **interface** (`axi4_if`) + **transaction** class (`axi4_txn`). |
| 3 | UVM agent: driver, sequencer, monitor + `base_test`. |
| 4 | Scoreboard + reference model; directed write/read burst tests. |
| 5 | Functional coverage (covergroups) + merged coverage report (HTML). |

## Week 1 — status: ✅ complete

Files:
- `tb/tb_top.sv` — sanity TB (all AXI inputs tied off, checks handshake readies).
- `sim/run.bat` — Questa compile+run (batch and `gui` modes).

Success criteria (all met):
- `s_axi_awready = 1`, `s_axi_arready = 1` after reset.
- Clock toggles at 10 ns period; reset high for first 100 ns then low.
- Clean `$finish`, no compile errors.

## Week 2 — next up

Goal: replace tied-off signals with a proper **interface** and a **transaction**
object, in preparation for a UVM driver.

Planned pieces:
1. `tb/axi4_if.sv` — SystemVerilog interface bundling all 5 AXI channels, with
   `clocking` blocks and `modport`s (master/monitor).
2. `tb/axi4_txn.sv` — transaction class: `id`, `addr`, `len`, `size`, `burst`,
   `data[]`, `strb[]`, `resp`, with `rand` fields + constraints.
3. Update `tb_top.sv` to instantiate the interface and connect it to the DUT.

## Questa command cheatsheet

### Compile / elaborate / run flow
```
vlib work                     # create work library (once)
vmap work work                # map logical->physical (auto if names match)
vlog -sv <file>               # compile SystemVerilog
vsim -c tb_top -do "run -all; quit"   # batch run
vsim tb_top                   # GUI
```

### Useful vlog options
- `-sv` — SystemVerilog mode
- `-work <lib>` — target library
- `+incdir+<path>` — include path (needed for UVM)
- `+define+<MACRO>` — pass `define macro
- `-lint` — enable lint warnings (recommended)
- `-timescale 1ns/1ps` — force timescale

### Useful vsim options
- `-c` — command-line (batch) mode
- `-do "<tcl>"` — run TCL commands on start
- `-voptargs=+acc` — **required** for full waveform signal access
- `-suppress <code>` — suppress a warning
- `-onfinish exit|stop|final` — behavior on `$finish`
- `+UVM_TESTNAME=<test>` — select UVM test (Week 3+)

### UVM (Week 3+)
```
vlog -sv +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv ..\tb\tb_top.sv
vsim -c -voptargs=+acc +UVM_TESTNAME=base_test +UVM_VERBOSITY=UVM_MEDIUM \
     -do "run -all; quit -f" tb_top
```
Questa ships UVM built in — `-uvmhome` / `vsim -uvmcontrol=trace` also available.

### Coverage (Week 5+)
```
vsim -coverage tb_top -do "run -all; coverage save cov.ucdb; quit"
vcover merge merged.ucdb cov1.ucdb cov2.ucdb
vcover report -html -htmldir cov_report merged.ucdb
```

### GUI interactive (debugging)
```
add wave -r /tb_top/*     ; # add all signals
run 100ns                 ; # run 100 ns
run -all                  ; # run to $finish
restart -f                ; # restart sim
```

## Common Questa errors & fixes
- `(vsim-3033) Instantiation of 'axi_ram' failed` → compile `axi_ram.v` **before**
  `tb_top.sv`.
- `(vlog-2110) Illegal reference to net` → declare TB signals as `logic`, not `wire`.
- Waveform empty / signals missing → forgot `-voptargs=+acc`.
- `License request failed for feature 'msimhdlsim'` → license server/path issue.
- `.bat` line-continuation `^` ignored → save the file as ANSI (not UTF-8 BOM).

## DUT reference

Full analysis in `docs/axi_ram_dut_analysis.pdf` (12 pages):
1. Overview (verilog-axi structure + axi_ram.v)
2. Parameters (DATA/ADDR/STRB widths)
3. Ports (5 AXI channels)
4. Memory structure (byte↔word, VALID_ADDR_WIDTH, byte lanes)
5. Write-path FSM (IDLE/BURST/RESP) + timing
6. Read-path FSM (2-state) + comparison
7. DUT constraints (WRAP burst bug, no outstanding, hardcoded responses, ignored signals)
8. Verification appeal points (bug list, resume bullet drafts)
9. Appendix: FSM syntax concepts (`localparam`, hardware mapping)

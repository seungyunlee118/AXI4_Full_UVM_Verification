# Project Log — AXI4-Full UVM Verification

> Migrated from a Claude web chat (2026-07). This file preserves the plan,
> decisions, and Questa command reference so work can continue in this repo.

## Toolchain decision

- DUT: `axi_ram.v` from Alex Forencich's `verilog-axi` (MIT license).
- Waveform dump via `$dumpfile("waves.vcd")` + `$dumpvars`.
- Originally planned on **Siemens Questa** (familiar, resume-relevant), but the
  only license installed on this machine is the free **Questa FPGA Starter
  Edition** — see the license note below. **Primary simulator switched to
  Vivado XSim** (2026-07-17).

## Simulator / license note (2026-07-17)

While running the Week 2 testbench on the installed Questa, `randomize()`
failed with:

```
** Error: Failure to checkout svverification license feature.
** Fatal: (vsim-7099) Unable to check out a verification license for randomize()
```

Investigation:
- Installed sim: `C:\altera_lite\25.1std\questa_fse` = **Questa Altera Starter
  FPGA Edition** (free).
- License file `C:\altera_lite\LR-168512_License.dat` contains only feature
  `intelqsimstarter`.
- The Starter edition has **no `svverification` license**, so it cannot run
  constrained randomization (`randomize()`), the UVM class library, or
  functional coverage (covergroups).
- Confirmed still-working on Starter: compile/elaborate, waveforms, classes/OOP,
  mailboxes, and `$urandom` / `$urandom_range` (no license needed).

**Decision:** move to **AMD Vivado XSim** (free, supports UVM + constrained
random + basic functional coverage) to keep the UVM roadmap intact.
Alternatives considered: full/licensed Questa (if available via
company/university), or a non-UVM `$urandom`-based TB on the Starter edition.

### How to run
- **XSim (primary):** `sim\run_xsim.bat` (needs Vivado on PATH; run its
  `settings64.bat` first). `run_xsim.bat gui` for waveforms.
- **Questa (only with a verification license):** `sim\run.bat` — compiles fine
  on Starter but `randomize()` will fatal without the svverification feature.

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

## Week 2 — status: 🟡 code written, run pending Vivado install

Goal: replace tied-off signals with a proper **interface** and a **transaction**
object, in preparation for a UVM driver.

Delivered:
1. `tb/axi4_if.sv` — SystemVerilog interface bundling all 5 AXI channels, with
   `master_cb` / `monitor_cb` clocking blocks and `master`/`monitor` modports.
2. `tb/axi4_pkg.sv` — package with AXI enums (`axi_burst_e`, `axi_resp_e`,
   `axi_dir_e`) + parameterized `axi4_txn` class: `rand` fields
   (`id/addr/len/size/burst/dir/data[]/strb[]`), constraints (bounded len,
   size ≤ bus width, INCR-weighted burst dist, WRAP legal lengths, size
   alignment, 4 KB boundary, payload sizing), and `clone`/`compare`/
   `convert2string` helpers. Default config typedef `axi4_txn_t` (32b/16b).
3. `tb/tb_top.sv` — instantiates the interface, wires the DUT through it, keeps
   the Week 1 sanity check, and randomizes 6 transactions as a smoke test.
4. `sim/run_xsim.bat` — Vivado XSim build+run script.

Verification status:
- ✅ Compiles + elaborates clean on Questa Starter (Errors 0, Warnings 0).
- Note: in Week 3 the plain `axi4_txn` class was **upgraded to a UVM
  `uvm_sequence_item`** (`axi4_seq_item`) and `axi4_pkg.sv` became the UVM
  include hub, so the standalone 6-transaction smoke test in `tb_top` was
  replaced by `run_test()`. The interface (`axi4_if.sv`) carries over unchanged.

## Week 3 — status: 🟢 code written + compile-verified, run pending Vivado

Goal: a full UVM agent (sequencer + driver + monitor) driving/observing real
AXI traffic, plus an env and tests. See `docs/ARCHITECTURE.md` for the diagram.

Delivered (all under `tb/uvm/`, included by `axi4_pkg.sv`):
1. `axi4_seq_item.svh` — `uvm_sequence_item`; same constraints as Week 2 plus
   `convert2string` / `do_copy` / `do_compare` (manual, not field macros).
2. `axi4_agent_cfg.svh` — cfg object (virtual interface handle + active/passive).
3. `axi4_driver.svh` — `uvm_driver`; AXI master protocol. Write drives AW‖W
   concurrently (`fork`) then B; read drives AR then collects R beats. Drives
   through `master_cb`.
4. `axi4_monitor.svh` — `uvm_monitor`; rebuilds write/read bursts from the pins
   and broadcasts them on an analysis port (feeds the Week 4 scoreboard).
5. `axi4_agent.svh` — `uvm_agent` (+ `axi4_sequencer` typedef); active/passive.
6. `axi4_env.svh` — `uvm_env` container.
7. `axi4_sequences.svh` — base / write / read / rand / **wr_rd** (write then read
   the same region back, sets up self-checking).
8. `axi4_base_test.svh` — `uvm_test` (+ write/read/rand tests via `get_seq()`
   override); grabs the vif from `config_db`, builds env, runs a sequence.
9. `tb/tb_top.sv` — rewritten for UVM: publishes vif, calls `run_test()`.
10. `sim/run_xsim.bat` — updated for UVM (`-L uvm`, test selection).

Verification status:
- ✅ **Whole env compiles clean (Errors 0, Warnings 0)** on Questa Starter using
  its built-in UVM (1.1d) — a real syntax/type/structure check. `sim\run.bat`
  does this compile-only check on the Starter edition.
- ⏳ Runtime NOT yet exercised (Starter can't run UVM). Once Vivado is installed:
  `cd sim && run_xsim.bat` → expect `print_topology`, per-transaction `DRV`/`MON`
  log lines, and `UVM_ERROR : 0`. Try `run_xsim.bat axi4_write_test` etc.

Local note: the Questa built-in UVM is 1.1d; XSim ships 1.2. The code only uses
API common to both. When compile-checking on Questa, do NOT add a `+incdir` to
the uvm-1.2 sources or the 1.2 macros clash with the 1.1d library.

## Vivado XSim cheatsheet (primary flow)

```
xvlog --sv <files...>              # compile (package first)
xelab -debug typical tb_top -s sim # elaborate -> snapshot "sim"
xsim sim -runall                   # batch run
xsim sim -gui                      # GUI + waveforms
```
UVM (Week 3+): add `-L uvm` to xvlog/xelab and `` `include "uvm_macros.svh" `` +
`import uvm_pkg::*;`. XSim ships a built-in UVM library.

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

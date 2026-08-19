# DPI-C Golden Memory Model

The AXI4 scoreboard's reference memory implemented in **C** and driven from
SystemVerilog through the **DPI-C** interface — the standard way to bring an
independent C golden model into a UVM testbench. The SystemVerilog side owns the
AXI addressing (correct FIXED/INCR/WRAP + byte lanes); the C side
(`axi4_ref_model.c`) owns the byte-addressable storage, kept independent of the
RTL so it cannot inherit the DUT's bugs.

## Files

| File | Role |
|------|------|
| `axi4_ref_model.c` | Golden byte memory: `axi_ref_reset / write_byte / read_byte` |
| `dpi_demo_tb.sv` | Self-contained demo exercising the C model over DPI-C |

`dpi_demo_tb.sv` reproduces the two non-trivial modelling rules the scoreboard
relies on — **write-strobe byte masking** and **narrow transfers folding into a
single aligned bus word** — and checks them against the C golden memory.

## Run it

### EDA Playground (recommended)
1. New playground → **Testbench+Design: SystemVerilog/Verilog**
2. Tools & Simulators → **Mentor Questa** (or Aldec Riviera-PRO / Synopsys VCS)
3. Add both files (`axi4_ref_model.c`, `dpi_demo_tb.sv`); top module `dpi_demo_tb`
4. Run → expect `DPI_DEMO_PASS`

### Vivado XSim (this small demo runs locally)
```bash
xsc axi4_ref_model.c
xvlog --sv dpi_demo_tb.sv
xelab dpi_demo_tb -sv_lib dpi -s demo
xsim demo -runall          # -> DPI_DEMO_PASS
```

### Questa (command line)
```bash
vlib work
vlog -sv -dpiheader dpi.h dpi_demo_tb.sv
gcc -shared -fPIC -o axi4_ref_model.so axi4_ref_model.c -I$QUESTA_HOME/include
vsim -c dpi_demo_tb -sv_lib axi4_ref_model -do "run -all; quit"
```

## Note on Vivado XSim + full UVM

This *small* demo runs fine on Vivado XSim, but wiring the same C model into the
**full UVM environment** trips a Vivado XSim (free tier) code-generation bug:
xelab emits the DPI wrapper as C++ (`namespace`, `extern "C"`, `<cstring>`) yet
compiles it with the C compiler, so elaboration fails with
`[XSIM 43-3409] Failed to compile generated C file`. It is not a code issue —
DPI-C + UVM runs cleanly on Questa/VCS. The UVM scoreboard therefore keeps its
SystemVerilog reference model on XSim, while this DPI-C variant demonstrates the
C-golden-model-over-DPI flow on a fully-licensed simulator.

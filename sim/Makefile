# =============================================================
# AXI4-Full UVM — Vivado XSim Makefile (Linux / WSL2)
#
# Mirrors run_xsim.bat for a Linux flow. Source Vivado first:
#     source /tools/Xilinx/2026.1/Vivado/settings64.sh   (adjust path)
#
# Usage:
#     make                          # default test (axi4_base_test), v1
#     make TEST=axi4_cov_test       # a specific test
#     make TEST=axi4_wrap_test DUT=v2
#     make gui                      # open the XSim GUI (all signals)
#     make gui WAVE=wave_write.tcl  # GUI, write-path waveforms only
#     make regress                  # run the whole test list, report pass/fail
#     make regress SEEDS="1 2 3"    # multi-seed regression
#     make clean
# =============================================================

# ---- knobs -------------------------------------------------
TEST   ?= axi4_base_test
DUT    ?=
SEEDS  ?= 1
WAVE   ?= wave.tcl
TOP     = tb_top
SNAP    = tb_top_sim

# axi_ram (default) vs axi_ram_v2
ifeq ($(DUT),v2)
  DUTOPT  = -d DUT_V2
  DUTNAME = axi_ram_v2
else
  DUTOPT  =
  DUTNAME = axi_ram (v1)
endif

RTL     = ../rtl/axi_ram.v ../rtl/Axi_ram_v2.v
SVSRC   = ../tb/axi4_if.sv ../tb/axi4_sva.sv ../tb/axi4_pkg.sv ../tb/tb_top.sv
INCDIR  = -i ../tb/uvm

XVLOG   = xvlog --sv -L uvm $(INCDIR) $(DUTOPT)
XELAB   = xelab -debug all -L uvm -timescale 1ns/1ps
XSIM    = xsim

# The elaboration snapshot depends on the DUT choice, so re-elaborate
# whenever DUT changes by keying a stamp file off DUTNAME.
STAMP   = .build_$(if $(DUTOPT),v2,v1)

# ---- default: build + run one test -------------------------
.PHONY: all run
all: run

run: $(STAMP)
	@echo "=== DUT: $(DUTNAME) | TEST: $(TEST) ==="
	$(XSIM) $(SNAP) -runall -testplusarg "UVM_TESTNAME=$(TEST)"

# ---- compile + elaborate (once per DUT) --------------------
$(STAMP): $(RTL) $(SVSRC) $(wildcard ../tb/uvm/*.svh) Makefile
	@echo "=== Compiling ($(DUTNAME)) ==="
	$(XVLOG) $(RTL) $(SVSRC)
	@echo "=== Elaborating ==="
	$(XELAB) $(TOP) -s $(SNAP)
	@touch $(STAMP)

# ---- GUI (waveforms) ---------------------------------------
.PHONY: gui
gui: $(STAMP)
	@echo "=== DUT: $(DUTNAME) | TEST: $(TEST) | waves: $(WAVE) ==="
	$(XSIM) $(SNAP) -gui -tclbatch $(WAVE) -testplusarg "UVM_TESTNAME=$(TEST)"

# ---- regression: every test x every seed -------------------
# axi4_wrap_test is expected to FAIL on v1 (documents the DUT bug), so it is
# not part of the clean list; run it explicitly with `make TEST=axi4_wrap_test`.
REGRESS_TESTS = axi4_base_test axi4_directed_test axi4_write_test \
                axi4_read_test axi4_rand_test axi4_cov_test axi4_outstanding_test

.PHONY: regress
regress: $(STAMP)
	@fail=0; \
	for t in $(REGRESS_TESTS); do \
	  for s in $(SEEDS); do \
	    echo "--- $$t (seed $$s) ---"; \
	    $(XSIM) $(SNAP) -runall -sv_seed $$s -testplusarg "UVM_TESTNAME=$$t" \
	      | grep -E "UVM_ERROR :|scoreboard:" ; \
	    if $(XSIM) $(SNAP) -runall -sv_seed $$s -testplusarg "UVM_TESTNAME=$$t" \
	         | grep -q "UVM_ERROR :    0"; then echo "  PASS"; \
	    else echo "  *** FAIL: $$t seed $$s ***"; fail=1; fi; \
	  done; \
	done; \
	if [ $$fail -eq 0 ]; then echo "=== REGRESSION PASS ==="; \
	else echo "=== REGRESSION FAIL ==="; exit 1; fi

.PHONY: clean
clean:
	rm -rf xsim.dir .Xil *.jou *.log *.pb *.wdb *.wdb.wcfg xsim.covdb .build_v1 .build_v2
	@echo "cleaned"

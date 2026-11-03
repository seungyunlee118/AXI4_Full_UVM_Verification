# =============================================================
# AXI4-Full UVM — Cadence Xcelium (xrun) flow
#
#     make                                  # axi4_base_test on axi_ram (v1)
#     make TEST=axi4_wrap_test DUT=v2 SEED=7
#     make XPROP=C                          # X-propagation build (C or F)
#     make WAVE=1                           # SHM waveforms -> waves.shm
#     make view                             # open waves.shm in SimVision
#     make regress                          # regress.py: 9 tests x 5 seeds x 2 DUTs
#     make mutate                           # mutate.py: bug-injection campaign on v2
#     make clean
#
# Pass/fail uses ../judge.py, the same rule as the XSim Makefile.
# xrun's own exit code is not used: on the lab host it is 1 for every run,
# because of the known IMPDLL message (see ../judge.py).
# =============================================================

SHELL := /bin/bash

TEST  ?= axi4_base_test
DUT   ?= v1
SEED  ?= 1
XPROP ?=
WAVE  ?= 0

LIBDIR := xcelium_$(DUT)$(if $(XPROP),_xprop$(XPROP)).d
EXPECT := $(if $(and $(filter v1,$(DUT)),$(filter axi4_wrap_test,$(TEST))),xfail,pass)

OPTS := -F xrun.args -F files.f -xmlibdirname $(LIBDIR) \
        -covtest $(DUT)_$(TEST)_$(SEED) -svseed $(SEED) +UVM_TESTNAME=$(TEST)
ifeq ($(DUT),v2)
OPTS += -define DUT_V2
endif
ifneq ($(XPROP),)
OPTS += -xprop $(XPROP)
endif
ifeq ($(WAVE),1)
OPTS += -access +r -input waves.tcl
endif

.PHONY: all run view regress mutate clean

all: run

run:
	@source ./xcelium_env.sh && xrun $(OPTS) -l xrun.log > /dev/null; \
	echo "=== $(TEST) | DUT $(DUT) | seed $(SEED) ==="; \
	grep -E "scoreboard:|outstanding on the bus|^ +TOTAL|^UVM_(ERROR|FATAL) :" xrun.log; \
	grep -E "^UVM_(ERROR|FATAL) .* @ " xrun.log | head -5; \
	verdict=$$(python3 ../judge.py xrun.log --expect $(EXPECT)); rc=$$?; \
	echo "=== $$verdict ($(EXPECT) expected) ==="; exit $$rc

# Plain `simvision` starts the 32-bit binary, which needs a 32-bit libX11.
view:
	@source ./xcelium_env.sh && simvision -64bit waves.shm &

regress:
	@source ./xcelium_env.sh && python3 regress.py

mutate:
	@source ./xcelium_env.sh && python3 mutate.py

clean:
	rm -rf xcelium*.d cov_work regress regress_* mutants waves.shm .simvision __pycache__ ../__pycache__
	rm -f *.log *.history *.key *.diag *.vcd xmsim.*
	@echo cleaned

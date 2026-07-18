# =============================================================
# XSim waveform setup
#
# XSim only records signals that were added/logged BEFORE the run,
# so this script adds them first and only then runs the simulation.
# Used by run_xsim.bat in GUI mode (xsim -gui -tclbatch wave.tcl).
#
# NOTE: we deliberately do NOT use "add_wave -r /tb_top/*" because
# that recurses into the DUT and adds its 16K-entry memory array,
# which makes the wave database huge and the GUI sluggish.
# =============================================================

# Clock / reset
add_wave /tb_top/clk
add_wave /tb_top/rst

# All AXI interface signals (AW / W / B / AR / R channels)
add_wave -r /tb_top/axi/*

# DUT handshake outputs + FSM state (handy for debugging the driver)
add_wave /tb_top/dut/write_state_reg
add_wave /tb_top/dut/read_state_reg

run -all

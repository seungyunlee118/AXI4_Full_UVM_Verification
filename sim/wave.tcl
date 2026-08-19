# =============================================================
# XSim waveform setup (all AXI signals)
#
# XSim only records signals added BEFORE the run, so this script adds
# them first and only then runs. Used by run_xsim.bat / Makefile GUI mode.
#
# DUT-internal signals go through add_opt, which checks the signal exists
# first. Without that guard a missing/optimized signal makes add_wave
# raise a hard error that ABORTS this script before "run -all" -> the
# wave window ends up empty. (This bit us on Linux XSim, where -debug
# typical optimized away the FSM regs.)  Build with `-debug all` (the
# Makefile/run_xsim.bat do) to keep the DUT internals visible.
#
# We deliberately avoid "add_wave -r /tb_top/*": it would pull in the
# DUT's 16K-entry memory array and bloat the wave database.
# =============================================================

proc add_opt {path args} {
    if {[llength [get_objects -quiet $path]] > 0} {
        eval add_wave $args {$path}
    } else {
        puts "wave.tcl: skipping (not found) $path"
    }
}

# Clock / reset
add_wave /tb_top/clk
add_wave /tb_top/rst

# All AXI interface signals (AW / W / B / AR / R channels)
add_wave -r /tb_top/axi/*

# DUT-internal FSM state (only whichever DUT is built shows up)
add_opt /tb_top/dut/write_state_reg          ;# axi_ram   (v1) write FSM
add_opt /tb_top/dut/read_state_reg           ;# axi_ram   (v1) read  FSM
add_opt /tb_top/dut/w_state                  ;# axi_ram_v2 write FSM
add_opt /tb_top/dut/r_state                  ;# axi_ram_v2 read  FSM

run -all

# =============================================================
# Write-path waveform  (AW / W / B channels only)
#
# Used by:  run_xsim.bat <test> gui wr
#
# valid/ready pairs are kept adjacent on purpose - finding the cycle
# where BOTH are high is the whole skill of reading an AXI waveform.
#
# XSim only records signals added BEFORE the run, hence "run -all" last.
# DUT-internal names differ between axi_ram (v1) and axi_ram_v2, so those
# go through add_opt, which silently skips whatever this DUT does not have.
# (catch{} does NOT work here: add_wave prints an ERROR but never raises a
#  TCL exception, so the message would still appear.)
# =============================================================

proc add_opt {path args} {
    if {[llength [get_objects -quiet $path]] > 0} {
        eval add_wave $args {$path}
    }
}

add_wave /tb_top/clk
add_wave /tb_top/rst

# ---- AW : write address channel ----
add_wave /tb_top/axi/awvalid
add_wave /tb_top/axi/awready
add_wave -radix hex      /tb_top/axi/awaddr
add_wave -radix unsigned /tb_top/axi/awlen
add_wave -radix unsigned /tb_top/axi/awsize
add_wave -radix bin      /tb_top/axi/awburst
add_wave -radix unsigned /tb_top/axi/awid

# ---- W : write data channel ----
add_wave /tb_top/axi/wvalid
add_wave /tb_top/axi/wready
add_wave -radix hex /tb_top/axi/wdata
add_wave -radix bin /tb_top/axi/wstrb
add_wave /tb_top/axi/wlast

# ---- B : write response channel ----
add_wave /tb_top/axi/bvalid
add_wave /tb_top/axi/bready
add_wave -radix bin      /tb_top/axi/bresp
add_wave -radix unsigned /tb_top/axi/bid

# ---- DUT internals (only whichever DUT is built shows up) ----
add_opt /tb_top/dut/write_state_reg                 ;# axi_ram   (v1) write FSM
add_opt /tb_top/dut/w_state                         ;# axi_ram_v2 write FSM
add_opt /tb_top/dut/aw_count -radix unsigned        ;# v2: AW queue occupancy
add_opt /tb_top/dut/b_count  -radix unsigned        ;# v2: B  queue occupancy

run -all

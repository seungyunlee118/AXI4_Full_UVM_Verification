# =============================================================
# Read-path waveform  (AR / R channels only)
#
# Used by:  run_xsim.bat <test> gui rd
#
# The read side is simpler than the write side: one address phase,
# then N data beats ending with RLAST. There is no separate response
# channel - RRESP rides along with each R beat.
#
# add_opt silently skips signals this DUT does not have (the FSM/queue
# names differ between axi_ram and axi_ram_v2).
# =============================================================

proc add_opt {path args} {
    if {[llength [get_objects -quiet $path]] > 0} {
        eval add_wave $args {$path}
    }
}

add_wave /tb_top/clk
add_wave /tb_top/rst

# ---- AR : read address channel ----
add_wave /tb_top/axi/arvalid
add_wave /tb_top/axi/arready
add_wave -radix hex      /tb_top/axi/araddr
add_wave -radix unsigned /tb_top/axi/arlen
add_wave -radix unsigned /tb_top/axi/arsize
add_wave -radix bin      /tb_top/axi/arburst
add_wave -radix unsigned /tb_top/axi/arid

# ---- R : read data channel ----
add_wave /tb_top/axi/rvalid
add_wave /tb_top/axi/rready
add_wave -radix hex      /tb_top/axi/rdata
add_wave /tb_top/axi/rlast
add_wave -radix bin      /tb_top/axi/rresp
add_wave -radix unsigned /tb_top/axi/rid

# ---- DUT internals (only whichever DUT is built shows up) ----
add_opt /tb_top/dut/read_state_reg                  ;# axi_ram   (v1) read FSM
add_opt /tb_top/dut/r_state                         ;# axi_ram_v2 read FSM
add_opt /tb_top/dut/ar_count -radix unsigned        ;# v2: AR queue occupancy

run -all

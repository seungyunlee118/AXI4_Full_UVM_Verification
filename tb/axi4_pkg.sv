
`ifndef AXI4_PKG_SV
`define AXI4_PKG_SV
`timescale 1ns/1ps

package axi4_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //---------------------------------------------------------
    parameter int AXI_DATA_WIDTH = 32;
    parameter int AXI_ADDR_WIDTH = 16;
    parameter int AXI_ID_WIDTH   = 8;
    parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;

    //---------------------------------------------------------
    // AXI4 protocol enums
    //---------------------------------------------------------
    typedef enum bit [1:0] {
        AXI_FIXED = 2'b00,
        AXI_INCR  = 2'b01,
        AXI_WRAP  = 2'b10
    } axi_burst_e;

    typedef enum bit [1:0] {
        AXI_OKAY   = 2'b00,
        AXI_EXOKAY = 2'b01,
        AXI_SLVERR = 2'b10,
        AXI_DECERR = 2'b11
    } axi_resp_e;

    typedef enum bit {
        AXI_READ  = 1'b0,
        AXI_WRITE = 1'b1
    } axi_dir_e;

    //---------------------------------------------------------
    // UVM classes, in dependency order
    //---------------------------------------------------------
    `include "axi4_seq_item.svh"
    `include "axi4_agent_cfg.svh"
    `include "axi4_driver.svh"
    `include "axi4_monitor.svh"
    `include "axi4_agent.svh"
    `include "axi4_ref_model.svh"
    `include "axi4_scoreboard.svh"
    `include "axi4_coverage.svh"
    `include "axi4_env.svh"
    `include "axi4_sequences.svh"
    `include "axi4_base_test.svh"

endpackage

`endif

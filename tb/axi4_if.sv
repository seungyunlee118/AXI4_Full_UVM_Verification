
`ifndef AXI4_IF_SV
`define AXI4_IF_SV
`timescale 1ns/1ps

interface axi4_if #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 16,
    parameter int STRB_WIDTH = (DATA_WIDTH/8),
    parameter int ID_WIDTH   = 8
) (
    input logic clk,
    input logic rst
);

    // ---- Write address channel (AW) ----
    logic [ID_WIDTH-1:0]   awid;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0]            awlen;
    logic [2:0]            awsize;
    logic [1:0]            awburst;
    logic                  awlock;
    logic [3:0]            awcache;
    logic [2:0]            awprot;
    logic                  awvalid;
    logic                  awready;

    // ---- Write data channel (W) ----
    logic [DATA_WIDTH-1:0] wdata;
    logic [STRB_WIDTH-1:0] wstrb;
    logic                  wlast;
    logic                  wvalid;
    logic                  wready;

    // ---- Write response channel (B) ----
    logic [ID_WIDTH-1:0]   bid;
    logic [1:0]            bresp;
    logic                  bvalid;
    logic                  bready;

    // ---- Read address channel (AR) ----
    logic [ID_WIDTH-1:0]   arid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
    logic                  arlock;
    logic [3:0]            arcache;
    logic [2:0]            arprot;
    logic                  arvalid;
    logic                  arready;

    // ---- Read data channel (R) ----
    logic [ID_WIDTH-1:0]   rid;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rlast;
    logic                  rvalid;
    logic                  rready;

    // Clocking Block
    
    //---------------------------------------------------------
    // Driver clocking block (acts as AXI master)
    //   drives *valid/payload, samples *ready and read data
    //---------------------------------------------------------
    clocking master_cb @(posedge clk);
        default input #1step output #1;
        // AW
        output awid, awaddr, awlen, awsize, awburst,
               awlock, awcache, awprot, awvalid;
        input  awready;
        // W
        output wdata, wstrb, wlast, wvalid;
        input  wready;
        // B
        input  bid, bresp, bvalid;
        output bready;
        // AR
        output arid, araddr, arlen, arsize, arburst,
               arlock, arcache, arprot, arvalid;
        input  arready;
        // R
        input  rid, rdata, rresp, rlast, rvalid;
        output rready;
    endclocking

    //---------------------------------------------------------
    // Monitor clocking block (passive: samples everything)
    //---------------------------------------------------------
    clocking monitor_cb @(posedge clk);
        default input #1step;
        input awid, awaddr, awlen, awsize, awburst,
              awlock, awcache, awprot, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst,
              arlock, arcache, arprot, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking

    modport master  (clocking master_cb,  input clk, rst);
    modport monitor (clocking monitor_cb, input clk, rst);

endinterface

`endif

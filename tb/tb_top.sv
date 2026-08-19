
`timescale 1ns/1ps
`ifdef DUT_V2
    `define DUT_MODULE axi_ram_v2
`else
    `define DUT_MODULE axi_ram
`endif

module tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi4_pkg::*;

    // Bus widths (must match axi4_pkg + the DUT instance below)
    localparam int DATA_WIDTH = 32;
    localparam int ADDR_WIDTH = 16;
    localparam int STRB_WIDTH = DATA_WIDTH/8;
    localparam int ID_WIDTH   = 8;

    // ---- Clock / reset ----
    logic clk;
    logic rst;

    initial clk = 0;
    always #5 clk = ~clk;                 // 100 MHz

    initial begin
        rst = 1'b1;
        repeat (10) @(posedge clk);       // hold reset 10 cycles
        rst = 1'b0;
    end

    // ---- Interface ----
    axi4_if #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) axi (
        .clk(clk),
        .rst(rst)
    );

    // ---- DUT ---- (module chosen by the DUT_V2 define above)
    `DUT_MODULE #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .s_axi_awid(axi.awid),
        .s_axi_awaddr(axi.awaddr),
        .s_axi_awlen(axi.awlen),
        .s_axi_awsize(axi.awsize),
        .s_axi_awburst(axi.awburst),
        .s_axi_awlock(axi.awlock),
        .s_axi_awcache(axi.awcache),
        .s_axi_awprot(axi.awprot),
        .s_axi_awvalid(axi.awvalid),
        .s_axi_awready(axi.awready),
        .s_axi_wdata(axi.wdata),
        .s_axi_wstrb(axi.wstrb),
        .s_axi_wlast(axi.wlast),
        .s_axi_wvalid(axi.wvalid),
        .s_axi_wready(axi.wready),
        .s_axi_bid(axi.bid),
        .s_axi_bresp(axi.bresp),
        .s_axi_bvalid(axi.bvalid),
        .s_axi_bready(axi.bready),
        .s_axi_arid(axi.arid),
        .s_axi_araddr(axi.araddr),
        .s_axi_arlen(axi.arlen),
        .s_axi_arsize(axi.arsize),
        .s_axi_arburst(axi.arburst),
        .s_axi_arlock(axi.arlock),
        .s_axi_arcache(axi.arcache),
        .s_axi_arprot(axi.arprot),
        .s_axi_arvalid(axi.arvalid),
        .s_axi_arready(axi.arready),
        .s_axi_rid(axi.rid),
        .s_axi_rdata(axi.rdata),
        .s_axi_rresp(axi.rresp),
        .s_axi_rlast(axi.rlast),
        .s_axi_rvalid(axi.rvalid),
        .s_axi_rready(axi.rready)
    );

    // ---- Hand the interface to the UVM world, then start the test ----
    initial begin
        uvm_config_db#(virtual axi4_if)::set(null, "*", "vif", axi);
        run_test("axi4_base_test");       // override with +UVM_TESTNAME=...
    end

    // ---- Waveform dump ----
    initial begin
        $dumpfile("waves.vcd");
        $dumpvars;
    end

endmodule

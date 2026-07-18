//=============================================================
// Week 1 Sanity Test Bench
// Purpose: verify axi_ram.v compiles and simulates cleanly
//          under clock/reset without any AXI transactions.
//=============================================================
`timescale 1ns/1ps

module tb_top;

    // Parameters (match DUT defaults)
    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 16;
    localparam STRB_WIDTH = DATA_WIDTH/8;
    localparam ID_WIDTH   = 8;

    // Clock and reset
    logic clk;
    logic rst;

    // AXI signals (all tied off to inactive values for now)
    logic [ID_WIDTH-1:0]    s_axi_awid    = '0;
    logic [ADDR_WIDTH-1:0]  s_axi_awaddr  = '0;
    logic [7:0]             s_axi_awlen   = '0;
    logic [2:0]             s_axi_awsize  = '0;
    logic [1:0]             s_axi_awburst = '0;
    logic                   s_axi_awlock  = '0;
    logic [3:0]             s_axi_awcache = '0;
    logic [2:0]             s_axi_awprot  = '0;
    logic                   s_axi_awvalid = 1'b0;
    logic                   s_axi_awready;
    logic [DATA_WIDTH-1:0]  s_axi_wdata   = '0;
    logic [STRB_WIDTH-1:0]  s_axi_wstrb   = '0;
    logic                   s_axi_wlast   = 1'b0;
    logic                   s_axi_wvalid  = 1'b0;
    logic                   s_axi_wready;
    logic [ID_WIDTH-1:0]    s_axi_bid;
    logic [1:0]             s_axi_bresp;
    logic                   s_axi_bvalid;
    logic                   s_axi_bready  = 1'b1;
    logic [ID_WIDTH-1:0]    s_axi_arid    = '0;
    logic [ADDR_WIDTH-1:0]  s_axi_araddr  = '0;
    logic [7:0]             s_axi_arlen   = '0;
    logic [2:0]             s_axi_arsize  = '0;
    logic [1:0]             s_axi_arburst = '0;
    logic                   s_axi_arlock  = '0;
    logic [3:0]             s_axi_arcache = '0;
    logic [2:0]             s_axi_arprot  = '0;
    logic                   s_axi_arvalid = 1'b0;
    logic                   s_axi_arready;
    logic [ID_WIDTH-1:0]    s_axi_rid;
    logic [DATA_WIDTH-1:0]  s_axi_rdata;
    logic [1:0]             s_axi_rresp;
    logic                   s_axi_rlast;
    logic                   s_axi_rvalid;
    logic                   s_axi_rready  = 1'b1;

    // DUT instance
    axi_ram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .s_axi_awid(s_axi_awid),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst),
        .s_axi_awlock(s_axi_awlock),
        .s_axi_awcache(s_axi_awcache),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst),
        .s_axi_arlock(s_axi_arlock),
        .s_axi_arcache(s_axi_arcache),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready)
    );

    // Clock: 10ns period = 100MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // Reset sequence
    initial begin
        rst = 1'b1;
        #100;
        rst = 1'b0;
        $display("[%0t] Reset released", $time);
    end

    // End of simulation
    initial begin
        #500;
        $display("[%0t] Sanity test complete. DUT is alive.", $time);
        $display("  s_axi_awready = %b (expect 1 after reset)", s_axi_awready);
        $display("  s_axi_arready = %b (expect 1 after reset)", s_axi_arready);
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("waves.vcd");
        $dumpvars(0, tb_top);
    end

endmodule

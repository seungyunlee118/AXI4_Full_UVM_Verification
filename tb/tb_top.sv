//=============================================================
// Week 2 Test Bench
//   - Connects the DUT through the axi4_if interface
//   - Exercises the axi4_txn transaction class (randomize + print)
//   - Still keeps the Week 1 sanity check (awready/arready == 1)
// No bus traffic is driven yet; the driver arrives in Week 3.
//=============================================================
`timescale 1ns/1ps

module tb_top;

    import axi4_pkg::*;

    // Parameters (match DUT defaults)
    localparam int DATA_WIDTH = 32;
    localparam int ADDR_WIDTH = 16;
    localparam int STRB_WIDTH = DATA_WIDTH/8;
    localparam int ID_WIDTH   = 8;

    // Clock and reset
    logic clk;
    logic rst;

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

    //---------------------------------------------------------
    // Interface instance
    //---------------------------------------------------------
    axi4_if #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) axi (
        .clk(clk),
        .rst(rst)
    );

    //---------------------------------------------------------
    // DUT instance (ports wired to the interface signals)
    //---------------------------------------------------------
    axi_ram #(
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

    //---------------------------------------------------------
    // Drive all master-side signals to their inactive values
    // (keeps the DUT quiescent, same intent as Week 1)
    //---------------------------------------------------------
    initial begin
        axi.awid    = '0; axi.awaddr  = '0; axi.awlen  = '0;
        axi.awsize  = '0; axi.awburst = '0; axi.awlock = '0;
        axi.awcache = '0; axi.awprot  = '0; axi.awvalid = 1'b0;
        axi.wdata   = '0; axi.wstrb   = '0; axi.wlast  = 1'b0;
        axi.wvalid  = 1'b0;
        axi.bready  = 1'b1;
        axi.arid    = '0; axi.araddr  = '0; axi.arlen  = '0;
        axi.arsize  = '0; axi.arburst = '0; axi.arlock = '0;
        axi.arcache = '0; axi.arprot  = '0; axi.arvalid = 1'b0;
        axi.rready  = 1'b1;
    end

    //---------------------------------------------------------
    // Week 2 smoke test: build and randomize transactions
    //---------------------------------------------------------
    initial begin
        axi4_txn_t tr;
        #120;   // wait until after reset is released
        $display("--- Week 2 transaction randomization ---");
        repeat (6) begin
            tr = new();
            if (!tr.randomize())
                $fatal(1, "axi4_txn randomize() failed");
            tr.display("  ");
        end
        $display("----------------------------------------");
    end

    //---------------------------------------------------------
    // End of simulation + sanity check
    //---------------------------------------------------------
    initial begin
        #500;
        $display("[%0t] Sanity test complete. DUT is alive.", $time);
        $display("  s_axi_awready = %b (expect 1 after reset)", axi.awready);
        $display("  s_axi_arready = %b (expect 1 after reset)", axi.arready);
        $finish;
    end

    //---------------------------------------------------------
    // Waveform dump
    //---------------------------------------------------------
    initial begin
        $dumpfile("waves.vcd");
        $dumpvars;
    end

endmodule

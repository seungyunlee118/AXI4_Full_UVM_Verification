
`ifndef AXI4_SVA_SV
`define AXI4_SVA_SV
`timescale 1ns/1ps

// ---- assertion macros (inline expansion; no property arguments) ----

// A VALID must not be withdrawn before its READY.
`define AXI_VALID_HELD(nm, vld, rdy)                                     \
    nm: assert property (@(posedge clk) disable iff (rst)                 \
        ((vld) && !(rdy)) |=> (vld))                                      \
        else $error("AXI-SVA: %s - VALID de-asserted before READY", `"nm`");

// Payload must stay stable while the transfer is stalled.
`define AXI_STABLE(nm, vld, rdy, sig)                                    \
    nm: assert property (@(posedge clk) disable iff (rst)                 \
        ((vld) && !(rdy)) |=> $stable(sig))                               \
        else $error("AXI-SVA: %s - payload changed while stalled", `"nm`");

module axi4_sva #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 16,
    parameter int STRB_WIDTH = (DATA_WIDTH/8),
    parameter int ID_WIDTH   = 8
)(
    input logic                  clk,
    input logic                  rst,
    // AW
    input logic [ID_WIDTH-1:0]   awid,
    input logic [ADDR_WIDTH-1:0] awaddr,
    input logic [7:0]            awlen,
    input logic [2:0]            awsize,
    input logic [1:0]            awburst,
    input logic                  awvalid,
    input logic                  awready,
    // W
    input logic [DATA_WIDTH-1:0] wdata,
    input logic [STRB_WIDTH-1:0] wstrb,
    input logic                  wlast,
    input logic                  wvalid,
    input logic                  wready,
    // B
    input logic [1:0]            bresp,
    input logic                  bvalid,
    input logic                  bready,
    // AR
    input logic [ID_WIDTH-1:0]   arid,
    input logic [ADDR_WIDTH-1:0] araddr,
    input logic [7:0]            arlen,
    input logic [2:0]            arsize,
    input logic [1:0]            arburst,
    input logic                  arvalid,
    input logic                  arready,
    // R
    input logic [1:0]            rresp,
    input logic                  rlast,
    input logic                  rvalid,
    input logic                  rready
);

`ifndef AXI4_NO_SVA

    //=========================================================
    // 1. VALID must never be withdrawn before READY
    //=========================================================
    `AXI_VALID_HELD(a_awvalid_held, awvalid, awready)
    `AXI_VALID_HELD(a_wvalid_held,  wvalid,  wready)
    `AXI_VALID_HELD(a_bvalid_held,  bvalid,  bready)
    `AXI_VALID_HELD(a_arvalid_held, arvalid, arready)
    `AXI_VALID_HELD(a_rvalid_held,  rvalid,  rready)

    //=========================================================
    // 2. Payload stable while a transfer is stalled
    //=========================================================
    `AXI_STABLE(a_awaddr_stable,  awvalid, awready, awaddr)
    `AXI_STABLE(a_awlen_stable,   awvalid, awready, awlen)
    `AXI_STABLE(a_awsize_stable,  awvalid, awready, awsize)
    `AXI_STABLE(a_awburst_stable, awvalid, awready, awburst)
    `AXI_STABLE(a_awid_stable,    awvalid, awready, awid)

    `AXI_STABLE(a_wdata_stable,   wvalid,  wready,  wdata)
    `AXI_STABLE(a_wstrb_stable,   wvalid,  wready,  wstrb)
    `AXI_STABLE(a_wlast_stable,   wvalid,  wready,  wlast)

    `AXI_STABLE(a_araddr_stable,  arvalid, arready, araddr)
    `AXI_STABLE(a_arlen_stable,   arvalid, arready, arlen)
    `AXI_STABLE(a_arsize_stable,  arvalid, arready, arsize)
    `AXI_STABLE(a_arburst_stable, arvalid, arready, arburst)

    `AXI_STABLE(a_bresp_stable,   bvalid,  bready,  bresp)
    `AXI_STABLE(a_rresp_stable,   rvalid,  rready,  rresp)
    `AXI_STABLE(a_rlast_stable,   rvalid,  rready,  rlast)

    //=========================================================
    // 3. Reserved / illegal encodings
    //=========================================================
    a_awburst_legal: assert property (@(posedge clk) disable iff (rst)
        awvalid |-> awburst != 2'b11)
        else $error("AXI-SVA: AWBURST uses the reserved encoding 2'b11");
    a_arburst_legal: assert property (@(posedge clk) disable iff (rst)
        arvalid |-> arburst != 2'b11)
        else $error("AXI-SVA: ARBURST uses the reserved encoding 2'b11");

    // Transfer size must fit the data bus
    a_awsize_fits: assert property (@(posedge clk) disable iff (rst)
        awvalid |-> ((1 << awsize) <= STRB_WIDTH))
        else $error("AXI-SVA: AWSIZE exceeds the data bus width");
    a_arsize_fits: assert property (@(posedge clk) disable iff (rst)
        arvalid |-> ((1 << arsize) <= STRB_WIDTH))
        else $error("AXI-SVA: ARSIZE exceeds the data bus width");

    //=========================================================
    // 4. No unknown (X/Z) on qualified control/payload
    //=========================================================
    a_aw_known: assert property (@(posedge clk) disable iff (rst)
        awvalid |-> !$isunknown({awaddr, awlen, awsize, awburst, awid}))
        else $error("AXI-SVA: X/Z on the AW channel while AWVALID");
    a_ar_known: assert property (@(posedge clk) disable iff (rst)
        arvalid |-> !$isunknown({araddr, arlen, arsize, arburst, arid}))
        else $error("AXI-SVA: X/Z on the AR channel while ARVALID");
    a_w_known: assert property (@(posedge clk) disable iff (rst)
        wvalid |-> !$isunknown({wstrb, wlast}))
        else $error("AXI-SVA: X/Z on the W channel while WVALID");

    //=========================================================
    // 5. No response may be issued while in reset
    //=========================================================
    a_no_resp_in_reset: assert property (@(posedge clk)
        rst |-> (!bvalid && !rvalid))
        else $error("AXI-SVA: BVALID/RVALID asserted during reset");

    //=========================================================
    // 6. WLAST / RLAST must land on the beat implied by the length
    //=========================================================
  
    localparam int SVA_QDEPTH = 16;

    int unsigned aw_len_mem [SVA_QDEPTH];
    int unsigned ar_len_mem [SVA_QDEPTH];
    int unsigned aw_wr, aw_rd, ar_wr, ar_rd;
    int unsigned w_beats, r_beats;

    // Scalar views of the tracker used by the assertions
    wire         aw_pending = (aw_wr != aw_rd);
    wire         ar_pending = (ar_wr != ar_rd);
    wire [31:0]  aw_head    = aw_len_mem[aw_rd];
    wire [31:0]  ar_head    = ar_len_mem[ar_rd];

    always @(posedge clk) begin
        if (rst) begin
            aw_wr <= 0; aw_rd <= 0;
            ar_wr <= 0; ar_rd <= 0;
            w_beats <= 0; r_beats <= 0;
        end
        else begin
            if (awvalid && awready) begin
                aw_len_mem[aw_wr] <= awlen;
                aw_wr <= (aw_wr + 1) % SVA_QDEPTH;
            end
            if (arvalid && arready) begin
                ar_len_mem[ar_wr] <= arlen;
                ar_wr <= (ar_wr + 1) % SVA_QDEPTH;
            end

            if (wvalid && wready) begin
                if (wlast) begin
                    w_beats <= 0;
                    if (aw_wr != aw_rd) aw_rd <= (aw_rd + 1) % SVA_QDEPTH;
                end
                else w_beats <= w_beats + 1;
            end

            if (rvalid && rready) begin
                if (rlast) begin
                    r_beats <= 0;
                    if (ar_wr != ar_rd) ar_rd <= (ar_rd + 1) % SVA_QDEPTH;
                end
                else r_beats <= r_beats + 1;
            end
        end
    end

    // Concurrent assertions sample in the preponed region, so they see the
    // counter/tracker values from before this cycle's updates.
    a_wlast_position: assert property (@(posedge clk) disable iff (rst)
        (wvalid && wready && wlast && aw_pending) |-> (w_beats == aw_head))
        else $error("AXI-SVA: WLAST on beat %0d but AWLEN implies beat %0d",
                    w_beats, aw_head);

    a_rlast_position: assert property (@(posedge clk) disable iff (rst)
        (rvalid && rready && rlast && ar_pending) |-> (r_beats == ar_head))
        else $error("AXI-SVA: RLAST on beat %0d but ARLEN implies beat %0d",
                    r_beats, ar_head);

    // A burst must not deliver more beats than its length allows
    a_w_no_overrun: assert property (@(posedge clk) disable iff (rst)
        (wvalid && wready && !wlast && aw_pending) |-> (w_beats < aw_head))
        else $error("AXI-SVA: more W beats than AWLEN allows");
    a_r_no_overrun: assert property (@(posedge clk) disable iff (rst)
        (rvalid && rready && !rlast && ar_pending) |-> (r_beats < ar_head))
        else $error("AXI-SVA: more R beats than ARLEN allows");

`endif // AXI4_NO_SVA

endmodule

//-------------------------------------------------------------
// Inject the checker into the testbench top.
//-------------------------------------------------------------
bind tb_top axi4_sva u_axi4_sva (
    .clk     (clk),
    .rst     (rst),
    .awid    (axi.awid),
    .awaddr  (axi.awaddr),
    .awlen   (axi.awlen),
    .awsize  (axi.awsize),
    .awburst (axi.awburst),
    .awvalid (axi.awvalid),
    .awready (axi.awready),
    .wdata   (axi.wdata),
    .wstrb   (axi.wstrb),
    .wlast   (axi.wlast),
    .wvalid  (axi.wvalid),
    .wready  (axi.wready),
    .bresp   (axi.bresp),
    .bvalid  (axi.bvalid),
    .bready  (axi.bready),
    .arid    (axi.arid),
    .araddr  (axi.araddr),
    .arlen   (axi.arlen),
    .arsize  (axi.arsize),
    .arburst (axi.arburst),
    .arvalid (axi.arvalid),
    .arready (axi.arready),
    .rresp   (axi.rresp),
    .rlast   (axi.rlast),
    .rvalid  (axi.rvalid),
    .rready  (axi.rready)
);

`endif

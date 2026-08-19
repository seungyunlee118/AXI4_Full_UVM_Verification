/*

Upgraded version of axi_ram.v with:
  1. Proper WRAP burst address calculation (wrap-around within window)
  2. Multiple outstanding write transactions (parameterizable depth)
  3. Multiple outstanding read transactions (parameterizable depth)
  4. Decoupled AW acceptance from W processing (queue-based)
  5. Decoupled B response from write completion (B queue)

Based on axi_ram.v by Alex Forencich (MIT License).
Enhancements added for verification learning purposes.

Note: Response codes still hardcoded to OKAY (SLVERR/DECERR not modeled).
      Exclusive access (LOCK) still ignored.
      Responses are returned in-order (no ID-based reordering).

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

module axi_ram_v2 #
(
    // Width of data bus in bits
    parameter DATA_WIDTH = 32,
    // Width of address bus in bits
    parameter ADDR_WIDTH = 16,
    // Width of wstrb (width of data bus in bytes)
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    // Width of ID signal
    parameter ID_WIDTH = 8,
    // Number of outstanding transactions supported (per direction)
    parameter OUTSTANDING_DEPTH = 4,
    // Extra pipeline register on output
    parameter PIPELINE_OUTPUT = 0
)
(
    input  wire                   clk,
    input  wire                   rst,

    // Write Address channel
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awlock,
    input  wire [3:0]             s_axi_awcache,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,
    // Write Data channel
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,
    // Write Response channel
    output wire [ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,
    // Read Address channel
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arlock,
    input  wire [3:0]             s_axi_arcache,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,
    // Read Data channel
    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready
);

// =====================================================================
// Local params
// =====================================================================
localparam VALID_ADDR_WIDTH = ADDR_WIDTH - $clog2(STRB_WIDTH);
localparam WORD_WIDTH       = STRB_WIDTH;
localparam WORD_SIZE        = DATA_WIDTH/WORD_WIDTH;
localparam PTR_W            = (OUTSTANDING_DEPTH > 1) ? $clog2(OUTSTANDING_DEPTH) : 1;
localparam CNT_W            = $clog2(OUTSTANDING_DEPTH+1);

localparam [1:0] BURST_FIXED = 2'b00;
localparam [1:0] BURST_INCR  = 2'b01;
localparam [1:0] BURST_WRAP  = 2'b10;

localparam [1:0] RESP_OKAY   = 2'b00;

// =====================================================================
// Sanity checks
// =====================================================================
initial begin
    if (WORD_SIZE * STRB_WIDTH != DATA_WIDTH) begin
        $error("Error: AXI data width not evenly divisible (instance %m)");
        $finish;
    end
    if (2**$clog2(WORD_WIDTH) != WORD_WIDTH) begin
        $error("Error: AXI word width must be power of two (instance %m)");
        $finish;
    end
    if (OUTSTANDING_DEPTH < 1) begin
        $error("Error: OUTSTANDING_DEPTH must be >= 1 (instance %m)");
        $finish;
    end
end

// =====================================================================
// Address helper functions
// =====================================================================
// Compute wrap window mask.
// Wrap window size = (len + 1) * (1 << size) bytes.
// mask = window_size - 1 (covers low bits within window).
function [ADDR_WIDTH-1:0] calc_wrap_mask;
    input [7:0] len;
    input [2:0] size;
    reg [15:0] total_bytes;
    begin
        total_bytes = ({8'd0, len} + 16'd1) << size;
        calc_wrap_mask = { { (ADDR_WIDTH-16){1'b0} }, total_bytes } - 1;
    end
endfunction

// Compute next address for a burst.
// FIXED: address unchanged
// INCR:  address + (1 << size)
// WRAP:  wraps within [wrap_base, wrap_base + window_size)
function [ADDR_WIDTH-1:0] next_addr_calc;
    input [ADDR_WIDTH-1:0] cur;
    input [1:0]            burst;
    input [2:0]            size;
    input [ADDR_WIDTH-1:0] wrap_base;
    input [ADDR_WIDTH-1:0] wrap_mask;
    reg   [ADDR_WIDTH-1:0] inc;
    begin
        inc = cur + (1 << size);
        case (burst)
            BURST_FIXED: next_addr_calc = cur;
            BURST_INCR:  next_addr_calc = inc;
            BURST_WRAP:  next_addr_calc = (inc & wrap_mask) | wrap_base;
            default:     next_addr_calc = inc;
        endcase
    end
endfunction

// =====================================================================
// Memory
// =====================================================================
// (* RAM_STYLE="BLOCK" *)
reg [DATA_WIDTH-1:0] mem [0:(2**VALID_ADDR_WIDTH)-1];

integer i_init, j_init;
initial begin
    for (i_init = 0; i_init < 2**VALID_ADDR_WIDTH; i_init = i_init + 2**(VALID_ADDR_WIDTH/2)) begin
        for (j_init = i_init; j_init < i_init + 2**(VALID_ADDR_WIDTH/2); j_init = j_init + 1) begin
            mem[j_init] = 0;
        end
    end
end

// =====================================================================
// AW COMMAND QUEUE (buffers incoming write commands)
// =====================================================================
// Entry: {awid, awaddr, awlen, awsize, awburst, wrap_base, wrap_mask}
localparam AW_ENTRY_W = ID_WIDTH + ADDR_WIDTH + 8 + 3 + 2 + ADDR_WIDTH + ADDR_WIDTH;

reg [AW_ENTRY_W-1:0] aw_q [0:OUTSTANDING_DEPTH-1];
reg [PTR_W-1:0]      aw_wr_ptr = 0;
reg [PTR_W-1:0]      aw_rd_ptr = 0;
reg [CNT_W-1:0]      aw_count  = 0;

wire aw_full  = (aw_count == OUTSTANDING_DEPTH);
wire aw_empty = (aw_count == 0);

wire aw_push = s_axi_awvalid & s_axi_awready;
reg  aw_pop;

assign s_axi_awready = !aw_full;

// Head-of-queue fields
wire [ID_WIDTH-1:0]   aw_head_id;
wire [ADDR_WIDTH-1:0] aw_head_addr;
wire [7:0]            aw_head_len;
wire [2:0]            aw_head_size;
wire [1:0]            aw_head_burst;
wire [ADDR_WIDTH-1:0] aw_head_wrap_base;
wire [ADDR_WIDTH-1:0] aw_head_wrap_mask;
assign {aw_head_id, aw_head_addr, aw_head_len, aw_head_size, aw_head_burst,
        aw_head_wrap_base, aw_head_wrap_mask} = aw_q[aw_rd_ptr];

// Pre-compute wrap params for incoming AW
wire [ADDR_WIDTH-1:0] in_aw_wrap_mask = calc_wrap_mask(s_axi_awlen, s_axi_awsize);
wire [ADDR_WIDTH-1:0] in_aw_wrap_base = s_axi_awaddr & ~in_aw_wrap_mask;

always @(posedge clk) begin
    if (rst) begin
        aw_wr_ptr <= 0;
        aw_rd_ptr <= 0;
        aw_count  <= 0;
    end else begin
        if (aw_push) begin
            aw_q[aw_wr_ptr] <= {s_axi_awid, s_axi_awaddr, s_axi_awlen, s_axi_awsize,
                                s_axi_awburst, in_aw_wrap_base, in_aw_wrap_mask};
            aw_wr_ptr <= (aw_wr_ptr == OUTSTANDING_DEPTH-1) ? {PTR_W{1'b0}} : aw_wr_ptr + 1'b1;
        end
        if (aw_pop) begin
            aw_rd_ptr <= (aw_rd_ptr == OUTSTANDING_DEPTH-1) ? {PTR_W{1'b0}} : aw_rd_ptr + 1'b1;
        end
        case ({aw_push, aw_pop})
            2'b10:   aw_count <= aw_count + 1'b1;
            2'b01:   aw_count <= aw_count - 1'b1;
            default: aw_count <= aw_count;
        endcase
    end
end

// =====================================================================
// B RESPONSE QUEUE (buffers write responses)
// =====================================================================
// Entry: {id, resp}
localparam B_ENTRY_W = ID_WIDTH + 2;

reg [B_ENTRY_W-1:0] b_q [0:OUTSTANDING_DEPTH-1];
reg [PTR_W-1:0]     b_wr_ptr = 0;
reg [PTR_W-1:0]     b_rd_ptr = 0;
reg [CNT_W-1:0]     b_count  = 0;

wire b_full  = (b_count == OUTSTANDING_DEPTH);
wire b_empty = (b_count == 0);

reg               b_push;
reg [ID_WIDTH-1:0] b_push_id;
wire b_pop = s_axi_bvalid & s_axi_bready;

assign s_axi_bid    = b_q[b_rd_ptr][B_ENTRY_W-1:2];
assign s_axi_bresp  = b_q[b_rd_ptr][1:0];
assign s_axi_bvalid = !b_empty;

always @(posedge clk) begin
    if (rst) begin
        b_wr_ptr <= 0;
        b_rd_ptr <= 0;
        b_count  <= 0;
    end else begin
        if (b_push) begin
            b_q[b_wr_ptr] <= {b_push_id, RESP_OKAY};
            b_wr_ptr <= (b_wr_ptr == OUTSTANDING_DEPTH-1) ? {PTR_W{1'b0}} : b_wr_ptr + 1'b1;
        end
        if (b_pop) begin
            b_rd_ptr <= (b_rd_ptr == OUTSTANDING_DEPTH-1) ? {PTR_W{1'b0}} : b_rd_ptr + 1'b1;
        end
        case ({b_push, b_pop})
            2'b10:   b_count <= b_count + 1'b1;
            2'b01:   b_count <= b_count - 1'b1;
            default: b_count <= b_count;
        endcase
    end
end

// =====================================================================
// WRITE ENGINE
// =====================================================================
// Simple 2-state FSM:
//   W_IDLE:  wait for AW at queue head and B slot available; load and go to BURST
//   W_BURST: WREADY high; consume W beats, write memory; on last beat push B, back to IDLE

localparam W_IDLE  = 1'b0;
localparam W_BURST = 1'b1;

reg               w_state = W_IDLE;
reg [ADDR_WIDTH-1:0] w_cur_addr = 0;
reg [7:0]            w_remain   = 0;
reg [ID_WIDTH-1:0]   w_cur_id   = 0;
reg [2:0]            w_cur_size  = 0;
reg [1:0]            w_cur_burst = 0;
reg [ADDR_WIDTH-1:0] w_cur_wbase = 0;
reg [ADDR_WIDTH-1:0] w_cur_wmask = 0;

wire [VALID_ADDR_WIDTH-1:0] w_word_addr = w_cur_addr >> (ADDR_WIDTH - VALID_ADDR_WIDTH);

wire w_beat        = s_axi_wvalid & s_axi_wready;
wire w_last_beat   = w_beat & (w_remain == 0);
wire w_can_start   = !aw_empty & !b_full;

assign s_axi_wready = (w_state == W_BURST);

// Combinational: aw_pop and b_push signals
always @* begin
    aw_pop    = 1'b0;
    b_push    = 1'b0;
    b_push_id = w_cur_id;

    case (w_state)
        W_IDLE: begin
            if (w_can_start) begin
                aw_pop = 1'b1;
            end
        end
        W_BURST: begin
            if (w_last_beat) begin
                b_push = 1'b1;
            end
        end
    endcase
end

// Sequential: engine state + registers
always @(posedge clk) begin
    if (rst) begin
        w_state <= W_IDLE;
    end else begin
        case (w_state)
            W_IDLE: begin
                if (w_can_start) begin
                    w_cur_id    <= aw_head_id;
                    w_cur_addr  <= aw_head_addr;
                    w_remain    <= aw_head_len;
                    w_cur_size  <= aw_head_size;
                    w_cur_burst <= aw_head_burst;
                    w_cur_wbase <= aw_head_wrap_base;
                    w_cur_wmask <= aw_head_wrap_mask;
                    w_state     <= W_BURST;
                end
            end
            W_BURST: begin
                if (w_beat) begin
                    if (w_remain == 0) begin
                        w_state <= W_IDLE;
                    end else begin
                        w_remain   <= w_remain - 1'b1;
                        w_cur_addr <= next_addr_calc(w_cur_addr, w_cur_burst, w_cur_size,
                                                      w_cur_wbase, w_cur_wmask);
                    end
                end
            end
        endcase
    end
end

// Memory write with WSTRB byte-lane masking
integer wi;
always @(posedge clk) begin
    if (w_beat) begin
        for (wi = 0; wi < WORD_WIDTH; wi = wi + 1) begin
            if (s_axi_wstrb[wi]) begin
                mem[w_word_addr][WORD_SIZE*wi +: WORD_SIZE] <= s_axi_wdata[WORD_SIZE*wi +: WORD_SIZE];
            end
        end
    end
end

// =====================================================================
// AR COMMAND QUEUE (buffers incoming read commands)
// =====================================================================
localparam AR_ENTRY_W = ID_WIDTH + ADDR_WIDTH + 8 + 3 + 2 + ADDR_WIDTH + ADDR_WIDTH;

reg [AR_ENTRY_W-1:0] ar_q [0:OUTSTANDING_DEPTH-1];
reg [PTR_W-1:0]      ar_wr_ptr = 0;
reg [PTR_W-1:0]      ar_rd_ptr = 0;
reg [CNT_W-1:0]      ar_count  = 0;

wire ar_full  = (ar_count == OUTSTANDING_DEPTH);
wire ar_empty = (ar_count == 0);

wire ar_push = s_axi_arvalid & s_axi_arready;
reg  ar_pop;

assign s_axi_arready = !ar_full;

wire [ID_WIDTH-1:0]   ar_head_id;
wire [ADDR_WIDTH-1:0] ar_head_addr;
wire [7:0]            ar_head_len;
wire [2:0]            ar_head_size;
wire [1:0]            ar_head_burst;
wire [ADDR_WIDTH-1:0] ar_head_wrap_base;
wire [ADDR_WIDTH-1:0] ar_head_wrap_mask;
assign {ar_head_id, ar_head_addr, ar_head_len, ar_head_size, ar_head_burst,
        ar_head_wrap_base, ar_head_wrap_mask} = ar_q[ar_rd_ptr];

wire [ADDR_WIDTH-1:0] in_ar_wrap_mask = calc_wrap_mask(s_axi_arlen, s_axi_arsize);
wire [ADDR_WIDTH-1:0] in_ar_wrap_base = s_axi_araddr & ~in_ar_wrap_mask;

always @(posedge clk) begin
    if (rst) begin
        ar_wr_ptr <= 0;
        ar_rd_ptr <= 0;
        ar_count  <= 0;
    end else begin
        if (ar_push) begin
            ar_q[ar_wr_ptr] <= {s_axi_arid, s_axi_araddr, s_axi_arlen, s_axi_arsize,
                                s_axi_arburst, in_ar_wrap_base, in_ar_wrap_mask};
            ar_wr_ptr <= (ar_wr_ptr == OUTSTANDING_DEPTH-1) ? {PTR_W{1'b0}} : ar_wr_ptr + 1'b1;
        end
        if (ar_pop) begin
            ar_rd_ptr <= (ar_rd_ptr == OUTSTANDING_DEPTH-1) ? {PTR_W{1'b0}} : ar_rd_ptr + 1'b1;
        end
        case ({ar_push, ar_pop})
            2'b10:   ar_count <= ar_count + 1'b1;
            2'b01:   ar_count <= ar_count - 1'b1;
            default: ar_count <= ar_count;
        endcase
    end
end

// =====================================================================
// READ ENGINE
// =====================================================================
// 2-state FSM:
//   R_IDLE:  wait for AR at queue head; load and go to BURST
//   R_BURST: generate one R beat per cycle when accepted;
//            on last beat, back to IDLE

localparam R_IDLE  = 1'b0;
localparam R_BURST = 1'b1;

reg                  r_state = R_IDLE;
reg [ADDR_WIDTH-1:0] r_cur_addr  = 0;
reg [7:0]            r_remain    = 0;
reg [ID_WIDTH-1:0]   r_cur_id    = 0;
reg [2:0]            r_cur_size  = 0;
reg [1:0]            r_cur_burst = 0;
reg [ADDR_WIDTH-1:0] r_cur_wbase = 0;
reg [ADDR_WIDTH-1:0] r_cur_wmask = 0;

wire [VALID_ADDR_WIDTH-1:0] r_word_addr = r_cur_addr >> (ADDR_WIDTH - VALID_ADDR_WIDTH);

// Non-pipelined output registers
reg [ID_WIDTH-1:0]   s_axi_rid_reg    = 0;
reg [DATA_WIDTH-1:0] s_axi_rdata_reg  = 0;
reg                  s_axi_rlast_reg  = 0;
reg                  s_axi_rvalid_reg = 0;

// Pipelined output registers (used when PIPELINE_OUTPUT=1)
reg [ID_WIDTH-1:0]   s_axi_rid_pipe    = 0;
reg [DATA_WIDTH-1:0] s_axi_rdata_pipe  = 0;
reg                  s_axi_rlast_pipe  = 0;
reg                  s_axi_rvalid_pipe = 0;

assign s_axi_rid    = PIPELINE_OUTPUT ? s_axi_rid_pipe    : s_axi_rid_reg;
assign s_axi_rdata  = PIPELINE_OUTPUT ? s_axi_rdata_pipe  : s_axi_rdata_reg;
assign s_axi_rlast  = PIPELINE_OUTPUT ? s_axi_rlast_pipe  : s_axi_rlast_reg;
assign s_axi_rvalid = PIPELINE_OUTPUT ? s_axi_rvalid_pipe : s_axi_rvalid_reg;
assign s_axi_rresp  = RESP_OKAY;

// "Can advance" condition: downstream can accept a new beat
wire r_advance = s_axi_rready | (PIPELINE_OUTPUT & !s_axi_rvalid_pipe) | !s_axi_rvalid_reg;

reg mem_rd_en;
reg r_active_beat;   // will produce a beat this cycle

always @* begin
    ar_pop        = 1'b0;
    mem_rd_en     = 1'b0;
    r_active_beat = 1'b0;

    case (r_state)
        R_IDLE: begin
            if (!ar_empty) begin
                ar_pop = 1'b1;
            end
        end
        R_BURST: begin
            if (r_advance) begin
                mem_rd_en     = 1'b1;
                r_active_beat = 1'b1;
            end
        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        r_state          <= R_IDLE;
        s_axi_rvalid_reg <= 1'b0;
        s_axi_rlast_reg  <= 1'b0;
    end else begin
        // Default: clear rvalid if consumed
        if (r_advance) begin
            s_axi_rvalid_reg <= 1'b0;
            s_axi_rlast_reg  <= 1'b0;
        end

        case (r_state)
            R_IDLE: begin
                if (!ar_empty) begin
                    r_cur_id    <= ar_head_id;
                    r_cur_addr  <= ar_head_addr;
                    r_remain    <= ar_head_len;
                    r_cur_size  <= ar_head_size;
                    r_cur_burst <= ar_head_burst;
                    r_cur_wbase <= ar_head_wrap_base;
                    r_cur_wmask <= ar_head_wrap_mask;
                    r_state     <= R_BURST;
                end
            end
            R_BURST: begin
                if (r_active_beat) begin
                    s_axi_rvalid_reg <= 1'b1;
                    s_axi_rid_reg    <= r_cur_id;
                    s_axi_rlast_reg  <= (r_remain == 0);

                    if (r_remain == 0) begin
                        r_state <= R_IDLE;
                    end else begin
                        r_remain   <= r_remain - 1'b1;
                        r_cur_addr <= next_addr_calc(r_cur_addr, r_cur_burst, r_cur_size,
                                                      r_cur_wbase, r_cur_wmask);
                    end
                end
            end
        endcase

        // Memory read (registered)
        if (mem_rd_en) begin
            s_axi_rdata_reg <= mem[r_word_addr];
        end

        // Pipeline stage (optional)
        if (!s_axi_rvalid_pipe || s_axi_rready) begin
            s_axi_rid_pipe    <= s_axi_rid_reg;
            s_axi_rdata_pipe  <= s_axi_rdata_reg;
            s_axi_rlast_pipe  <= s_axi_rlast_reg;
            s_axi_rvalid_pipe <= s_axi_rvalid_reg;
        end
    end

    if (rst) begin
        s_axi_rvalid_pipe <= 1'b0;
    end
end

endmodule

`resetall
//=============================================================
// Week 2 - AXI4 package: enums + transaction class
// (Plain SystemVerilog for now; will convert axi4_txn into a
//  uvm_sequence_item in Week 3.)
//=============================================================
`ifndef AXI4_PKG_SV
`define AXI4_PKG_SV
`timescale 1ns/1ps

package axi4_pkg;

    //--------------------------------------------------------
    // AXI4 protocol enums
    //--------------------------------------------------------
    typedef enum bit [1:0] {
        AXI_FIXED = 2'b00,
        AXI_INCR  = 2'b01,
        AXI_WRAP  = 2'b10
        // 2'b11 reserved
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

    //--------------------------------------------------------
    // Transaction: one AXI burst (write or read)
    //--------------------------------------------------------
    class axi4_txn #(
        parameter int DATA_WIDTH = 32,
        parameter int ADDR_WIDTH = 16,
        parameter int ID_WIDTH   = 8,
        parameter int STRB_WIDTH = DATA_WIDTH/8
    );

        // Direction of the burst
        rand axi_dir_e            dir;

        // Address-channel fields (shared shape for AW / AR)
        rand bit [ID_WIDTH-1:0]   id;
        rand bit [ADDR_WIDTH-1:0] addr;
        rand bit [7:0]            len;    // beats = len + 1
        rand bit [2:0]            size;   // bytes/beat = 2**size
        rand axi_burst_e          burst;

        // Data-channel payload, one element per beat
        rand bit [DATA_WIDTH-1:0] data [];
        rand bit [STRB_WIDTH-1:0] strb [];

        // Response captured from the DUT (not randomized)
        axi_resp_e                resp = AXI_OKAY;

        // Unique handle for logging
        static int                s_count = 0;
        int                       tag;

        //----------------------------------------------------
        // Constraints
        //----------------------------------------------------
        // Bounded burst length for early testing (1..16 beats)
        constraint c_len { len inside {[0:15]}; }

        // Transfer size cannot exceed the data-bus width
        constraint c_size { size <= $clog2(STRB_WIDTH); }

        // Prefer INCR, but allow FIXED / WRAP so we can hit the
        // DUT's known WRAP weakness on purpose later.
        constraint c_burst_dist {
            burst dist { AXI_INCR := 8, AXI_FIXED := 1, AXI_WRAP := 1 };
        }

        // WRAP bursts must have 2, 4, 8 or 16 beats
        constraint c_wrap_len {
            (burst == AXI_WRAP) -> len inside {1, 3, 7, 15};
        }

        // Start address aligned to the transfer size
        constraint c_align { addr % (1 << size) == 0; }

        // A burst must not cross a 4 KB boundary
        constraint c_4k {
            (addr % 4096) + ((len + 1) << size) <= 4096;
        }

        // Payload arrays sized to the beat count
        constraint c_payload_size {
            data.size() == len + 1;
            strb.size() == len + 1;
        }

        //----------------------------------------------------
        // Convenience
        //----------------------------------------------------
        function new();
            tag = s_count++;
        endfunction

        // beats in this burst
        function int unsigned beats();
            return len + 1;
        endfunction

        // bytes per beat
        function int unsigned bytes_per_beat();
            return (1 << size);
        endfunction

        // For read transactions strobes are meaningless -> force all-ones
        function void post_randomize();
            if (dir == AXI_READ) begin
                foreach (strb[i]) strb[i] = '1;
            end
        endfunction

        function string convert2string();
            string s;
            s = $sformatf(
                "axi4_txn#%0d %s id=%0d addr=0x%0h len=%0d(%0d beats) size=%0d(%0d B) burst=%s resp=%s",
                tag, dir.name(), id, addr, len, beats(), size,
                bytes_per_beat(), burst.name(), resp.name());
            if (data.size() > 0)
                s = {s, $sformatf(" data[0]=0x%0h", data[0])};
            return s;
        endfunction

        function void display(string prefix = "");
            $display("%s%s", prefix, convert2string());
        endfunction

        // Deep copy
        function axi4_txn #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) clone();
            clone = new();
            clone.dir   = dir;
            clone.id    = id;
            clone.addr  = addr;
            clone.len   = len;
            clone.size  = size;
            clone.burst = burst;
            clone.resp  = resp;
            clone.data  = new[data.size()](data);
            clone.strb  = new[strb.size()](strb);
            return clone;
        endfunction

        // Compare address/control + payload (ignores tag)
        function bit compare(axi4_txn #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, STRB_WIDTH) rhs);
            if (rhs == null)                 return 0;
            if (dir   !== rhs.dir)           return 0;
            if (id    !== rhs.id)            return 0;
            if (addr  !== rhs.addr)          return 0;
            if (len   !== rhs.len)           return 0;
            if (size  !== rhs.size)          return 0;
            if (burst !== rhs.burst)         return 0;
            if (data.size() != rhs.data.size()) return 0;
            foreach (data[i]) if (data[i] !== rhs.data[i]) return 0;
            return 1;
        endfunction

    endclass

    // Default 32-bit / 16-bit-addr configuration used by tb_top
    typedef axi4_txn #(.DATA_WIDTH(32), .ADDR_WIDTH(16),
                       .ID_WIDTH(8),   .STRB_WIDTH(4)) axi4_txn_t;

endpackage

`endif

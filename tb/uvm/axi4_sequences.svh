//=============================================================
//   axi4_base_seq     : common base + wr_then_rd() helper
//   axi4_write_seq    : N random writes
//   axi4_read_seq     : N random reads
//   axi4_rand_seq     : N random bursts, mixed read/write
//   axi4_wr_rd_seq    : write a region then read it back (self-checking)
//   axi4_directed_seq : hand-picked corner cases
//   axi4_wrap_seq     : WRAP bursts — EXPECTED TO FAIL, documents a DUT bug
//=============================================================
`ifndef AXI4_SEQUENCES_SVH
`define AXI4_SEQUENCES_SVH

//---------------------------------------------------------------
class axi4_base_seq extends uvm_sequence #(axi4_seq_item);
    `uvm_object_utils(axi4_base_seq)
    rand int unsigned num = 5;   // how many transactions / pairs

    function new(string name = "axi4_base_seq");
        super.new(name);
    endfunction

    // Write a burst, then read exactly the same region back.
    // With a correct DUT the scoreboard should see identical data.
    task wr_then_rd(bit [AXI_ADDR_WIDTH-1:0] a,
                    bit [7:0]                l,
                    bit [2:0]                s,
                    axi_burst_e              b);
        axi4_seq_item wr, rd;

        wr = axi4_seq_item::type_id::create("wr");
        start_item(wr);
        if (!wr.randomize() with { dir == AXI_WRITE; addr == a;
                                   len == l; size == s; burst == b; })
            `uvm_error("RAND", "directed write randomize() failed")
        finish_item(wr);

        rd = axi4_seq_item::type_id::create("rd");
        start_item(rd);
        if (!rd.randomize() with { dir == AXI_READ; addr == a;
                                   len == l; size == s; burst == b;
                                   id == wr.id; })
            `uvm_error("RAND", "directed read randomize() failed")
        finish_item(rd);
    endtask
endclass

//---------------------------------------------------------------
class axi4_write_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_write_seq)
    function new(string name = "axi4_write_seq"); super.new(name); endfunction
    task body();
        repeat (num) begin
            req = axi4_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize() with { dir == AXI_WRITE;
                                        burst inside {AXI_INCR, AXI_FIXED}; })
                `uvm_error("RAND", "write item randomize() failed")
            finish_item(req);
        end
    endtask
endclass

//---------------------------------------------------------------
class axi4_read_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_read_seq)
    function new(string name = "axi4_read_seq"); super.new(name); endfunction
    task body();
        repeat (num) begin
            req = axi4_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize() with { dir == AXI_READ;
                                        burst inside {AXI_INCR, AXI_FIXED}; })
                `uvm_error("RAND", "read item randomize() failed")
            finish_item(req);
        end
    endtask
endclass

//---------------------------------------------------------------
class axi4_rand_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_rand_seq)
    function new(string name = "axi4_rand_seq"); super.new(name); endfunction
    task body();
        repeat (num) begin
            req = axi4_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize() with { burst inside {AXI_INCR, AXI_FIXED}; })
                `uvm_error("RAND", "rand item randomize() failed")
            finish_item(req);
        end
    endtask
endclass

//---------------------------------------------------------------
// Random write followed by a read-back of the same region.
class axi4_wr_rd_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_wr_rd_seq)
    function new(string name = "axi4_wr_rd_seq"); super.new(name); endfunction
    task body();
        repeat (num) begin
            axi4_seq_item wr, rd;

            wr = axi4_seq_item::type_id::create("wr");
            start_item(wr);
            if (!wr.randomize() with { dir == AXI_WRITE; burst == AXI_INCR; })
                `uvm_error("RAND", "write randomize() failed")
            finish_item(wr);

            rd = axi4_seq_item::type_id::create("rd");
            start_item(rd);
            if (!rd.randomize() with { dir == AXI_READ; burst == AXI_INCR;
                                       addr == wr.addr; len == wr.len;
                                       size == wr.size; id == wr.id; })
                `uvm_error("RAND", "read randomize() failed")
            finish_item(rd);
        end
    endtask
endclass

//---------------------------------------------------------------
// Outstanding-transaction stimulus.
//---------------------------------------------------------------
class axi4_os_base_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_os_base_seq)
    function new(string name = "axi4_os_base_seq"); super.new(name); endfunction

    localparam int OS_COUNT = 8;
    // 0x5000, 0x5100, ... 0x5700 — 4 beats x 4 B each, all 4 KB-safe
    function bit [AXI_ADDR_WIDTH-1:0] os_addr(int i);
        return 16'h5000 + (i * 16'h0100);
    endfunction
endclass

class axi4_os_write_seq extends axi4_os_base_seq;
    `uvm_object_utils(axi4_os_write_seq)
    function new(string name = "axi4_os_write_seq"); super.new(name); endfunction
    task body();
        for (int i = 0; i < OS_COUNT; i++) begin
            req = axi4_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize() with { dir   == AXI_WRITE;
                                        burst == AXI_INCR;
                                        addr  == os_addr(i);
                                        len   == 3;
                                        size  == 3'd2;
                                        foreach (strb[j])
                                            strb[j] == {AXI_STRB_WIDTH{1'b1}}; })
                `uvm_error("RAND", "outstanding write randomize() failed")
            finish_item(req);
        end
    endtask
endclass

class axi4_os_read_seq extends axi4_os_base_seq;
    `uvm_object_utils(axi4_os_read_seq)
    function new(string name = "axi4_os_read_seq"); super.new(name); endfunction
    task body();
        for (int i = 0; i < OS_COUNT; i++) begin
            req = axi4_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize() with { dir   == AXI_READ;
                                        burst == AXI_INCR;
                                        addr  == os_addr(i);
                                        len   == 3;
                                        size  == 3'd2; })
                `uvm_error("RAND", "outstanding read randomize() failed")
            finish_item(req);
        end
    endtask
endclass

//---------------------------------------------------------------
// Coverage-closure stimulus
//---------------------------------------------------------------
class axi4_cov_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_cov_seq)
    function new(string name = "axi4_cov_seq"); super.new(name); endfunction

    task body();
        // Deterministic sweep: every burst type x every size
        foreach_burst_size();
        // Deterministic sweep: every burst type x every length class
        burst_len_sweep();
        // Then a broad random mix to fill length / region / strobe bins
        repeat (num) begin
            req = axi4_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize())
                `uvm_error("RAND", "coverage item randomize() failed")
            finish_item(req);
        end
    endtask



    task burst_len_sweep();
        bit [AXI_ADDR_WIDTH-1:0] a = 16'h3000;
        // one length from each class: single / 2-4 / 5-8 / 9-16 beats
        bit [7:0] lens[4] = '{8'd0, 8'd2, 8'd6, 8'd12};

        foreach (lens[i]) begin
            wr_then_rd(a, lens[i], 3'd2, AXI_FIXED); a += 16'h0100;
            wr_then_rd(a, lens[i], 3'd2, AXI_INCR);  a += 16'h0100;
        end
        // WRAP is only legal with 2/4/8/16 beats (len 1/3/7/15)
        wr_then_rd(a, 8'd1,  3'd2, AXI_WRAP); a += 16'h0100;
        wr_then_rd(a, 8'd3,  3'd2, AXI_WRAP); a += 16'h0100;
        wr_then_rd(a, 8'd7,  3'd2, AXI_WRAP); a += 16'h0100;
        wr_then_rd(a, 8'd15, 3'd2, AXI_WRAP);
    endtask

    // Hit every legal (burst, size) combination for both directions.
    task foreach_burst_size();
        axi_burst_e blist[3] = '{AXI_FIXED, AXI_INCR, AXI_WRAP};
        bit [AXI_ADDR_WIDTH-1:0] a = 16'h2000;
        foreach (blist[b]) begin
            for (int s = 0; s <= 2; s++) begin
                // WRAP is only legal with 2/4/8/16 beats -> use 4
                automatic bit [7:0] l = (blist[b] == AXI_WRAP) ? 8'd3 : 8'd2;
                wr_then_rd(a, l, s[2:0], blist[b]);
                a += 16'h0100;
            end
        end
    endtask
endclass

//---------------------------------------------------------------
// Hand-picked corner cases, each written then read back.
class axi4_directed_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_directed_seq)
    function new(string name = "axi4_directed_seq"); super.new(name); endfunction
    task body();
        //          addr      len   size  burst        what it exercises
        wr_then_rd(16'h0000, 8'd0,  3'd2, AXI_INCR);  // single beat, full width
        wr_then_rd(16'h0100, 8'd15, 3'd2, AXI_INCR);  // max 16-beat burst
        wr_then_rd(16'h0FC0, 8'd15, 3'd2, AXI_INCR);  // ends exactly at 4KB edge
        wr_then_rd(16'h0200, 8'd7,  3'd0, AXI_INCR);  // narrow: 1 byte/beat
        wr_then_rd(16'h0300, 8'd3,  3'd1, AXI_INCR);  // narrow: 2 bytes/beat
        wr_then_rd(16'h0400, 8'd3,  3'd2, AXI_FIXED); // FIXED: same address
    endtask
endclass

//---------------------------------------------------------------
// WRAP bursts. The reference model wraps correctly, the DUT does not,
// so this sequence is EXPECTED to raise scoreboard mismatches.
class axi4_wrap_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_wrap_seq)
    function new(string name = "axi4_wrap_seq"); super.new(name); endfunction

    //-----------------------------------------------------------
    // Write with WRAP starting mid-window 
    //-----------------------------------------------------------
    task wrap_write_incr_read(bit [AXI_ADDR_WIDTH-1:0] a,
                              bit [7:0]                l,
                              bit [2:0]                s);
        axi4_seq_item wr, rd;
        int unsigned nbytes = 1 << s;
        int unsigned total  = (l + 1) * nbytes;          // wrap window size
        bit [AXI_ADDR_WIDTH-1:0] base = a - (a % total); // window base

        wr = axi4_seq_item::type_id::create("wr_wrap");
        start_item(wr);
        if (!wr.randomize() with { dir == AXI_WRITE; addr == a;
                                   len == l; size == s; burst == AXI_WRAP;
                                   foreach (strb[j])
                                       strb[j] == {AXI_STRB_WIDTH{1'b1}}; })
            `uvm_error("RAND", "wrap write randomize() failed")
        finish_item(wr);

        rd = axi4_seq_item::type_id::create("rd_incr");
        start_item(rd);
        if (!rd.randomize() with { dir == AXI_READ; addr == base;
                                   len == l; size == s; burst == AXI_INCR; })
            `uvm_error("RAND", "incr read-back randomize() failed")
        finish_item(rd);
    endtask

    task body();
        // len 1/3/7/15 -> 2/4/8/16 beats, the only legal WRAP lengths
        wrap_write_incr_read(16'h0A08, 8'd3, 3'd2);  // window 0x0A00..0x0A0F
        wrap_write_incr_read(16'h0B10, 8'd7, 3'd2);  // window 0x0B00..0x0B1F
    endtask
endclass

`endif

//=============================================================
//   axi4_base_seq     : common base + wr_then_rd() helper
//   axi4_write_seq    : N random writes
//   axi4_read_seq     : N random reads
//   axi4_rand_seq     : N random bursts, mixed read/write
//   axi4_wr_rd_seq    : write a region then read it back (self-checking)
//   axi4_directed_seq : hand-picked corner cases
//   axi4_wrap_seq     : WRAP bursts — EXPECTED TO FAIL on v1 (documents the WRAP bug)
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
// Stress stimulus: many short bursts, so the slave's queues fill up.
// Each burst gets its own 64-byte slot from 0x6000 (fits any 1-4 beat
// burst, never crosses 4 KB). INCR/FIXED only, so v1 passes as well.
//---------------------------------------------------------------
class axi4_stress_base_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_stress_base_seq)
    function new(string name = "axi4_stress_base_seq"); super.new(name); endfunction

    localparam int STRESS_COUNT = 32;
    function bit [AXI_ADDR_WIDTH-1:0] slot(int i);
        return 16'h6000 + i * 16'h0040;
    endfunction

    task one_burst(axi_dir_e d, int i);
        req = axi4_seq_item::type_id::create("req");
        start_item(req);
        if (!req.randomize() with { dir == d; addr == slot(i); len inside {[0:3]};
                                    burst inside {AXI_INCR, AXI_FIXED}; })
            `uvm_error("RAND", "stress item randomize() failed")
        finish_item(req);
    endtask
endclass

class axi4_stress_write_seq extends axi4_stress_base_seq;
    `uvm_object_utils(axi4_stress_write_seq)
    function new(string name = "axi4_stress_write_seq"); super.new(name); endfunction
    task body();
        for (int i = 0; i < STRESS_COUNT; i++) one_burst(AXI_WRITE, i);
    endtask
endclass

class axi4_stress_read_seq extends axi4_stress_base_seq;
    `uvm_object_utils(axi4_stress_read_seq)
    function new(string name = "axi4_stress_read_seq"); super.new(name); endfunction
    task body();
        for (int i = 0; i < STRESS_COUNT; i++) one_burst(AXI_READ, i);
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
        // Deterministic: every 4 KB region and every strobe shape. Left to
        // the random mix below, these closed on only 5 of 12 seeds.
        region_sweep();
        strb_sweep();
        // Then a broad random mix on top of the closed model
        repeat (num) begin
            req = axi4_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize())
                `uvm_error("RAND", "coverage item randomize() failed")
            finish_item(req);
        end
        // A WRAP that really wraps (the sweeps above all start on a window
        // base). Last on purpose: v1 writes past the window, and no later
        // random read may land on those bytes.
        wrap_mid_window();
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

    // One short burst in each of the 16 4 KB regions (cp_region).
    task region_sweep();
        for (int r = 0; r < 16; r++)
            wr_then_rd({r[3:0], 12'hE00}, 8'd1, 3'd2, AXI_INCR);
    endtask

    // Every strobe shape (cp_strb): all addressed lanes, one lane, none.
    task strb_sweep();
        bit [AXI_STRB_WIDTH-1:0] pat[3] = '{'1, AXI_STRB_WIDTH'(1), '0};
        bit [AXI_ADDR_WIDTH-1:0] a = 16'h4F00;
        foreach (pat[p]) begin
            wr_strb_then_rd(a, pat[p]);
            a += 16'h0010;
        end
    endtask

    task wr_strb_then_rd(bit [AXI_ADDR_WIDTH-1:0] a, bit [AXI_STRB_WIDTH-1:0] st);
        axi4_seq_item wr, rd;

        wr = axi4_seq_item::type_id::create("wr_strb");
        start_item(wr);
        if (!wr.randomize() with { dir == AXI_WRITE; addr == a; len == 8'd1;
                                   size == 3'd2; burst == AXI_INCR;
                                   foreach (strb[j]) strb[j] == st; })
            `uvm_error("RAND", "strobe write randomize() failed")
        finish_item(wr);

        rd = axi4_seq_item::type_id::create("rd_strb");
        start_item(rd);
        if (!rd.randomize() with { dir == AXI_READ; addr == a; len == 8'd1;
                                   size == 3'd2; burst == AXI_INCR; id == wr.id; })
            `uvm_error("RAND", "strobe read randomize() failed")
        finish_item(rd);
    endtask

    // Starts mid-window, so the wrap point is crossed. The read-back is WRAP
    // too, so a wrap bug shared by the write and read paths cannot show here
    // (axi4_wrap_test checks that, with an INCR read-back of the window), but
    // a read-path-only one does (mutation campaign, mutant A06).
    task wrap_mid_window();
        wr_then_rd(16'h3C08, 8'd3, 3'd2, AXI_WRAP);   // window 0x3C00..0x3C0F
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

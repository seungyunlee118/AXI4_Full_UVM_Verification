//=============================================================
// Sequences — the stimulus programs
//
//   axi4_base_seq  : common base (nothing to drive by itself)
//   axi4_write_seq : N random writes
//   axi4_read_seq  : N random reads
//   axi4_rand_seq  : N random bursts, mixed read/write
//   axi4_wr_rd_seq : write a region, then read the SAME region back
//                    (sets up self-checking for the Week 4 scoreboard)
//
// A sequence runs on a sequencer: start_item()/finish_item() blocks
// until the driver has consumed each item.
//=============================================================
`ifndef AXI4_SEQUENCES_SVH
`define AXI4_SEQUENCES_SVH

//---------------------------------------------------------------
class axi4_base_seq extends uvm_sequence #(axi4_seq_item);
    `uvm_object_utils(axi4_base_seq)
    rand int unsigned num = 5;   // how many transactions to generate
    function new(string name = "axi4_base_seq");
        super.new(name);
    endfunction
endclass

//---------------------------------------------------------------
class axi4_write_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_write_seq)
    function new(string name = "axi4_write_seq");
        super.new(name);
    endfunction
    task body();
        repeat (num) begin
            req = axi4_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize() with { dir == AXI_WRITE; })
                `uvm_error("RAND", "write item randomize() failed")
            finish_item(req);
        end
    endtask
endclass

//---------------------------------------------------------------
class axi4_read_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_read_seq)
    function new(string name = "axi4_read_seq");
        super.new(name);
    endfunction
    task body();
        repeat (num) begin
            req = axi4_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize() with { dir == AXI_READ; })
                `uvm_error("RAND", "read item randomize() failed")
            finish_item(req);
        end
    endtask
endclass

//---------------------------------------------------------------
class axi4_rand_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_rand_seq)
    function new(string name = "axi4_rand_seq");
        super.new(name);
    endfunction
    task body();
        repeat (num) begin
            req = axi4_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize())     // dir is free -> mixed read/write
                `uvm_error("RAND", "rand item randomize() failed")
            finish_item(req);
        end
    endtask
endclass

//---------------------------------------------------------------
// Write a region, then read exactly the same region back.
// With a correct DUT the read data should equal what we wrote —
// the Week 4 scoreboard will check that automatically.
//---------------------------------------------------------------
class axi4_wr_rd_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_wr_rd_seq)
    function new(string name = "axi4_wr_rd_seq");
        super.new(name);
    endfunction
    task body();
        repeat (num) begin
            axi4_seq_item wr, rd;

            // ---- WRITE (INCR keeps address bookkeeping simple) ----
            wr = axi4_seq_item::type_id::create("wr");
            start_item(wr);
            if (!wr.randomize() with { dir == AXI_WRITE; burst == AXI_INCR; })
                `uvm_error("RAND", "write randomize() failed")
            finish_item(wr);

            // ---- READ back the same addr/len/size/id ----
            rd = axi4_seq_item::type_id::create("rd");
            start_item(rd);
            if (!rd.randomize() with {
                    dir   == AXI_READ;
                    burst == AXI_INCR;
                    addr  == wr.addr;
                    len   == wr.len;
                    size  == wr.size;
                    id    == wr.id;
                })
                `uvm_error("RAND", "read randomize() failed")
            finish_item(rd);
        end
    endtask
endclass

`endif

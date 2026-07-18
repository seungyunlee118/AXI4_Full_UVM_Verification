//=============================================================
// axi4_ref_model — golden memory model
//
// Predicts what memory SHOULD contain if the DUT implements AXI
// correctly. Deliberately independent of the DUT's implementation:
//   - byte-granular (so write strobes are modelled exactly)
//   - uses axi4_seq_item::beat_addr(), which implements *correct*
//     FIXED / INCR / WRAP addressing
//
// The DUT increments the address linearly even for WRAP bursts, so
// a WRAP write/read pair will disagree with this model — that is a
// real DUT bug, not a modelling error.
//=============================================================
`ifndef AXI4_REF_MODEL_SVH
`define AXI4_REF_MODEL_SVH

class axi4_ref_model extends uvm_object;

    `uvm_object_utils(axi4_ref_model)

    // Sparse byte-addressed memory. The DUT zeroes its array at time 0,
    // so any byte we never wrote is predicted as 0x00.
    protected bit [7:0] mem [bit [AXI_ADDR_WIDTH-1:0]];

    function new(string name = "axi4_ref_model");
        super.new(name);
    endfunction

    function void reset();
        mem.delete();
    endfunction

    function bit [7:0] read_byte(bit [AXI_ADDR_WIDTH-1:0] a);
        return mem.exists(a) ? mem[a] : 8'h00;
    endfunction

    //---------------------------------------------------------
    // Apply an observed write burst to the model.
    // Byte lane `lane` of the bus carries the byte at
    // (bus-aligned address + lane) — same mapping the DUT uses
    // when it indexes mem[addr >> 2] and writes byte `lane`.
    //---------------------------------------------------------
    function void apply_write(axi4_seq_item tr);
        bit [AXI_ADDR_WIDTH-1:0] a, word_base;
        foreach (tr.data[i]) begin
            a         = tr.beat_addr(i);
            word_base = a - (a % AXI_STRB_WIDTH);
            for (int lane = 0; lane < AXI_STRB_WIDTH; lane++)
                if (tr.strb[i][lane])
                    mem[word_base + lane] = tr.data[i][8*lane +: 8];
        end
    endfunction

    //---------------------------------------------------------
    // Expected bus word for beat i of a read burst.
    // The DUT returns the whole 32-bit word at mem[addr>>2], so we
    // assemble the full aligned word here; the scoreboard then only
    // compares the lanes that are actually addressed by this beat.
    //---------------------------------------------------------
    function bit [AXI_DATA_WIDTH-1:0] expected_beat(axi4_seq_item tr, int i);
        bit [AXI_ADDR_WIDTH-1:0] a, word_base;
        a         = tr.beat_addr(i);
        word_base = a - (a % AXI_STRB_WIDTH);
        for (int lane = 0; lane < AXI_STRB_WIDTH; lane++)
            expected_beat[8*lane +: 8] = read_byte(word_base + lane);
    endfunction

endclass

`endif

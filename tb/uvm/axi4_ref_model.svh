
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

//=============================================================
// axi4_seq_item — one AXI4 burst (write OR read) as a UVM object
//
// This is the "unit of stimulus". Sequences randomize these and
// hand them to the driver; the monitor rebuilds them from the pins.
//=============================================================
`ifndef AXI4_SEQ_ITEM_SVH
`define AXI4_SEQ_ITEM_SVH

class axi4_seq_item extends uvm_sequence_item;

    // ---- Address / control (shared shape for AW and AR) ----
    rand bit [AXI_ID_WIDTH-1:0]   id;
    rand bit [AXI_ADDR_WIDTH-1:0] addr;
    rand bit [7:0]                len;    // number of beats - 1  (AXI encoding)
    rand bit [2:0]                size;   // bytes per beat = 2**size
    rand axi_burst_e              burst;
    rand axi_dir_e                dir;    // READ or WRITE

    // ---- Data payload: one entry per beat ----
    rand bit [AXI_DATA_WIDTH-1:0] data [];
    rand bit [AXI_STRB_WIDTH-1:0] strb [];

    // ---- Result captured from the DUT (not randomized) ----
    axi_resp_e                    resp = AXI_OKAY;

    // Register with the factory so tests can create/override by type name.
    `uvm_object_utils(axi4_seq_item)

    function new(string name = "axi4_seq_item");
        super.new(name);
    endfunction

    //---------------------------------------------------------
    // Constraints = the legal AXI stimulus space
    //---------------------------------------------------------
    // Keep bursts short while bringing the env up (1..16 beats).
    constraint c_len  { len inside {[0:15]}; }

    // Transfer size cannot exceed the data-bus width (2**size <= STRB_WIDTH).
    constraint c_size { size <= $clog2(AXI_STRB_WIDTH); }

    // Mostly INCR, but keep some FIXED/WRAP so we can stress the DUT later.
    constraint c_burst_dist {
        burst dist { AXI_INCR := 8, AXI_FIXED := 1, AXI_WRAP := 1 };
    }

    // WRAP bursts are only legal with 2, 4, 8 or 16 beats.
    constraint c_wrap_len { (burst == AXI_WRAP) -> len inside {1, 3, 7, 15}; }

    // Start address aligned to the transfer size.
    constraint c_align { addr % (1 << size) == 0; }

    // A single burst must not cross a 4 KB boundary (AXI rule).
    constraint c_4k { (addr % 4096) + ((len + 1) << size) <= 4096; }

    // Payload arrays are sized to the beat count.
    constraint c_payload { data.size() == len + 1; strb.size() == len + 1; }

    // Reads have no write strobes -> force them all-ones for clean logs.
    function void post_randomize();
        if (dir == AXI_READ)
            foreach (strb[i]) strb[i] = '1;
    endfunction

    //---------------------------------------------------------
    // Helpers
    //---------------------------------------------------------
    function int unsigned beats();          return len + 1;      endfunction
    function int unsigned bytes_per_beat(); return (1 << size);  endfunction

    //---------------------------------------------------------
    // convert2string — one readable log line (+ per-beat detail)
    //---------------------------------------------------------
    virtual function string convert2string();
        convert2string = $sformatf(
            "%-5s id=%0d addr=0x%04h len=%0d(%0d beats) size=%0d(%0dB) burst=%-5s resp=%s",
            dir.name(), id, addr, len, beats(), size, bytes_per_beat(),
            burst.name(), resp.name());
        foreach (data[i])
            convert2string = {convert2string,
                $sformatf("\n        beat[%0d] data=0x%08h strb=0x%01h", i, data[i], strb[i])};
    endfunction

    //---------------------------------------------------------
    // do_copy — deep copy (dynamic arrays need explicit handling)
    //   Called by clone()/copy(). Manual impl is faster and clearer
    //   than the `uvm_field_* automation macros.
    //---------------------------------------------------------
    virtual function void do_copy(uvm_object rhs);
        axi4_seq_item t;
        if (!$cast(t, rhs))
            `uvm_fatal("DO_COPY", "rhs is not an axi4_seq_item")
        super.do_copy(rhs);
        id    = t.id;    addr  = t.addr;  len   = t.len;
        size  = t.size;  burst = t.burst; dir   = t.dir;   resp = t.resp;
        data  = new[t.data.size()](t.data);   // copy contents, not the handle
        strb  = new[t.strb.size()](t.strb);
    endfunction

    //---------------------------------------------------------
    // do_compare — field-by-field equality (used by the Week 4 scoreboard)
    //---------------------------------------------------------
    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        axi4_seq_item t;
        if (!$cast(t, rhs)) return 0;
        do_compare = super.do_compare(rhs, comparer)
                   && (id == t.id) && (addr == t.addr) && (len == t.len)
                   && (size == t.size) && (burst == t.burst) && (dir == t.dir);
        if (data.size() != t.data.size()) return 0;
        foreach (data[i])
            do_compare &= (data[i] === t.data[i]);
    endfunction

endclass

`endif

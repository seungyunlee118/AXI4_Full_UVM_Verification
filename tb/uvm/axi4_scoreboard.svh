
`ifndef AXI4_SCOREBOARD_SVH
`define AXI4_SCOREBOARD_SVH

class axi4_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(axi4_scoreboard)

    // The monitor writes observed transactions into this port.
    uvm_analysis_imp #(axi4_seq_item, axi4_scoreboard) ap_imp;

    axi4_ref_model ref_model;

    int unsigned n_writes, n_reads, n_beats, n_mismatch;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap_imp = new("ap_imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ref_model = axi4_ref_model::type_id::create("ref_model");
    endfunction

    // Called by the analysis port for every completed burst.
    function void write(axi4_seq_item tr);
        if (tr.dir == AXI_WRITE) begin
            ref_model.apply_write(tr);
            n_writes++;
        end
        else begin
            check_read(tr);
            n_reads++;
        end
    endfunction

    protected function void check_read(axi4_seq_item tr);
        bit [AXI_DATA_WIDTH-1:0] exp;
        bit [AXI_STRB_WIDTH-1:0] mask;
        foreach (tr.data[i]) begin
            exp  = ref_model.expected_beat(tr, i);
            mask = tr.lane_mask(i);
            n_beats++;
            for (int lane = 0; lane < AXI_STRB_WIDTH; lane++) begin
                if (!mask[lane]) continue;              // lane not addressed
                if (tr.data[i][8*lane +: 8] !== exp[8*lane +: 8]) begin
                    n_mismatch++;
                    `uvm_error("SB_MISMATCH", $sformatf(
                        "READ mismatch @beat %0d lane %0d: addr=0x%04h burst=%s size=%0d len=%0d | expected 0x%02h, got 0x%02h",
                        i, lane, tr.beat_addr(i), tr.burst.name(), tr.size, tr.len,
                        exp[8*lane +: 8], tr.data[i][8*lane +: 8]))
                end
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SB", $sformatf(
            "scoreboard: %0d write bursts, %0d read bursts, %0d beats checked, %0d byte mismatches",
            n_writes, n_reads, n_beats, n_mismatch), UVM_LOW)
    endfunction

endclass

`endif

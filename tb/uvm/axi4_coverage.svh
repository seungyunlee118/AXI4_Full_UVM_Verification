
`ifndef AXI4_COVERAGE_SVH
`define AXI4_COVERAGE_SVH

// How the write strobes of a burst look overall.
typedef enum { STRB_NONE, STRB_PARTIAL, STRB_FULL } axi_strb_kind_e;

class axi4_coverage extends uvm_subscriber #(axi4_seq_item);

    `uvm_component_utils(axi4_coverage)

    // Sampled item + derived values the covergroup reads.
    axi4_seq_item   tr;
    axi_strb_kind_e strb_kind;

    int unsigned n_sampled;

    //---------------------------------------------------------
    covergroup axi_cg;
        option.per_instance = 1;
        option.name         = "axi4_functional_coverage";

        cp_dir: coverpoint tr.dir {
            bins rd = {AXI_READ};
            bins wr = {AXI_WRITE};
        }

        cp_burst: coverpoint tr.burst {
            bins fixed = {AXI_FIXED};
            bins incr  = {AXI_INCR};
            bins wrap  = {AXI_WRAP};
        }

        cp_size: coverpoint tr.size {
            bins bytes1 = {0};
            bins bytes2 = {1};
            bins bytes4 = {2};
            ignore_bins too_wide = {[3:7]};   // impossible on a 32-bit bus
        }

        cp_len: coverpoint tr.len {
            bins single   = {0};            // 1 beat
            bins len_2_4  = {[1:3]};
            bins len_5_8  = {[4:7]};
            bins len_9_16 = {[8:15]};
            ignore_bins beyond = {[16:255]}; // stimulus is constrained to <=16 beats
        }

        cp_resp: coverpoint tr.resp {
            bins okay = {AXI_OKAY};
            // The DUT hardwires bresp/rresp to OKAY, so error responses are
            // unreachable by construction. Ignored on purpose (documented
            // DUT limitation), not an open coverage hole.
            ignore_bins unreachable = {AXI_EXOKAY, AXI_SLVERR, AXI_DECERR};
        }

        // 4 KB region of the 64 KB space
        cp_region: coverpoint tr.addr[15:12] {
            bins region[16] = {[0:15]};
        }

        // Write-strobe shape (writes only)
        cp_strb: coverpoint strb_kind iff (tr.dir == AXI_WRITE) {
            bins none    = {STRB_NONE};
            bins partial = {STRB_PARTIAL};
            bins full    = {STRB_FULL};
        }

        // Crosses — the interesting combinations
        x_burst_size : cross cp_burst, cp_size;

        x_burst_len  : cross cp_burst, cp_len {
            // A WRAP burst must be 2, 4, 8 or 16 beats, so a single-beat
            // WRAP cannot exist. Unreachable by construction, not a hole.
            ignore_bins wrap_single = binsof(cp_burst.wrap) && binsof(cp_len.single);
        }

        x_dir_burst  : cross cp_dir,   cp_burst;
    endgroup

    //---------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
        axi_cg = new();
    endfunction

    // Called by the analysis port for every observed burst.
    function void write(axi4_seq_item t);
        tr        = t;
        strb_kind = classify_strb(t);
        axi_cg.sample();
        n_sampled++;
    endfunction

    // FULL  : every beat drives all of its addressed lanes
    // NONE  : no beat drives any lane
    // PARTIAL: anything in between
    protected function axi_strb_kind_e classify_strb(axi4_seq_item t);
        bit all_full = 1;
        bit all_zero = 1;
        foreach (t.strb[i]) begin
            if (t.strb[i] !== t.lane_mask(i)) all_full = 0;
            if (t.strb[i] !== '0)             all_zero = 0;
        end
        if (all_zero) return STRB_NONE;
        if (all_full) return STRB_FULL;
        return STRB_PARTIAL;
    endfunction

    //---------------------------------------------------------
    // Per-coverpoint report, printed at the end of the run.
    //
    // Vivado's external report generator (xcrg) needs a PRO license
    // tier, which the free BASIC tier does not have — so we build the
    // report from the SystemVerilog coverage API instead. This works
    // on any simulator and costs nothing.
    //---------------------------------------------------------
    function string coverage_report();
        coverage_report = {
            "\n",
            "=========== AXI4 functional coverage ===========\n",
            $sformatf("  bursts sampled : %0d\n", n_sampled),
            "  ---------------------------------------------\n",
            $sformatf("  %-14s %7.2f %%\n", "cp_dir",    axi_cg.cp_dir.get_inst_coverage()),
            $sformatf("  %-14s %7.2f %%\n", "cp_burst",  axi_cg.cp_burst.get_inst_coverage()),
            $sformatf("  %-14s %7.2f %%\n", "cp_size",   axi_cg.cp_size.get_inst_coverage()),
            $sformatf("  %-14s %7.2f %%\n", "cp_len",    axi_cg.cp_len.get_inst_coverage()),
            $sformatf("  %-14s %7.2f %%\n", "cp_resp",   axi_cg.cp_resp.get_inst_coverage()),
            $sformatf("  %-14s %7.2f %%\n", "cp_region", axi_cg.cp_region.get_inst_coverage()),
            $sformatf("  %-14s %7.2f %%\n", "cp_strb",   axi_cg.cp_strb.get_inst_coverage()),
            "  ---------------------------------------------\n",
            $sformatf("  %-14s %7.2f %%\n", "x_burst_size", axi_cg.x_burst_size.get_inst_coverage()),
            $sformatf("  %-14s %7.2f %%\n", "x_burst_len",  axi_cg.x_burst_len.get_inst_coverage()),
            $sformatf("  %-14s %7.2f %%\n", "x_dir_burst",  axi_cg.x_dir_burst.get_inst_coverage()),
            "  =============================================\n",
            $sformatf("  %-14s %7.2f %%\n", "TOTAL", axi_cg.get_inst_coverage()),
            "===============================================\n"
        };
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COV", coverage_report(), UVM_LOW)
    endfunction

endclass

`endif

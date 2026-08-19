
`ifndef AXI4_DRIVER_SVH
`define AXI4_DRIVER_SVH

class axi4_driver extends uvm_driver #(axi4_seq_item);

    `uvm_component_utils(axi4_driver)

    axi4_agent_cfg  cfg;
    virtual axi4_if vif;

    // Per-channel work queues
    protected axi4_seq_item aw_q[$];   // writes waiting to issue AW
    protected axi4_seq_item w_q[$];    // writes waiting to send W beats
    protected axi4_seq_item ar_q[$];   // reads waiting to issue AR

    // Bursts accepted from the sequencer but not yet finished on the bus
    protected int unsigned  n_inflight;

    int unsigned wr_outstanding, wr_peak;
    int unsigned rd_outstanding, rd_peak;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi4_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "axi4_agent_cfg not found for driver")
        vif = cfg.vif;
    endfunction

    // True when nothing is queued and nothing is on the bus.
    // The test uses this to drain before dropping its objection.
    function bit is_idle();
        return (aw_q.size() == 0) && (w_q.size() == 0) &&
               (ar_q.size() == 0) && (n_inflight == 0);
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("DRV", $sformatf(
            "outstanding on the bus: peak writes = %0d, peak reads = %0d (max_outstanding = %0d)",
            wr_peak, rd_peak, cfg.max_outstanding), UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);
        reset_signals();
        @(negedge vif.rst);
        @(vif.master_cb);
        `uvm_info("DRV", $sformatf("driver running, max_outstanding=%0d",
                                   cfg.max_outstanding), UVM_LOW)
        fork
            item_thread();
            aw_thread();
            w_thread();
            b_thread();
            ar_thread();
            r_thread();
        join
    endtask

    // Park all master-driven signals in their inactive state.
    task reset_signals();
        vif.master_cb.awvalid <= 1'b0;
        vif.master_cb.awlock  <= 1'b0;
        vif.master_cb.awcache <= '0;
        vif.master_cb.awprot  <= '0;
        vif.master_cb.wvalid  <= 1'b0;
        vif.master_cb.wlast   <= 1'b0;
        vif.master_cb.bready  <= 1'b0;
        vif.master_cb.arvalid <= 1'b0;
        vif.master_cb.arlock  <= 1'b0;
        vif.master_cb.arcache <= '0;
        vif.master_cb.arprot  <= '0;
        vif.master_cb.rready  <= 1'b0;
    endtask

    //---------------------------------------------------------
    // Sequencer -> channel queues
    //---------------------------------------------------------
    task item_thread();
        forever begin
            seq_item_port.get_next_item(req);

            // Throttle to the configured outstanding depth.
            while (n_inflight >= cfg.max_outstanding) @(vif.master_cb);

            if (req.dir == AXI_WRITE) begin
                aw_q.push_back(req);
                w_q.push_back(req);      // same order -> AXI write-data order
            end
            else begin
                ar_q.push_back(req);
            end
            n_inflight++;

            // Return the item now, so the sequence can produce the next one
            // while this burst is still on the bus. This is what creates
            // multiple outstanding transactions.
            seq_item_port.item_done();
        end
    endtask

    //---------------------------------------------------------
    // Write address channel
    //---------------------------------------------------------
    task aw_thread();
        axi4_seq_item tr;
        forever begin
            while (aw_q.size() == 0) @(vif.master_cb);
            tr = aw_q.pop_front();

            vif.master_cb.awid    <= tr.id;
            vif.master_cb.awaddr  <= tr.addr;
            vif.master_cb.awlen   <= tr.len;
            vif.master_cb.awsize  <= tr.size;
            vif.master_cb.awburst <= tr.burst;
            vif.master_cb.awvalid <= 1'b1;
            @(vif.master_cb);
            while (!vif.master_cb.awready) @(vif.master_cb);
            vif.master_cb.awvalid <= 1'b0;
            wr_outstanding++;
            if (wr_outstanding > wr_peak) wr_peak = wr_outstanding;
        end
    endtask

    //---------------------------------------------------------
    // Write data channel — beats in AW order
    //---------------------------------------------------------
    task w_thread();
        axi4_seq_item tr;
        forever begin
            while (w_q.size() == 0) @(vif.master_cb);
            tr = w_q.pop_front();

            foreach (tr.data[i]) begin
                vif.master_cb.wdata  <= tr.data[i];
                vif.master_cb.wstrb  <= tr.strb[i];
                vif.master_cb.wlast  <= (i == tr.len);
                vif.master_cb.wvalid <= 1'b1;
                @(vif.master_cb);
                while (!vif.master_cb.wready) @(vif.master_cb);
                vif.master_cb.wvalid <= 1'b0;
                vif.master_cb.wlast  <= 1'b0;
            end
        end
    endtask

    //---------------------------------------------------------
    // Write response channel — always ready, count completions
    //---------------------------------------------------------
    task b_thread();
        vif.master_cb.bready <= 1'b1;
        forever begin
            @(vif.master_cb);
            if (vif.master_cb.bvalid) begin
                if (n_inflight > 0)     n_inflight--;
                if (wr_outstanding > 0) wr_outstanding--;
            end
        end
    endtask

    //---------------------------------------------------------
    // Read address channel
    //---------------------------------------------------------
    task ar_thread();
        axi4_seq_item tr;
        forever begin
            while (ar_q.size() == 0) @(vif.master_cb);
            tr = ar_q.pop_front();

            vif.master_cb.arid    <= tr.id;
            vif.master_cb.araddr  <= tr.addr;
            vif.master_cb.arlen   <= tr.len;
            vif.master_cb.arsize  <= tr.size;
            vif.master_cb.arburst <= tr.burst;
            vif.master_cb.arvalid <= 1'b1;
            @(vif.master_cb);
            while (!vif.master_cb.arready) @(vif.master_cb);
            vif.master_cb.arvalid <= 1'b0;
            rd_outstanding++;
            if (rd_outstanding > rd_peak) rd_peak = rd_outstanding;
        end
    endtask

    //---------------------------------------------------------
    // Read data channel — always ready, a burst ends on RLAST
    //---------------------------------------------------------
    task r_thread();
        vif.master_cb.rready <= 1'b1;
        forever begin
            @(vif.master_cb);
            if (vif.master_cb.rvalid && vif.master_cb.rlast) begin
                if (n_inflight > 0)     n_inflight--;
                if (rd_outstanding > 0) rd_outstanding--;
            end
        end
    endtask

endclass

`endif

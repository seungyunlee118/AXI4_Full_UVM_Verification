
`ifndef AXI4_MONITOR_SVH
`define AXI4_MONITOR_SVH

class axi4_monitor extends uvm_monitor;

    `uvm_component_utils(axi4_monitor)

    axi4_agent_cfg  cfg;
    virtual axi4_if vif;

    // Broadcasts completed transactions to the scoreboard and coverage.
    uvm_analysis_port #(axi4_seq_item) ap;

    // Address phases waiting for their data / response phases
    protected axi4_seq_item aw_q[$];      // AW seen, W beats not finished
    protected axi4_seq_item w_done_q[$];  // W finished, waiting for B
    protected axi4_seq_item ar_q[$];      // AR seen, R beats not finished

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi4_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "axi4_agent_cfg not found for monitor")
        vif = cfg.vif;
    endfunction

    task run_phase(uvm_phase phase);
        @(negedge vif.rst);
        fork
            mon_aw();
            mon_w();
            mon_b();
            mon_ar();
            mon_r();
        join
    endtask

    //---------------------------------------------------------
    // Write address phase
    //---------------------------------------------------------
    task mon_aw();
        axi4_seq_item tr;
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.awvalid && vif.monitor_cb.awready) begin
                tr       = axi4_seq_item::type_id::create("mon_wr");
                tr.dir   = AXI_WRITE;
                tr.id    = vif.monitor_cb.awid;
                tr.addr  = vif.monitor_cb.awaddr;
                tr.len   = vif.monitor_cb.awlen;
                tr.size  = vif.monitor_cb.awsize;
                tr.burst = axi_burst_e'(vif.monitor_cb.awburst);
                tr.data  = new[tr.len + 1];
                tr.strb  = new[tr.len + 1];
                aw_q.push_back(tr);
            end
        end
    endtask

    //---------------------------------------------------------
    // Write data phase — beats belong to the oldest pending AW
    //---------------------------------------------------------
    task mon_w();
        axi4_seq_item tr;
        int unsigned  beat = 0;
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.wvalid && vif.monitor_cb.wready) begin
                if (aw_q.size() == 0) begin
                    `uvm_warning("MON", "W beat with no outstanding AW - ignored")
                end
                else begin
                    tr = aw_q[0];
                    if (beat <= tr.len) begin
                        tr.data[beat] = vif.monitor_cb.wdata;
                        tr.strb[beat] = vif.monitor_cb.wstrb;
                    end
                    if (vif.monitor_cb.wlast) begin
                        void'(aw_q.pop_front());
                        w_done_q.push_back(tr);
                        beat = 0;
                    end
                    else beat++;
                end
            end
        end
    endtask

    //---------------------------------------------------------
    // Write response phase — completes the oldest finished burst
    //---------------------------------------------------------
    task mon_b();
        axi4_seq_item tr;
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.bvalid && vif.monitor_cb.bready) begin
                if (w_done_q.size() == 0) begin
                    `uvm_warning("MON", "B response with no completed write burst")
                end
                else begin
                    tr      = w_done_q.pop_front();
                    tr.resp = axi_resp_e'(vif.monitor_cb.bresp);
                    `uvm_info("MON", $sformatf("WRITE seen: %s", tr.convert2string()),
                              UVM_MEDIUM)
                    ap.write(tr);
                end
            end
        end
    endtask

    //---------------------------------------------------------
    // Read address phase
    //---------------------------------------------------------
    task mon_ar();
        axi4_seq_item tr;
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.arvalid && vif.monitor_cb.arready) begin
                tr       = axi4_seq_item::type_id::create("mon_rd");
                tr.dir   = AXI_READ;
                tr.id    = vif.monitor_cb.arid;
                tr.addr  = vif.monitor_cb.araddr;
                tr.len   = vif.monitor_cb.arlen;
                tr.size  = vif.monitor_cb.arsize;
                tr.burst = axi_burst_e'(vif.monitor_cb.arburst);
                tr.data  = new[tr.len + 1];
                tr.strb  = new[tr.len + 1];
                foreach (tr.strb[j]) tr.strb[j] = '1;   // reads have no strobes
                ar_q.push_back(tr);
            end
        end
    endtask

    //---------------------------------------------------------
    // Read data phase — beats belong to the oldest pending AR
    //---------------------------------------------------------
    task mon_r();
        axi4_seq_item tr;
        int unsigned  beat = 0;
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.rvalid && vif.monitor_cb.rready) begin
                if (ar_q.size() == 0) begin
                    `uvm_warning("MON", "R beat with no outstanding AR - ignored")
                end
                else begin
                    tr = ar_q[0];
                    if (beat <= tr.len)
                        tr.data[beat] = vif.monitor_cb.rdata;
                    tr.resp = axi_resp_e'(vif.monitor_cb.rresp);
                    if (vif.monitor_cb.rlast) begin
                        void'(ar_q.pop_front());
                        `uvm_info("MON", $sformatf("READ  seen: %s", tr.convert2string()),
                                  UVM_MEDIUM)
                        ap.write(tr);
                        beat = 0;
                    end
                    else beat++;
                end
            end
        end
    endtask

endclass

`endif

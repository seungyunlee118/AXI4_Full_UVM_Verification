//=============================================================
// axi4_monitor — passive AXI observer
//
// Watches the bus through the monitor clocking block and rebuilds
// transactions from the handshakes, then broadcasts each completed
// transaction on an analysis port. It NEVER drives anything.
// Write and read channels are watched in parallel (fork/join).
//=============================================================
`ifndef AXI4_MONITOR_SVH
`define AXI4_MONITOR_SVH

class axi4_monitor extends uvm_monitor;

    `uvm_component_utils(axi4_monitor)

    axi4_agent_cfg  cfg;
    virtual axi4_if vif;

    // Broadcasts observed transactions to any subscribers (scoreboard,
    // coverage collector, ...). Nothing has to be connected for it to work.
    uvm_analysis_port #(axi4_seq_item) ap;

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
            mon_write();
            mon_read();
        join
    endtask

    //---------------------------------------------------------
    // Rebuild a write burst: AW handshake -> N W beats -> B response
    //---------------------------------------------------------
    task mon_write();
        forever begin
            axi4_seq_item tr;

            // 1) wait for the AW handshake, capture address/control
            do @(vif.monitor_cb);
            while (!(vif.monitor_cb.awvalid && vif.monitor_cb.awready));

            tr       = axi4_seq_item::type_id::create("mon_wr");
            tr.dir   = AXI_WRITE;
            tr.id    = vif.monitor_cb.awid;
            tr.addr  = vif.monitor_cb.awaddr;
            tr.len   = vif.monitor_cb.awlen;
            tr.size  = vif.monitor_cb.awsize;
            tr.burst = axi_burst_e'(vif.monitor_cb.awburst);
            tr.data  = new[tr.len + 1];
            tr.strb  = new[tr.len + 1];

            // 2) capture each W beat
            for (int i = 0; i <= tr.len; i++) begin
                do @(vif.monitor_cb);
                while (!(vif.monitor_cb.wvalid && vif.monitor_cb.wready));
                tr.data[i] = vif.monitor_cb.wdata;
                tr.strb[i] = vif.monitor_cb.wstrb;
            end

            // 3) capture the B response
            do @(vif.monitor_cb);
            while (!(vif.monitor_cb.bvalid && vif.monitor_cb.bready));
            tr.resp = axi_resp_e'(vif.monitor_cb.bresp);

            `uvm_info("MON", $sformatf("WRITE seen: %s", tr.convert2string()), UVM_MEDIUM)
            ap.write(tr);
        end
    endtask

    //---------------------------------------------------------
    // Rebuild a read burst: AR handshake -> N R beats (until rlast)
    //---------------------------------------------------------
    task mon_read();
        forever begin
            axi4_seq_item tr;

            do @(vif.monitor_cb);
            while (!(vif.monitor_cb.arvalid && vif.monitor_cb.arready));

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

            for (int i = 0; i <= tr.len; i++) begin
                do @(vif.monitor_cb);
                while (!(vif.monitor_cb.rvalid && vif.monitor_cb.rready));
                tr.data[i] = vif.monitor_cb.rdata;
                tr.resp    = axi_resp_e'(vif.monitor_cb.rresp);
            end

            `uvm_info("MON", $sformatf("READ  seen: %s", tr.convert2string()), UVM_MEDIUM)
            ap.write(tr);
        end
    endtask

endclass

`endif

//=============================================================
// axi4_driver — AXI master driver
//
// run_phase loop: get a transaction from the sequencer, translate it
// into pin-level AXI handshakes, tell the sequencer we're done.
// Drives through the interface's master clocking block (master_cb),
// which applies the correct input-sample / output-drive skews and
// avoids clock-edge races.
//=============================================================
`ifndef AXI4_DRIVER_SVH
`define AXI4_DRIVER_SVH

class axi4_driver extends uvm_driver #(axi4_seq_item);

    `uvm_component_utils(axi4_driver)

    axi4_agent_cfg  cfg;
    virtual axi4_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi4_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "axi4_agent_cfg not found for driver")
        vif = cfg.vif;
    endfunction

    task run_phase(uvm_phase phase);
        reset_signals();
        // Hold off driving until reset is de-asserted.
        @(negedge vif.rst);
        @(vif.master_cb);
        forever begin
            seq_item_port.get_next_item(req);   // blocking: wait for stimulus
            drive(req);
            seq_item_port.item_done();          // handshake back to sequencer
        end
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

    task drive(axi4_seq_item tr);
        if (tr.dir == AXI_WRITE) drive_write(tr);
        else                     drive_read(tr);
        `uvm_info("DRV", $sformatf("drove %s", tr.convert2string()), UVM_HIGH)
    endtask

    //---------------------------------------------------------
    // WRITE: AW and W run concurrently (fork), then wait for B.
    //   The DUT only raises wready AFTER accepting AW, so the W
    //   thread simply waits until wready appears — no deadlock.
    //---------------------------------------------------------
    task drive_write(axi4_seq_item tr);
        fork
            begin : aw_channel
                vif.master_cb.awid    <= tr.id;
                vif.master_cb.awaddr  <= tr.addr;
                vif.master_cb.awlen   <= tr.len;
                vif.master_cb.awsize  <= tr.size;
                vif.master_cb.awburst <= tr.burst;
                vif.master_cb.awvalid <= 1'b1;
                @(vif.master_cb);
                while (!vif.master_cb.awready) @(vif.master_cb);
                vif.master_cb.awvalid <= 1'b0;
            end
            begin : w_channel
                foreach (tr.data[i]) begin
                    vif.master_cb.wdata  <= tr.data[i];
                    vif.master_cb.wstrb  <= tr.strb[i];
                    vif.master_cb.wlast  <= (i == tr.len);   // last beat flag
                    vif.master_cb.wvalid <= 1'b1;
                    @(vif.master_cb);
                    while (!vif.master_cb.wready) @(vif.master_cb);
                    vif.master_cb.wvalid <= 1'b0;
                    vif.master_cb.wlast  <= 1'b0;
                end
            end
        join
        // B channel: accept the write response.
        vif.master_cb.bready <= 1'b1;
        @(vif.master_cb);
        while (!vif.master_cb.bvalid) @(vif.master_cb);
        tr.resp = axi_resp_e'(vif.master_cb.bresp);
        vif.master_cb.bready <= 1'b0;
    endtask

    //---------------------------------------------------------
    // READ: drive AR, then accept R beats until the last one.
    //   Captured read data is written back into tr.data[].
    //---------------------------------------------------------
    task drive_read(axi4_seq_item tr);
        vif.master_cb.arid    <= tr.id;
        vif.master_cb.araddr  <= tr.addr;
        vif.master_cb.arlen   <= tr.len;
        vif.master_cb.arsize  <= tr.size;
        vif.master_cb.arburst <= tr.burst;
        vif.master_cb.arvalid <= 1'b1;
        @(vif.master_cb);
        while (!vif.master_cb.arready) @(vif.master_cb);
        vif.master_cb.arvalid <= 1'b0;

        vif.master_cb.rready <= 1'b1;
        foreach (tr.data[i]) begin
            @(vif.master_cb);
            while (!vif.master_cb.rvalid) @(vif.master_cb);
            tr.data[i] = vif.master_cb.rdata;
            tr.resp    = axi_resp_e'(vif.master_cb.rresp);
        end
        vif.master_cb.rready <= 1'b0;
    endtask

endclass

`endif

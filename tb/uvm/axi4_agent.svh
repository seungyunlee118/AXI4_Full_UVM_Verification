
`ifndef AXI4_AGENT_SVH
`define AXI4_AGENT_SVH

typedef uvm_sequencer #(axi4_seq_item) axi4_sequencer;

class axi4_agent extends uvm_agent;

    `uvm_component_utils(axi4_agent)

    axi4_agent_cfg cfg;
    axi4_sequencer sqr;
    axi4_driver    drv;
    axi4_monitor   mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi4_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "axi4_agent_cfg not found for agent")

        // Forward cfg to the children so driver/monitor can grab the vif.
        uvm_config_db#(axi4_agent_cfg)::set(this, "drv", "cfg", cfg);
        uvm_config_db#(axi4_agent_cfg)::set(this, "mon", "cfg", cfg);

        // Monitor always exists; sequencer/driver only when active.
        mon = axi4_monitor::type_id::create("mon", this);
        if (cfg.is_active == UVM_ACTIVE) begin
            sqr = axi4_sequencer::type_id::create("sqr", this);
            drv = axi4_driver::type_id::create("drv", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Wire the driver to the sequencer's item export.
        if (cfg.is_active == UVM_ACTIVE)
            drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass

`endif

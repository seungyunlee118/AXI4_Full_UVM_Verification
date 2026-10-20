
`ifndef AXI4_AGENT_CFG_SVH
`define AXI4_AGENT_CFG_SVH

class axi4_agent_cfg extends uvm_object;

    virtual axi4_if         vif;
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // How many bursts the driver may keep in flight at once.
    //   1  -> strictly serialised (one burst at a time)
    //   >1 -> pipelined 
    int unsigned max_outstanding = 1;

    `uvm_object_utils(axi4_agent_cfg)

    function new(string name = "axi4_agent_cfg");
        super.new(name);
    endfunction

endclass

`endif

//=============================================================
// axi4_agent_cfg — configuration object for the AXI agent
//
// One small object that carries "how should this agent behave":
//   - vif       : handle to the DUT pins (set by the test from tb_top)
//   - is_active : UVM_ACTIVE  -> build sequencer+driver (drive the bus)
//                 UVM_PASSIVE -> monitor only (just observe)
// Passing knobs via a cfg object (instead of many config_db entries)
// is the standard, scalable UVM style.
//=============================================================
`ifndef AXI4_AGENT_CFG_SVH
`define AXI4_AGENT_CFG_SVH

class axi4_agent_cfg extends uvm_object;

    virtual axi4_if         vif;
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // How many bursts the driver may keep in flight at once.
    //   1  -> strictly serialised (one burst at a time), the safe default
    //         that keeps write-then-read-back sequences ordered
    //   >1 -> pipelined; needed to exercise a DUT that supports multiple
    //         outstanding transactions (axi_ram_v2)
    int unsigned max_outstanding = 1;

    `uvm_object_utils(axi4_agent_cfg)

    function new(string name = "axi4_agent_cfg");
        super.new(name);
    endfunction

endclass

`endif

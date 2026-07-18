//=============================================================
// axi4_env — top-level verification environment
//
// For Week 3 it just holds the AXI agent. In Week 4 the scoreboard
// and coverage collector get built here and connected to the
// monitor's analysis port.
//=============================================================
`ifndef AXI4_ENV_SVH
`define AXI4_ENV_SVH

class axi4_env extends uvm_env;

    `uvm_component_utils(axi4_env)

    axi4_agent     agent;
    axi4_agent_cfg cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi4_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "axi4_agent_cfg not found for env")

        // Hand the same cfg down to the agent.
        uvm_config_db#(axi4_agent_cfg)::set(this, "agent", "cfg", cfg);
        agent = axi4_agent::type_id::create("agent", this);
    endfunction

endclass

`endif

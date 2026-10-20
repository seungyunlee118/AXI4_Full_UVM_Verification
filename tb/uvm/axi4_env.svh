
`ifndef AXI4_ENV_SVH
`define AXI4_ENV_SVH

class axi4_env extends uvm_env;

    `uvm_component_utils(axi4_env)

    axi4_agent      agent;
    axi4_scoreboard sb;
    axi4_coverage   cov;
    axi4_agent_cfg  cfg;

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
        sb    = axi4_scoreboard::type_id::create("sb", this);
        cov   = axi4_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.mon.ap.connect(sb.ap_imp);
        agent.mon.ap.connect(cov.analysis_export);
    endfunction

endclass

`endif

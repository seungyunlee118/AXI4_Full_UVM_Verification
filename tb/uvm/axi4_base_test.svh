//=============================================================
// Tests — top of the UVM hierarchy
//
//   axi4_base_test : builds the env, grabs the virtual interface from
//                    config_db, and runs a default stimulus sequence.
//   Derived tests override get_seq() to swap in different stimulus,
//   selected at run time with +UVM_TESTNAME=<name>.
//=============================================================
`ifndef AXI4_BASE_TEST_SVH
`define AXI4_BASE_TEST_SVH

class axi4_base_test extends uvm_test;

    `uvm_component_utils(axi4_base_test)

    axi4_env       env;
    axi4_agent_cfg cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Build the agent cfg and fetch the DUT handle that tb_top published.
        cfg = axi4_agent_cfg::type_id::create("cfg");
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", "vif", cfg.vif))
            `uvm_fatal("NOVIF", "virtual interface 'vif' was not set by tb_top")
        cfg.is_active = UVM_ACTIVE;

        uvm_config_db#(axi4_agent_cfg)::set(this, "env", "cfg", cfg);
        env = axi4_env::type_id::create("env", this);
    endfunction

    // Print the component hierarchy once built — looks great in logs.
    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    // Derived tests override this to choose their stimulus.
    virtual function axi4_base_seq get_seq();
        axi4_wr_rd_seq s = axi4_wr_rd_seq::type_id::create("seq");
        return s;
    endfunction

    task run_phase(uvm_phase phase);
        axi4_base_seq seq = get_seq();
        phase.raise_objection(this, "stimulus running");
        `uvm_info("TEST", $sformatf("starting sequence '%s' (num=%0d)",
                                    seq.get_type_name(), seq.num), UVM_LOW)
        seq.start(env.agent.sqr);
        #200ns;   // let the final response drain through the monitor
        phase.drop_objection(this, "stimulus done");
    endtask

endclass

//---------------------------------------------------------------
// Convenience tests: pick a single-direction stimulus.
//---------------------------------------------------------------
class axi4_write_test extends axi4_base_test;
    `uvm_component_utils(axi4_write_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function axi4_base_seq get_seq();
        axi4_write_seq s = axi4_write_seq::type_id::create("seq");
        return s;
    endfunction
endclass

class axi4_read_test extends axi4_base_test;
    `uvm_component_utils(axi4_read_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function axi4_base_seq get_seq();
        axi4_read_seq s = axi4_read_seq::type_id::create("seq");
        return s;
    endfunction
endclass

class axi4_rand_test extends axi4_base_test;
    `uvm_component_utils(axi4_rand_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function axi4_base_seq get_seq();
        axi4_rand_seq s = axi4_rand_seq::type_id::create("seq");
        return s;
    endfunction
endclass

// Corner cases: single beat, max burst, 4KB edge, narrow transfers, FIXED.
class axi4_directed_test extends axi4_base_test;
    `uvm_component_utils(axi4_directed_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function axi4_base_seq get_seq();
        axi4_directed_seq s = axi4_directed_seq::type_id::create("seq");
        return s;
    endfunction
endclass

//---------------------------------------------------------------
// WRAP burst test — EXPECTED TO FAIL.
//
// The DUT increments WRAP addresses linearly instead of wrapping them,
// so the scoreboard reports mismatches. This test exists to document
// and reproduce that bug, so it is NOT part of the clean regression.
//---------------------------------------------------------------
class axi4_wrap_test extends axi4_base_test;
    `uvm_component_utils(axi4_wrap_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function axi4_base_seq get_seq();
        axi4_wrap_seq s = axi4_wrap_seq::type_id::create("seq");
        return s;
    endfunction
    function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        `uvm_info("TEST",
            "axi4_wrap_test: UVM_ERRORs below are EXPECTED - they demonstrate the DUT's WRAP-burst bug",
            UVM_LOW)
    endfunction
endclass

`endif

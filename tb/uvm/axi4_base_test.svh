
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
        drain();
        phase.drop_objection(this, "stimulus done");
    endtask

    // The driver is pipelined: item_done() returns as soon as a burst is
    // queued, not when it finishes on the bus. So wait for the driver to
    // go idle before ending the test, otherwise the last bursts would be
    // cut off mid-flight.
    protected task drain();
        int unsigned guard = 0;
        while (!env.agent.drv.is_idle() && guard < 10000) begin
            #100ns;
            guard++;
        end
        if (guard >= 10000)
            `uvm_error("DRAIN", "driver did not go idle - transactions stuck?")
        #200ns;   // let the final response propagate through the monitor
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

// Coverage-closure test: wide stimulus to fill the covergroup bins.
// May report WRAP mismatches (the real DUT bug) - those are true positives.
class axi4_cov_test extends axi4_base_test;
    `uvm_component_utils(axi4_cov_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function axi4_base_seq get_seq();
        axi4_cov_seq s = axi4_cov_seq::type_id::create("seq");
        s.num = 40;              // extra random traffic after the sweep
        return s;
    endfunction
endclass

//---------------------------------------------------------------
// Outstanding-transaction test.
//
// Raises the driver's outstanding depth so several bursts overlap on
// the bus, then checks the data still comes back correctly. The driver
// reports the PEAK number of bursts that were genuinely concurrent:
//   axi_ram    (v1) -> peak 1  (it accepts one address at a time)
//   axi_ram_v2      -> peak >1 (queue-based, OUTSTANDING_DEPTH=4)
// Writes and reads run as separate passes with a drain in between,
// because the AXI read and write channels are independent and a read
// must not overtake a write that has not completed yet.
//---------------------------------------------------------------
class axi4_outstanding_test extends axi4_base_test;
    `uvm_component_utils(axi4_outstanding_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // The driver's build_phase runs after ours, so it picks this up.
        cfg.max_outstanding = 4;
    endfunction

    task run_phase(uvm_phase phase);
        axi4_os_write_seq wr = axi4_os_write_seq::type_id::create("wr");
        axi4_os_read_seq  rd = axi4_os_read_seq::type_id::create("rd");
        phase.raise_objection(this, "outstanding stimulus");

        `uvm_info("TEST", "phase 1 - pipelined writes", UVM_LOW)
        wr.start(env.agent.sqr);
        drain();                     // all writes must land before reading back

        `uvm_info("TEST", "phase 2 - pipelined reads", UVM_LOW)
        rd.start(env.agent.sqr);
        drain();

        phase.drop_objection(this, "done");
    endtask
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

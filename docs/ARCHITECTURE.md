# UVM Testbench Architecture (Week 3+)

```
                          tb_top (module)
   clk/rst gen ─┐   ┌──────────────────────────────┐
                ├──▶│  axi4_if (interface)          │◀── DUT axi_ram
                │   │  master_cb / monitor_cb       │    (pins wired to axi.*)
                │   └───────────────┬───────────────┘
   run_test() ──┘                   │ virtual interface (via uvm_config_db)
                                     ▼
 ┌─────────────────────────── uvm_test (axi4_base_test) ───────────────────────┐
 │  builds cfg (holds vif, is_active), starts a sequence on the sequencer       │
 │                                                                              │
 │   ┌──────────────────────── axi4_env ─────────────────────────────────┐     │
 │   │                                                                    │     │
 │   │   ┌────────────────────── axi4_agent ───────────────────────┐      │     │
 │   │   │                                                          │      │     │
 │   │   │   sequence ──▶ [ sequencer ] ──seq_item──▶ [ driver ] ──▶ pins │     │
 │   │   │                                                     │    │      │     │
 │   │   │                                     [ monitor ] ◀───┘ (observes)     │
 │   │   │                                          │ analysis_port           │ │
 │   │   └──────────────────────────────────────────┼──────────┘      │      │ │
 │   │                                               ▼ (to scoreboard, Week 4) │ │
 │   └────────────────────────────────────────────────────────────────┘      │ │
 └────────────────────────────────────────────────────────────────────────────┘
```

## Component responsibilities

| Component | Base class | Role |
|-----------|-----------|------|
| `axi4_seq_item` | `uvm_sequence_item` | One AXI burst (write or read): addr/ctrl + data[]/strb[] + resp. Randomizable. |
| `axi4_agent_cfg` | `uvm_object` | Knobs: the virtual interface handle + active/passive. |
| `axi4_sequencer` | `uvm_sequencer` | Arbitrates sequences and hands items to the driver (a typedef). |
| `axi4_driver` | `uvm_driver` | Pulls items from the sequencer and wiggles the AXI pins per protocol. |
| `axi4_monitor` | `uvm_monitor` | Passively watches the pins, rebuilds transactions, broadcasts them. |
| `axi4_agent` | `uvm_agent` | Container: sequencer + driver + monitor. Active drives; passive only watches. |
| `axi4_env` | `uvm_env` | Container for agent(s) (+ scoreboard/coverage later). |
| `axi4_*_seq` | `uvm_sequence` | Stimulus programs: what transactions to generate. |
| `axi4_base_test` | `uvm_test` | Top of the hierarchy: builds env, wires cfg, launches a sequence. |

## Key UVM mechanisms used

- **Factory** (`type_id::create` + `uvm_*_utils`): objects/components are created
  through a registry so tests can override types without editing the env.
- **Phases** (`build_phase` → `connect_phase` → `run_phase`): build top-down,
  connect bottom-up, then run in parallel time-consuming threads.
- **`uvm_config_db`**: passes the virtual interface and the cfg object down the
  hierarchy without hard-coded paths.
- **TLM**:
  - sequencer↔driver via `seq_item_port`/`seq_item_export`
    (`get_next_item` / `item_done`);
  - monitor→subscribers via `uvm_analysis_port` (`ap.write()`).
- **Objections**: the sequence/test raises an objection during `run_phase` so the
  simulation stays alive until the stimulus is done, then drops it to finish.

## AXI protocol notes baked into the driver/monitor

- Write: drive **AW** and **W** channels concurrently (`fork`), because the DUT
  only raises `wready` after it has accepted `AW`. Collect **B** at the end.
- Read: drive **AR**, then accept **R** beats until `rlast`.
- Handshake rule: hold `*valid` + payload stable until `*ready` is sampled high
  on a rising clock edge.
- DUT quirks to remember (targets for the Week 4 scoreboard):
  - `bresp`/`rresp` are hardwired to `OKAY` — the DUT can never report an error.
  - `WRAP` bursts are treated like `INCR` (address is incremented linearly, not
    wrapped) — a real bug we will catch by modelling correct WRAP in the ref model.

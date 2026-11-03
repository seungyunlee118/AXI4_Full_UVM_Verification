#!/usr/bin/env python3
"""
Bug-injection (mutation) campaign for the AXI4-Full testbench.

Each mutant is one deliberate defect in rtl/Axi_ram_v2.v, the revision that is
supposed to be correct: a single exact text substitution. For every mutant the
script copies rtl/, applies the change, builds it as v2 and runs the
regression (one seed by default), stopping at the first failing run.

    KILLED      some run failed on a testbench check: scoreboard, assertion,
                drain or watchdog timeout
    SURVIVED    every run passed - the testbench cannot see this bug
    EQUIVALENT  survives, and is listed in EQUIVALENT with the reason
    INVALID     the substitution did not apply exactly once, or did not build
    ERROR       a run failed for a tool reason (crash, wall-clock limit,
                unknown simulator error), so the mutant was not judged

An unmutated baseline runs first and must pass, otherwise the campaign stops.

    python3 mutate.py                  # every mutant, 4 at a time
    python3 mutate.py -m A01 R03       # selected mutants
    python3 mutate.py -j 8 -s 1 7      # more parallelism, two seeds
    python3 mutate.py --list           # print the catalogue
    python3 mutate.py --check          # only verify every mutant applies

Writes mutants/report.md and mutants/<id>/ (patched rtl, build and run logs).
"""

import argparse
import concurrent.futures
import os
import shutil
import sys
import time

import regress

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
RTL = os.path.join(ROOT, "rtl")
OUT = os.path.join(HERE, "mutants")
V2 = "Axi_ram_v2.v"

# Run the tests most likely to fail first, so a killed mutant stops early.
TEST_ORDER = ["axi4_directed_test", "axi4_wrap_test", "axi4_stress_test", "axi4_base_test",
              "axi4_cov_test", "axi4_outstanding_test", "axi4_rand_test", "axi4_read_test",
              "axi4_write_test"]

# (id, file, original text, mutated text, what the bug is)
#   A  address generation    D  data path         L  burst length / LAST
#   R  response code and ID  Q  queues and READY/VALID flow control
MUTANTS = [
    ("A01", V2, "BURST_WRAP:  next_addr_calc = (inc & wrap_mask) | wrap_base;",
                "BURST_WRAP:  next_addr_calc = inc;",
     "WRAP addressed like INCR (the original v1 bug)"),
    ("A02", V2, "BURST_WRAP:  next_addr_calc = (inc & wrap_mask) | wrap_base;",
                "BURST_WRAP:  next_addr_calc = inc & wrap_mask;",
     "WRAP drops the window base"),
    ("A03", V2, "calc_wrap_mask = { { (ADDR_WIDTH-16){1'b0} }, total_bytes } - 1;",
                "calc_wrap_mask = ({ { (ADDR_WIDTH-16){1'b0} }, total_bytes } << 1) - 1;",
     "WRAP window twice the burst size"),
    ("A04", V2, "inc = cur + (1 << size);",
                "inc = cur + 4;",
     "address step ignores AxSIZE (always 4 bytes)"),
    ("A05", V2, "BURST_FIXED: next_addr_calc = cur;",
                "BURST_FIXED: next_addr_calc = inc;",
     "FIXED bursts increment like INCR"),
    ("A06", V2, "in_ar_wrap_base = s_axi_araddr & ~in_ar_wrap_mask;",
                "in_ar_wrap_base = s_axi_araddr;",
     "read WRAP base not aligned to the window"),
    ("A07", V2, "in_aw_wrap_base = s_axi_awaddr & ~in_aw_wrap_mask;",
                "in_aw_wrap_base = s_axi_awaddr;",
     "write WRAP base not aligned to the window"),

    ("D01", V2, "if (s_axi_wstrb[wi]) begin",
                "if (1'b1) begin",
     "write ignores WSTRB (every lane written)"),
    ("D02", V2, "if (s_axi_wstrb[wi]) begin",
                "if (s_axi_wstrb[WORD_WIDTH-1-wi]) begin",
     "WSTRB lanes reversed"),
    ("D03", V2, "<= s_axi_wdata[WORD_SIZE*wi +: WORD_SIZE];",
                "<= s_axi_wdata[0 +: WORD_SIZE];",
     "every lane written with lane 0's byte"),
    ("D04", V2, "s_axi_rdata_reg <= mem[r_word_addr];",
                "s_axi_rdata_reg <= mem[r_word_addr + 1'b1];",
     "read returns the next word"),
    ("D05", V2, "if (mem_rd_en) begin",
                "if (1'b1) begin",
     "read data reloads every cycle, even while R is stalled"),

    ("L01", V2, "s_axi_rlast_reg  <= (r_remain == 0);",
                "s_axi_rlast_reg  <= (r_remain == 1);",
     "RLAST one beat early"),
    ("L02", V2, "r_remain    <= ar_head_len;",
                "r_remain    <= ar_head_len + 1'b1;",
     "read burst one beat too long"),
    ("L03", V2, "w_remain    <= aw_head_len;",
                "w_remain    <= aw_head_len - 1'b1;",
     "write engine takes one beat fewer than AWLEN"),
    ("L04", V2, "if (w_last_beat) begin",
                "if (w_beat) begin",
     "a B response per W beat (B before WLAST)"),

    ("R01", V2, "b_q[b_wr_ptr] <= {b_push_id, RESP_OKAY};",
                "b_q[b_wr_ptr] <= {b_push_id, 2'b10};",
     "BRESP = SLVERR on every write"),
    ("R02", V2, "assign s_axi_rresp  = RESP_OKAY;",
                "assign s_axi_rresp  = 2'b10;",
     "RRESP = SLVERR on every read"),
    ("R03", V2, "b_push_id = w_cur_id;",
                "b_push_id = {ID_WIDTH{1'b0}};",
     "BID always 0"),
    ("R04", V2, "s_axi_rid_reg    <= r_cur_id;",
                "s_axi_rid_reg    <= {ID_WIDTH{1'b0}};",
     "RID always 0"),

    ("Q01", V2, "assign s_axi_awready = !aw_full;",
                "assign s_axi_awready = 1'b1;",
     "AWREADY ignores a full AW queue"),
    ("Q02", V2, "assign s_axi_arready = !ar_full;",
                "assign s_axi_arready = 1'b1;",
     "ARREADY ignores a full AR queue"),
    ("Q03", V2, "wire w_can_start   = !aw_empty & !b_full;",
                "wire w_can_start   = !aw_empty;",
     "write burst starts with no free B slot"),
    ("Q04", V2, "wire b_pop = s_axi_bvalid & s_axi_bready;",
                "wire b_pop = s_axi_bvalid;",
     "B response retired without BREADY"),
    ("Q05", V2, "wire r_advance = s_axi_rready | (PIPELINE_OUTPUT & !s_axi_rvalid_pipe) | !s_axi_rvalid_reg;",
                "wire r_advance = 1'b1;",
     "R beat advances without RREADY"),
]

# Mutants that cannot be told apart from the original by any test, with the
# reason. They are still run: if one ever dies, the reasoning was wrong.
EQUIVALENT = {}

# Failures that mean "a testbench check fired". FATAL covers the UVM watchdog
# (PH_TIMEOUT); ASRTST is Xcelium reporting a failed assertion.
TOOL_REASONS = {"NOT_FINISHED", "NO_SUMMARY", "NO_LOG", "WALL_TIMEOUT"}
SIM_CHECKS = {"ASRTST"}


def caught_by_testbench(verdict):
    reason = verdict.split(" ", 1)[1] if " " in verdict else verdict
    if reason.startswith("SIM:"):
        return reason[4:] in SIM_CHECKS
    return reason not in TOOL_REASONS


def prepare(mid, fname, old, new):
    """Copy rtl/ into mutants/<mid>/rtl, apply the change, write a filelist.
    Returns an error string, or None."""
    work = os.path.join(OUT, mid)
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(RTL, os.path.join(work, "rtl"))
    if fname is not None:
        path = os.path.join(work, "rtl", fname)
        with open(path) as f:
            text = f.read()
        n = text.count(old)
        if n != 1:
            return "original text found %d times in %s" % (n, fname)
        with open(path, "w") as f:
            f.write(text.replace(old, new))

    # Absolute paths: the build runs inside the mutant's own directory.
    with open(os.path.join(HERE, "files.f")) as f:
        flist = (f.read().replace("../../rtl/", os.path.join(work, "rtl") + "/")
                          .replace("../../", ROOT + "/"))
    with open(os.path.join(work, "files.f"), "w") as f:
        f.write(flist)
    return None


def run(mid, seeds):
    """Build and regress one prepared mutant as v2. Returns (status, detail, secs)."""
    work = os.path.join(OUT, mid)
    t0 = time.time()
    results, build_errors = regress.regress(TEST_ORDER, seeds, ["v2"], os.path.join(work, "run"),
                                            jobs=1, files=os.path.join(work, "files.f"),
                                            stop_on_fail=True, quiet=True)
    secs = int(time.time() - t0)
    if build_errors:
        return "INVALID", "does not build: %s" % build_errors["v2"][:60], secs
    for r in results:
        if not r["ok"]:
            detail = "%s seed %s: %s" % (r["test"].replace("axi4_", ""), r["seed"], r["verdict"][5:])
            return ("KILLED" if caught_by_testbench(r["verdict"]) else "ERROR"), detail, secs
    if mid in EQUIVALENT:
        return "EQUIVALENT", "%d run(s) passed (see note)" % len(results), secs
    return "SURVIVED", "%d run(s) passed" % len(results), secs


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-m", nargs="+", metavar="ID", help="mutant ids to run")
    ap.add_argument("-s", nargs="+", default=["1"], metavar="SEED", help="seeds (default 1)")
    ap.add_argument("-j", type=int, default=4, help="mutants run in parallel (default 4)")
    ap.add_argument("--list", action="store_true", help="print the catalogue and exit")
    ap.add_argument("--check", action="store_true", help="only verify each mutant applies")
    args = ap.parse_args()

    todo = [m for m in MUTANTS if not args.m or m[0] in args.m]
    if args.list:
        for mid, fname, _, _, desc in todo:
            print("%s  %-14s %s" % (mid, fname, desc))
        return 0

    os.makedirs(OUT, exist_ok=True)
    bad = [(m[0], prepare(*m[:4])) for m in todo]
    bad = [(mid, err) for mid, err in bad if err]
    for mid, err in bad:
        print("%s: %s" % (mid, err))
    if args.check or bad:
        if not bad:
            print("all %d mutants apply exactly once" % len(todo))
        return 1 if bad else 0

    print("baseline (no mutation) ...", flush=True)
    prepare("base", None, None, None)
    status, detail, _ = run("base", args.s)
    if status != "SURVIVED":
        print("baseline does not pass (%s) - fix the testbench first" % detail)
        return 1

    t0 = time.time()
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.j) as pool:
        futs = {pool.submit(run, m[0], args.s): m for m in todo}
        for fut in concurrent.futures.as_completed(futs):
            m = futs[fut]
            results[m[0]] = fut.result()
            st, detail, secs = results[m[0]]
            print("  %-3s %-10s %-46s %s" % (m[0], st, m[4][:46], detail), flush=True)

    killed = sum(1 for r in results.values() if r[0] == "KILLED")
    valid = sum(1 for r in results.values() if r[0] in ("KILLED", "SURVIVED"))
    equiv = [mid for mid, r in sorted(results.items()) if r[0] == "EQUIVALENT"]
    errors = [mid for mid, r in sorted(results.items()) if r[0] in ("ERROR", "INVALID")]
    score = 100.0 * killed / valid if valid else 0.0

    with open(os.path.join(OUT, "report.md"), "w") as f:
        f.write("# Mutation campaign — Axi_ram_v2\n\n")
        f.write("Seeds: %s. Killed %d / %d non-equivalent mutants (%.1f%%), %d equivalent.\n\n"
                % (" ".join(args.s), killed, valid, score, len(equiv)))
        f.write("| ID | Injected bug | Result | First failing run |\n|---|---|---|---|\n")
        for mid, _, _, _, desc in todo:
            st, detail, _ = results[mid]
            f.write("| %s | %s | %s | %s |\n" % (mid, desc, st, detail))
        for mid in equiv:
            f.write("\n**%s is equivalent.** %s\n" % (mid, EQUIVALENT[mid]))
        if errors:
            f.write("\n**Not judged (tool error or invalid, rerun):** %s\n" % ", ".join(errors))

    print("\nkilled %d / %d non-equivalent mutants (%.1f%%), %d equivalent, %.0f s - report: mutants/report.md"
          % (killed, valid, score, len(equiv), time.time() - t0))
    if errors:
        print("%d mutant(s) not judged: %s" % (len(errors), " ".join(errors)))
        return 4
    return 0 if killed == valid else 3


if __name__ == "__main__":
    sys.exit(main())

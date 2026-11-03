#!/usr/bin/env python3
"""
AXI4-Full UVM regression - Cadence Xcelium.

    python3 regress.py                          # 9 tests x seeds 1-5 x v1, v2
    python3 regress.py -d v2 -s 1 7 42          # one DUT, chosen seeds
    python3 regress.py -t axi4_cov_test -j 8    # a subset, 8 runs at a time
    python3 regress.py -x C                     # X-propagation build (C or F)
    python3 regress.py -k                       # stop at the first unexpected result

Builds each DUT once (xrun -elaborate), then runs every test/seed from that
snapshot in its own directory, several at a time. Each run is judged by
../judge.py, the same rule the XSim Makefile uses. axi4_wrap_test is an
expected failure (XFAIL) on v1 - the WRAP bug must still reproduce - and a
regular test on v2.

Writes <out>/results.txt (one line per run), <out>/results.xml (JUnit) and
<out>/<dut>/logs/. Exits 0 only if every run had the expected outcome.
"""

import argparse
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from judge import judge  # noqa: E402  (sim/judge.py)

TESTS = ["axi4_base_test", "axi4_directed_test", "axi4_write_test", "axi4_read_test",
         "axi4_rand_test", "axi4_cov_test", "axi4_outstanding_test", "axi4_stress_test",
         "axi4_wrap_test"]
DUTS = ["v1", "v2"]
WALL_LIMIT = 300      # seconds per run - backstop if the UVM timeout never fires


def expected(dut, test):
    """The WRAP test documents v1's bug, so on v1 it has to fail."""
    return "xfail" if (dut, test) == ("v1", "axi4_wrap_test") else "pass"


def build(dut, out, files=None, xprop=None):
    """Compile and elaborate one DUT into <out>/<dut>/xcelium.d.
    Returns (library path, None) or (None, error)."""
    bdir = os.path.join(out, dut)
    shutil.rmtree(bdir, ignore_errors=True)
    os.makedirs(os.path.join(bdir, "logs"))
    log = os.path.join(bdir, "build.log")
    cmd = ["xrun", "-F", os.path.join(HERE, "xrun.args"), "-F", files or os.path.join(HERE, "files.f"),
           "-xmlibdirname", "xcelium.d", "-elaborate", "-l", log]
    if dut == "v2":
        cmd += ["-define", "DUT_V2"]
    if xprop:
        cmd += ["-xprop", xprop]
    subprocess.call(cmd, cwd=bdir, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    try:
        errs = [l.strip() for l in open(log, errors="replace") if re.search(r"\*[EF],", l)]
    except OSError:
        return None, "no build log"
    if errs or not os.path.isdir(os.path.join(bdir, "xcelium.d")):
        return None, errs[0] if errs else "no snapshot"
    return os.path.join(bdir, "xcelium.d"), None


def run_one(lib, dut, test, seed, out):
    """Simulate one test/seed from a built snapshot and judge it."""
    rundir = os.path.join(out, dut, "runs", "%s_%s" % (test, seed))
    log = os.path.join(out, dut, "logs", "%s_%s.log" % (test, seed))
    os.makedirs(rundir, exist_ok=True)
    cmd = ["xrun", "-R", "-xmlibdirname", lib, "-covworkdir", "cov_work",
           "-covtest", "%s_%s" % (test, seed), "-covoverwrite",
           "-svseed", str(seed), "+UVM_TESTNAME=" + test, "-l", log]
    t0 = time.time()
    try:
        subprocess.call(cmd, cwd=rundir, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT,
                        timeout=WALL_LIMIT)
        ok, verdict = judge(log, expected(dut, test))
    except subprocess.TimeoutExpired:
        ok, verdict = False, "FAIL WALL_TIMEOUT"
    res = {"dut": dut, "test": test, "seed": seed, "expect": expected(dut, test),
           "ok": ok, "verdict": verdict, "secs": time.time() - t0, "log": log,
           "cov": "-", "beats": "-", "mism": "-"}
    try:
        text = open(log, errors="replace").read()
        m = re.search(r"^\s+TOTAL\s+([\d.]+)", text, re.M)
        res["cov"] = m.group(1) if m else "-"
        m = re.search(r"(\d+) beats checked, (\d+) byte mismatches", text)
        if m:
            res["beats"], res["mism"] = m.group(1), m.group(2)
    except OSError:
        pass
    return res


def write_junit(results, path):
    suite = ET.Element("testsuite", name="axi4_full_uvm", tests=str(len(results)),
                       failures=str(sum(1 for r in results if not r["ok"])))
    for r in results:
        case = ET.SubElement(suite, "testcase", classname=r["dut"],
                             name="%s.seed%s" % (r["test"], r["seed"]), time="%.1f" % r["secs"])
        if not r["ok"]:
            ET.SubElement(case, "failure", message=r["verdict"]).text = r["log"]
    ET.ElementTree(suite).write(path, encoding="utf-8", xml_declaration=True)


def regress(tests, seeds, duts, out, jobs=4, files=None, xprop=None,
            stop_on_fail=False, quiet=False):
    """Build and run everything. Returns (list of result dicts, build errors)."""
    say = (lambda *a: None) if quiet else (lambda *a: print(*a, flush=True))
    os.makedirs(out, exist_ok=True)
    results, build_errors = [], {}
    for dut in duts:
        say("==================== BUILD %s%s ====================" % (dut, " (xprop %s)" % xprop if xprop else ""))
        lib, err = build(dut, out, files, xprop)
        if err:
            say("BUILD FAILED: %s" % err)
            build_errors[dut] = err
            if stop_on_fail:
                break
            continue
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
            futs = [pool.submit(run_one, lib, dut, t, s, out) for t in tests for s in seeds]
            for fut in concurrent.futures.as_completed(futs):
                r = fut.result()
                results.append(r)
                say("  %-3s %-22s seed %-4s %-5s %-26s cov %-7s beats %-4s mism %s"
                    % (r["dut"], r["test"], r["seed"], r["expect"], r["verdict"],
                       r["cov"], r["beats"], r["mism"]))
                if stop_on_fail and not r["ok"]:
                    for f in futs:
                        f.cancel()
                    break
        if stop_on_fail and any(not r["ok"] for r in results):
            break
    order = {(d, t, str(s)): i for i, (d, t, s) in
             enumerate((d, t, str(s)) for d in duts for t in tests for s in seeds)}
    results.sort(key=lambda r: order.get((r["dut"], r["test"], str(r["seed"])), 0))
    return results, build_errors


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-t", "--tests", nargs="+", default=TESTS, metavar="TEST")
    ap.add_argument("-s", "--seeds", nargs="+", default=["1", "2", "3", "4", "5"], metavar="SEED")
    ap.add_argument("-d", "--duts", nargs="+", default=DUTS, choices=DUTS)
    ap.add_argument("-j", "--jobs", type=int, default=4, help="simulations at a time (default 4)")
    ap.add_argument("-x", "--xprop", choices=("C", "F"), help="X-propagation build")
    ap.add_argument("-o", "--out", default=os.path.join(HERE, "regress"), help="output directory")
    ap.add_argument("-k", "--stop-on-fail", action="store_true")
    ap.add_argument("-q", "--quiet", action="store_true")
    ap.add_argument("--files", help="filelist instead of files.f (used by mutate.py)")
    args = ap.parse_args()

    t0 = time.time()
    out = os.path.abspath(args.out)
    results, build_errors = regress(args.tests, args.seeds, args.duts, out, args.jobs,
                                    args.files, args.xprop, args.stop_on_fail, args.quiet)
    with open(os.path.join(out, "results.txt"), "w") as f:
        for dut, err in build_errors.items():
            f.write("%s BUILD_FAILED %s\n" % (dut, err))
        for r in results:
            f.write("%s %s %s %s %s %s %s %s\n" % (r["dut"], r["test"], r["seed"], r["expect"],
                                                  r["verdict"].replace(" ", "_"),
                                                  r["cov"], r["beats"], r["mism"]))
    write_junit(results, os.path.join(out, "results.xml"))

    ok = sum(1 for r in results if r["ok"])
    if not args.quiet:
        cov = [float(r["cov"]) for r in results if r["test"] == "axi4_cov_test" and r["cov"] != "-"]
        print("==================== %d / %d runs as expected (%.0f s) ===================="
              % (ok, len(results), time.time() - t0))
        if cov:
            print("axi4_cov_test coverage: min %.2f%%  max %.2f%%  over %d runs"
                  % (min(cov), max(cov), len(cov)))
        print("=== REGRESSION %s ===" % ("PASS" if ok == len(results) and not build_errors else "FAIL"))
    return 0 if ok == len(results) and not build_errors else 1


if __name__ == "__main__":
    sys.exit(main())

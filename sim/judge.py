#!/usr/bin/env python3
"""
Pass/fail rule for one simulation log, shared by the XSim Makefile
(sim/Makefile) and the Xcelium scripts (sim/xcelium/regress.py, mutate.py).

    python3 judge.py <log> [--expect pass|xfail]

Prints the verdict and exits 0 if it was the expected outcome, 1 if not.

    PASS           reached END_OF_TEST with no UVM_ERROR, no UVM_FATAL and no
                   simulator error
    XFAIL          (--expect xfail) reached END_OF_TEST and every UVM_ERROR is
                   a scoreboard mismatch - the bug still reproduces
    FAIL <reason>  anything else. The reason is the earliest problem in the
                   log - a UVM_ERROR id, or FATAL:<id> - then SIM:<code>,
                   NOT_FINISHED, NO_SUMMARY, or UNEXPECTED_PASS for an xfail
                   test that passed

END_OF_TEST is printed by axi4_base_test::report_phase. A uvm_fatal skips
report_phase but still prints "UVM_ERROR :    0" in its summary, so the error
count alone is not enough. UVM's own "[TEST_DONE]" message shows up on every
normal run, so it cannot serve as the marker.
"""

import argparse
import re
import sys

# Xcelium on the lab host cannot link the DPI export stub (no glibc-devel) and
# reports *E,IMPDLL on every run. It does not affect batch results.
KNOWN_SIM_ERRORS = {"IMPDLL"}

MARKER = "[TEST] END_OF_TEST"
UVM_MSG = re.compile(r"^UVM_(ERROR|FATAL) [^\[]*\[([^\]]+)\]")   # ... [<ID>] <message>
SUMMARY = re.compile(r"^UVM_(ERROR|FATAL) :\s+(\d+)\s*$")
SIM_MSG = re.compile(r"\*[EF],([A-Z0-9_]+)")                     # Xcelium *E / *F


def judge(log, expect="pass"):
    """Return (as_expected, verdict) for one simulation log."""
    try:
        with open(log, errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return False, "FAIL NO_LOG"

    finished = False
    first = None                    # earliest UVM_ERROR / UVM_FATAL in the log
    errors, fatals, counts, sim = [], [], {}, []
    for line in lines:
        if MARKER in line:
            finished = True
        m = UVM_MSG.match(line)
        if m:
            kind, mid = m.group(1), m.group(2)
            (errors if kind == "ERROR" else fatals).append(mid)
            if first is None:
                first = mid if kind == "ERROR" else "FATAL:" + mid
            continue
        m = SUMMARY.match(line)
        if m:
            counts[m.group(1)] = int(m.group(2))
            continue
        sim += [c for c in SIM_MSG.findall(line) if c not in KNOWN_SIM_ERRORS]

    if fatals or counts.get("FATAL", 0):
        # A watchdog timeout is often the consequence of an earlier error;
        # name the error. For an xfail test any fatal is the problem itself.
        if expect == "xfail" or first is None:
            return False, "FAIL FATAL:" + (fatals[0] if fatals else "?")
        return False, "FAIL " + first
    if not finished:
        return False, "FAIL NOT_FINISHED"
    if "FATAL" not in counts:
        return False, "FAIL NO_SUMMARY"

    # Xcelium also reports every failed assertion as *E,ASRTST next to its
    # [AXI_SVA] UVM_ERROR; UVM ids come first so the reason names what failed.
    if expect == "xfail":
        other = [e for e in errors if e != "SB_MISMATCH"]
        if other:
            return False, "FAIL " + other[0]
        if sim:
            return False, "FAIL SIM:" + sim[0]
        if not errors:
            return False, "FAIL UNEXPECTED_PASS"
        return True, "XFAIL"
    if errors:
        return False, "FAIL " + errors[0]
    if sim:
        return False, "FAIL SIM:" + sim[0]
    if counts.get("ERROR", 0):
        return False, "FAIL UVM_ERROR"
    return True, "PASS"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log")
    ap.add_argument("--expect", choices=("pass", "xfail"), default="pass")
    args = ap.parse_args()
    ok, verdict = judge(args.log, args.expect)
    print(verdict)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

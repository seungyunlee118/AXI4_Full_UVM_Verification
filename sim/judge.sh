# =============================================================
# Pass/fail rule for one simulation log, shared by the XSim Makefile
# (sim/Makefile) and the Xcelium regression (sim/xcelium/regress.sh).
#
#   judge <log> [pass|xfail]   prints a verdict, returns 0 if it was the
#                              expected outcome
#
#   PASS           reached END_OF_TEST with no UVM_ERROR, no UVM_FATAL and
#                  no simulator error
#   XFAIL          (xfail) reached END_OF_TEST and every UVM_ERROR is a
#                  scoreboard mismatch - the bug still reproduces
#   FAIL <reason>  anything else: NOT_FINISHED, FATAL, NO_SUMMARY,
#                  SIM:<code>, the first UVM_ERROR id, or UNEXPECTED_PASS
#                  for an xfail test that passed
#
# END_OF_TEST is printed by axi4_base_test::report_phase. A uvm_fatal skips
# report_phase but still prints "UVM_ERROR :    0" in its summary, so the
# error count alone is not enough. UVM's own "[TEST_DONE]" message shows up
# on every normal run, so it cannot serve as the marker.
# =============================================================

# Xcelium on the lab host cannot link the DPI export stub (no glibc-devel)
# and reports *E,IMPDLL on every run. It does not affect batch results.
KNOWN_SIM_ERRORS="IMPDLL"

judge() {
    _log=$1; _expect=${2:-pass}

    if ! grep -qF "[TEST] END_OF_TEST" "$_log"; then
        if grep -qE "^UVM_FATAL :[[:space:]]+[1-9]" "$_log"; then echo "FAIL FATAL"
        else echo "FAIL NOT_FINISHED"; fi
        return 1
    fi
    grep -qE "^UVM_FATAL :" "$_log"                || { echo "FAIL NO_SUMMARY"; return 1; }
    grep -qE "^UVM_FATAL :[[:space:]]+0$" "$_log"  || { echo "FAIL FATAL"; return 1; }

    # UVM_ERROR <file(line)> @ <time>: <path> [<ID>] <message>
    _ids=$(sed -nE 's/^UVM_ERROR [^[]*\[([^]]+)\].*/\1/p' "$_log")
    # Simulator *E / *F messages (Xcelium format). Xcelium also reports every
    # failed assertion as *E,ASRTST, next to its [AXI_SVA] UVM_ERROR; the UVM
    # ids are checked first so the reason names what failed.
    _sim=$(grep -oE '\*[EF],[A-Z0-9_]+' "$_log" | sed 's/^\*[EF],//' \
           | grep -vxE "$(echo $KNOWN_SIM_ERRORS | tr ' ' '|')" | head -1)

    if [ "$_expect" = xfail ]; then
        _other=$(echo "$_ids" | grep -vx SB_MISMATCH | grep -v '^$' | head -1)
        [ -n "$_other" ] && { echo "FAIL $_other"; return 1; }
        [ -n "$_sim" ]   && { echo "FAIL SIM:$_sim"; return 1; }
        echo "$_ids" | grep -qx SB_MISMATCH || { echo "FAIL UNEXPECTED_PASS"; return 1; }
        echo "XFAIL"; return 0
    fi
    _first=$(echo "$_ids" | grep -v '^$' | head -1)
    [ -n "$_first" ] && { echo "FAIL $_first"; return 1; }
    [ -n "$_sim" ]   && { echo "FAIL SIM:$_sim"; return 1; }
    grep -qE "^UVM_ERROR :[[:space:]]+0$" "$_log" || { echo "FAIL UVM_ERROR"; return 1; }
    echo "PASS"; return 0
}

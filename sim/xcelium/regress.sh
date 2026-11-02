#!/usr/bin/env bash
# =============================================================
# AXI4-Full UVM regression — Cadence Xcelium
#
#   ./regress.sh                      # 8 tests x seeds "1 2 3 4 5" x v1, v2
#   ./regress.sh -d v2                # one DUT only
#   ./regress.sh -s "1 7 42"          # other seeds
#   ./regress.sh -t "axi4_cov_test"   # a subset of tests
#   ./regress.sh -x C                 # X-propagation build (-xprop C or F)
#
# Builds each DUT once into <out>/<dut>/xcelium.d, then runs every test/seed
# from that snapshot in its own directory. Verdicts come from ../judge.sh,
# the same rule the XSim Makefile uses. axi4_wrap_test is an expected
# failure (XFAIL) on v1 and a regular test on v2.
#
# Results: <out>/results.txt, one line per run:
#   <dut> <test> <seed> <expect> <verdict> <coverage%|-> <beats> <mismatches>
# =============================================================
set -u
cd "$(dirname "$0")"
source ./xcelium_env.sh || exit 1
source ../judge.sh

TESTS="axi4_base_test axi4_directed_test axi4_write_test axi4_read_test
       axi4_rand_test axi4_cov_test axi4_outstanding_test axi4_wrap_test"
SEEDS="1 2 3 4 5"
DUTS="v1 v2"
XPROP=""
OUT="regress"
WALL_LIMIT=300        # seconds per run - backstop if the UVM timeout never fires

usage() { sed -n '3,18p' "$0"; exit 1; }
while getopts "t:s:d:x:o:h" opt; do
    case $opt in
        t) TESTS=$OPTARG ;;
        s) SEEDS=$OPTARG ;;
        d) DUTS=$OPTARG ;;
        x) XPROP=$OPTARG ;;
        o) OUT=$OPTARG ;;
        *) usage ;;
    esac
done

for dut in $DUTS; do
    case $dut in v1|v2) ;; *) echo "unknown DUT '$dut' (use v1 / v2)"; exit 1 ;; esac
done

HERE=$(pwd)
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
: > "$OUT/results.txt"
fail=0

for dut in $DUTS; do
    def=""; [ "$dut" = v2 ] && def="-define DUT_V2"
    xp="";  [ -n "$XPROP" ] && xp="-xprop $XPROP"
    rm -rf "${OUT:?}/$dut"; mkdir -p "$OUT/$dut/logs"
    echo "==================== BUILD $dut${XPROP:+ (xprop $XPROP)} ===================="
    if ! (cd "$OUT/$dut" && xrun -F "$HERE/xrun.args" -F "$HERE/files.f" $def $xp \
              -xmlibdirname xcelium.d -elaborate -l build.log >/dev/null 2>&1) \
       || grep -qE "\*[EF]," "$OUT/$dut/build.log"; then
        echo "BUILD FAILED - see $OUT/$dut/build.log"
        grep -E "\*[EF]," "$OUT/$dut/build.log" | head -5
        fail=1; continue
    fi

    for t in $TESTS; do
        expect=pass
        [ "$dut" = v1 ] && [ "$t" = axi4_wrap_test ] && expect=xfail
        for s in $SEEDS; do
            log="$OUT/$dut/logs/${t}_${s}.log"; dir="$OUT/$dut/runs/${t}_${s}"
            mkdir -p "$dir"
            (cd "$dir" && timeout "$WALL_LIMIT" xrun -R -xmlibdirname "$OUT/$dut/xcelium.d" \
                -covworkdir cov_work -covtest "${t}_${s}" -covoverwrite \
                -svseed "$s" +UVM_TESTNAME="$t" -l "$log" >/dev/null 2>&1)
            if [ $? -eq 124 ]; then verdict="FAIL WALL_TIMEOUT"; fail=1
            else verdict=$(judge "$log" "$expect") || fail=1; fi
            cov=$(grep -E "^ +TOTAL" "$log" | grep -oE "[0-9.]+" | head -1)
            beats=$(grep -oE "[0-9]+ beats checked" "$log" | grep -oE "^[0-9]+")
            mm=$(grep -oE "[0-9]+ byte mismatches" "$log" | grep -oE "^[0-9]+")
            line="$dut $t $s $expect $verdict ${cov:--} ${beats:--} ${mm:--}"
            echo "$line" >> "$OUT/results.txt"
            printf "  %-3s %-22s seed %-4s %-5s %-24s cov %-7s beats %-4s mism %s\n" \
                   "$dut" "$t" "$s" "$expect" "$verdict" "${cov:--}" "${beats:--}" "${mm:--}"
        done
    done
done

total=$(wc -l < "$OUT/results.txt")
ok=$(grep -cE " (PASS|XFAIL) " "$OUT/results.txt")
echo "==================== $ok / $total runs as expected ===================="
if [ $fail -eq 0 ]; then echo "=== REGRESSION PASS ==="; else echo "=== REGRESSION FAIL (logs in $OUT/<dut>/logs/) ==="; exit 1; fi

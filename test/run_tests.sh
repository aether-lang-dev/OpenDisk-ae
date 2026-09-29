#!/usr/bin/env bash
# run_tests.sh — OpenDisk's unit suites (std.spec): the model, scanner,
# chart, search, Collector, protected paths, devices and view rules. No
# window, no driver — these run on any box, display or not.
#
#   test/run_tests.sh            # every suite
#   test/run_tests.sh chart tree # just these
#
# `ae run` (not aetherc + gcc) because od_stat / od_text ship their C via
# @source, which `ae` compiles in. Exit status: 0 only if every suite passed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$(cd "$HERE/../opendisk" && pwd)"
LIB="$APP"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) command -v cygpath >/dev/null 2>&1 && LIB="$(cygpath -m "$APP")" ;;
esac

SUITES=(formatters tree search chart protected collector scanner rescan devices view)
[ $# -gt 0 ] && SUITES=("$@")

cd "$HERE"
fail=0
for s in "${SUITES[@]}"; do
    log="$(mktemp)"
    if AETHER_LIB_DIR="$LIB" ae run "test_${s}.ae" > "$log" 2>&1; then
        pass="$(grep -a -o '[0-9]* passing' "$log" | tail -1)"
        echo "  OK   opendisk ${s} (${pass:-no count})"
    else
        echo "  FAIL opendisk ${s}"
        grep -a -v '^warning\|-->\|^ *[0-9]* |\|^ *|\|help:' "$log" | tail -25 | sed 's/^/       /'
        fail=$((fail + 1))
    fi
    rm -f "$log"
done
exit $fail

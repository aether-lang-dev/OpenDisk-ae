#!/usr/bin/env bash
# ci.sh — OpenDisk's whole pipeline: build, unit suites, driver specs.
#
#   ./ci.sh
#
# Needs `ae` and `aeb` on PATH and aether-ui at ./aether-ui (see README).
# On Linux with no $DISPLAY the driver specs run under xvfb-run when it is
# installed; without it they are skipped (the unit suites still run).
# Exit status: 0 only if every step passed.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
fail=0

echo "=== build (aeb opendisk/.build.ae, driver enabled) ==="
if [ ! -d aether-ui/ui ]; then
    echo "  FAIL: ./aether-ui does not reach an aether-ui checkout"; exit 1
fi
if AETHER_UI_WITH_DRIVER=1 aeb opendisk/.build.ae > target.build.log 2>&1 \
        && [ -x target/build/opendisk/bin/opendisk ]; then
    echo "  OK   opendisk built"
else
    echo "  FAIL build"; grep -a -E "error|FAILED" target.build.log | head -20 | sed 's/^/       /'
    exit 1
fi
rm -f target.build.log

echo "=== unit suites (test/) ==="
test/run_tests.sh || fail=$((fail + $?))

echo "=== od_watch seam (test/test_watch.sh) ==="
test/test_watch.sh || fail=$((fail + $?))

echo "=== od_native seam (test/test_native.sh) ==="
test/test_native.sh || fail=$((fail + $?))

echo "=== AetherUIDriver specs (spec/) ==="
od_xvfb=0
if [ "$(uname -s)" = "Linux" ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    if command -v xvfb-run > /dev/null 2>&1; then
        od_xvfb=1; export GSK_RENDERER=cairo
    else
        echo "  SKIP: no display and no xvfb-run"
        od_xvfb=skip
    fi
fi
if [ "$od_xvfb" != "skip" ]; then
    OD_XVFB=$od_xvfb spec/run.sh || fail=$((fail + $?))
fi

echo
if [ "$fail" -eq 0 ]; then echo "=== all green ==="; else echo "=== $fail failure(s) ==="; fi
exit $fail

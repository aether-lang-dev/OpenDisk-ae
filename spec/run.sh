#!/usr/bin/env bash
# run.sh — run OpenDisk's AetherUIDriver specs against a fresh app and a
# fresh fixture each. Needs a driver-enabled build:
#   AETHER_UI_WITH_DRIVER=1 aeb opendisk/.build.ae
#
#   spec/run.sh                 # every spec
#   spec/run.sh chart search    # just these
#
# The generic driver client (uidriver.ae) is aether-ui's own, reached
# through the repo's aether-ui symlink; od_driver.ae sits beside the specs.
#
# OD_XVFB=1 wraps each launch in xvfb-run (ci.sh sets it on a display-less
# Linux box, matching its launch_xvfb). OD_BIN overrides the binary.
#
# Exit status: the number of specs that failed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC_DIR="$ROOT/spec"
BIN="${OD_BIN:-$ROOT/target/build/opendisk/bin/opendisk}"
LIBT="$ROOT/aether-ui/tests/lib"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) command -v cygpath >/dev/null 2>&1 && LIBT="$(cygpath -m "$LIBT")" ;;
esac
PORT=9222
SPECS=(scan_list chart chart_drag search collector picker incremental_rescan)
[ $# -gt 0 ] && SPECS=("$@")
export AETHER_UI_NO_ANIMATION=1

# make_fixture <dir>: the tree spec/od_driver.ae describes.
make_fixture() {
    local f="$1"
    mkdir -p "$f/Movies" "$f/Documents/drafts" "$f/Music"
    head -c 2000000 /dev/urandom > "$f/Movies/movie.mov"
    head -c 50000   /dev/urandom > "$f/Documents/report.pdf"
    head -c 30000   /dev/urandom > "$f/Documents/drafts/report-old.pdf"
    head -c 400000  /dev/urandom > "$f/Music/song.flac"
    head -c 10      /dev/urandom > "$f/tiny.txt"
}

fail=0
for s in "${SPECS[@]}"; do
    work="$(mktemp -d "${TMPDIR:-/tmp}/od-spec-XXXXXX")"
    fix="$work/odfix"
    mkdir -p "$fix" "$work/config"
    make_fixture "$fix"
    if curl -sf -o /dev/null "http://127.0.0.1:$PORT/widgets" 2>/dev/null; then
        echo "  FAIL opendisk_$s — port $PORT already answering (stray app?)"
        fail=$((fail + 1)); rm -rf "$work"; continue
    fi
    # The picker spec starts on the device screen with the fixture as a
    # remembered folder; the others open straight into the fixture.
    arg="$fix"
    if [ "$s" = "picker" ]; then
        arg=""
        printf '%s\n' "$fix" > "$work/config/recent.txt"
    fi
    launch=()
    if [ "${OD_XVFB:-0}" = "1" ]; then launch=(xvfb-run -a -s "-screen 0 3200x2000x24"); fi
    OPENDISK_CONFIG_DIR="$work/config" AETHER_UI_TEST_PORT=$PORT \
        ${launch[@]+"${launch[@]}"} "$BIN" $arg > "$work/app.log" 2>&1 &
    pid=$!
    up=0
    for _ in $(seq 1 50); do
        curl -sf -o /dev/null "http://127.0.0.1:$PORT/widgets" && { up=1; break; }
        sleep 0.2
    done
    if [ "$up" -ne 1 ]; then
        echo "  FAIL opendisk_$s — app never answered"; tail -5 "$work/app.log"
        kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
        fail=$((fail + 1)); rm -rf "$work"; continue
    fi
    out="$(cd "$SPEC_DIR" && OD_FIXTURE="$fix" AETHER_LIB_DIR="$LIBT" ae run "spec_${s}.ae" 2>&1)"
    rc=$?
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    pass="$(printf '%s\n' "$out" | grep -a -o '[0-9]* passing' | tail -1)"
    if [ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -aq 'failing'; then
        echo "  OK   opendisk_$s (${pass:-?})"
    else
        echo "  FAIL opendisk_$s (${pass:-0 passing})"
        printf '%s\n' "$out" | grep -a -v '^warning\|-->\|^ *[0-9]* |\|^ *|\|help:' | tail -30 | sed 's/^/       /'
        fail=$((fail + 1))
    fi
    rm -rf "$work"
done
exit $fail

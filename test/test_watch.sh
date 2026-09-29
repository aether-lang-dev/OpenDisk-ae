#!/usr/bin/env bash
# test_watch.sh — exercises od_watch's two implementations directly (not
# through the app), the same way opendisk/.build.ae picks between them:
# watch_none everywhere, watch_mac (backed by macae's mac.fsevents) on
# macOS only. Outside a std.spec suite because each side needs a DIFFERENT
# AETHER_LIB_DIR (od_app.ae's own tests use a single fixed one, see
# run_tests.sh's header) and the macOS side needs a real filesystem event to
# round-trip, not just a pure function call.
#
#   test/test_watch.sh
#
# Exit status: 0 only if every applicable case passed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$(cd "$HERE/../opendisk" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
fail=0

run_case() {
    label="$1"; libdir="$2"; body="$3"
    work="$(mktemp -d)"
    cat > "$work/t.ae" <<EOF
import od_watch (watch_available, watch_start, watch_stop, watch_poll)
import std.strarr
import std.string
import std.fs
extern exit(code: int)
main() {
${body}
}
EOF
    log="$(mktemp)"
    if AETHER_LIB_DIR="$libdir" ae run "$work/t.ae" > "$log" 2>&1; then
        echo "  OK   $label"
    else
        echo "  FAIL $label"
        sed -n '1,25p' "$log" | sed 's/^/       /'
        fail=$((fail + 1))
    fi
    rm -f "$log"
    rm -rf "$work"
}

echo "=== od_watch: the portable stub (watch_none) ==="
run_case "watch_available() is 0, start/poll are safe no-ops" \
    "$APP/watch_none" \
    'if watch_available() != 0 { println("FAIL: expected unavailable"); exit(1) }
    w = watch_start("/tmp")
    if w != null { println("FAIL: expected null watch"); exit(1) }
    paths, give_up = watch_poll(w)
    if strarr.size(paths) != 0 { println("FAIL: expected no paths"); exit(1) }
    if give_up != 0 { println("FAIL: expected give_up=0"); exit(1) }
    println("stub OK")'

if [ "$(uname -s)" != "Darwin" ]; then
    echo "=== od_watch: the macOS side (watch_mac) — skipped, not on macOS ==="
    exit $fail
fi

echo "=== od_watch: the macOS side (watch_mac), backed by macae ==="
watch_dir="$(mktemp -d)"
run_case "reports the new file's real path (macae runs FSEvents in FILE_EVENTS mode, not directory-level)" \
    "$APP/watch_mac:$ROOT/macae" \
    "if watch_available() == 0 { println(\"FAIL: expected available on macOS\"); exit(1) }
    w = watch_start(\"$watch_dir\")
    if w == null { println(\"FAIL: expected a watch handle\"); exit(1) }
    // Give the watch a moment to actually open before the change it
    // should see, then write the file from inside the same program —
    // no cross-process race to get right. FSEvents resolves symlinks in
    // what it reports (e.g. /tmp -> /private/tmp), so compare against the
    // DIRECTORY's realpath as a prefix — the reported path is the file
    // itself, not its containing directory (macae's fsevents.c passes
    // kFSEventStreamCreateFlagFileEvents, confirmed by inspection).
    sleep(300)
    _err = fs.write(\"$watch_dir/new_file.txt\", \"hello\")
    want_dir, _k, _e = fs.realpath(\"$watch_dir\")
    seen = 0
    tries = 0
    while tries < 40 {
        paths, give_up = watch_poll(w)
        if give_up == 1 { println(\"FAIL: unexpected give_up\"); exit(1) }
        j = 0
        while j < strarr.size(paths) {
            if string.starts_with(strarr.get(paths, j), want_dir) == 1 { seen = 1; j = strarr.size(paths) }
            j = j + 1
        }
        if seen == 1 { tries = 40 } else {
            sleep(100)
            tries = tries + 1
        }
    }
    if seen == 0 { println(\"FAIL: watched directory never reported changed\"); exit(1) }
    watch_stop(w)
    println(\"watch_mac OK\")"
rm -rf "$watch_dir"

exit $fail

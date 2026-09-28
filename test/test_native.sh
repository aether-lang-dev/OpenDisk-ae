#!/usr/bin/env bash
# test_native.sh — exercises od_native's two implementations directly (not
# through the app): the portable stub everywhere, and the five macae-backed
# capabilities on macOS. Outside a std.spec suite for the same reason as
# test_watch.sh — each side needs a different AETHER_LIB_DIR, and several of
# the macOS calls (workspace's open/reveal) would otherwise pop real UI, so
# MACAE_HEADLESS=1 keeps them to their refusal path here, same as macae's
# own test suite does.
#
#   test/test_native.sh
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
import od_native (
    native_volume_available, native_capacity,
    native_quicklook_available, native_quicklook_preview,
    native_trash_available, native_trash_item,
    native_workspace_available, native_reveal, native_open,
    native_fda_available, native_fda_probe, native_fda_open_settings,
    FDA_GRANTED, FDA_DENIED, FDA_UNDETERMINED
)
import std.string
import std.fs
extern exit(code: int)
main() {
${body}
}
EOF
    log="$(mktemp)"
    if AETHER_LIB_DIR="$libdir" MACAE_HEADLESS=1 ae run "$work/t.ae" > "$log" 2>&1; then
        echo "  OK   $label"
    else
        echo "  FAIL $label"
        sed -n '1,25p' "$log" | sed 's/^/       /'
        fail=$((fail + 1))
    fi
    rm -f "$log"
    rm -rf "$work"
}

echo "=== od_native: the portable stub (native_none) ==="
run_case "every *_available() is 0, and every call degrades safely" \
    "$APP/native_none" \
    'if native_volume_available() != 0 { println("FAIL: volume available"); exit(1) }
    _t, _a, ok = native_capacity("/")
    if ok != 0 { println("FAIL: capacity ok"); exit(1) }
    if native_quicklook_available() != 0 { println("FAIL: quicklook available"); exit(1) }
    if string.length(native_quicklook_preview("/tmp")) == 0 { println("FAIL: preview should error"); exit(1) }
    if native_trash_available() != 0 { println("FAIL: trash available"); exit(1) }
    _w, terr = native_trash_item("/tmp/nope")
    if string.length(terr) == 0 { println("FAIL: trash should error"); exit(1) }
    if native_workspace_available() != 0 { println("FAIL: workspace available"); exit(1) }
    if native_reveal("/tmp") != 0 { println("FAIL: reveal should refuse"); exit(1) }
    if native_open("/tmp") != 0 { println("FAIL: open should refuse"); exit(1) }
    if native_fda_available() != 0 { println("FAIL: fda available"); exit(1) }
    if native_fda_probe() != FDA_UNDETERMINED { println("FAIL: fda probe"); exit(1) }
    println("stub OK")'

if [ "$(uname -s)" != "Darwin" ]; then
    echo "=== od_native: the macOS side (native_mac) — skipped, not on macOS ==="
    exit $fail
fi

echo "=== od_native: the macOS side (native_mac), backed by macae ==="
run_case "mac.volume: real capacity numbers, roughly sane against statvfs" \
    "$APP/native_mac:$ROOT/macae" \
    'if native_volume_available() != 1 { println("FAIL: expected available"); exit(1) }
    total, avail, ok = native_capacity("/")
    if ok != 1 { println("FAIL: expected ok=1 for /"); exit(1) }
    if total <= 0 { println("FAIL: total should be positive, got ${total}"); exit(1) }
    if avail < 0 { println("FAIL: available should be non-negative, got ${avail}"); exit(1) }
    if avail > total { println("FAIL: available (${avail}) should not exceed total (${total})"); exit(1) }
    stat_total, _f, stat_avail, _e = fs.statvfs("/")
    // mac.volume includes purgeable space, so it should read >= raw statvfs free space.
    if avail < stat_avail { println("FAIL: Finder-style available (${avail}) should be >= statvfs avail (${stat_avail})"); exit(1) }
    println("volume OK: total=${total} available=${avail} (statvfs avail=${stat_avail})")'

run_case "mac.quicklook: unavailable outside a real app, so the caller falls back" \
    "$APP/native_mac:$ROOT/macae" \
    'if native_quicklook_available() != 0 { println("FAIL: expected unavailable with no NSApplication"); exit(1) }
    println("quicklook OK (correctly unavailable here)")'

trash_fixture_dir="$(mktemp -d)"
trash_fixture="$trash_fixture_dir/tiny.txt"
echo "x" > "$trash_fixture"
run_case "mac.trash: moves a real temp file, Put-Back path returned" \
    "$APP/native_mac:$ROOT/macae" \
    "p = \"$trash_fixture\"
    if native_trash_available() != 1 { println(\"FAIL: expected available\"); exit(1) }
    where, err = native_trash_item(p)
    if string.length(err) > 0 { println(\"FAIL: \${err}\"); exit(1) }
    if fs.exists(p) == 1 { println(\"FAIL: original path should be gone\"); exit(1) }
    if fs.exists(where) == 0 { println(\"FAIL: trashed file should exist at \${where}\"); exit(1) }
    _rerr = fs.remove_tree(where)
    println(\"trash OK: moved to \${where}\")"

run_case "mac.workspace: refused under MACAE_HEADLESS, queries still work" \
    "$APP/native_mac:$ROOT/macae" \
    'if native_workspace_available() != 1 { println("FAIL: expected available"); exit(1) }
    if native_reveal("/tmp") != 0 { println("FAIL: reveal should be refused when headless"); exit(1) }
    if native_open("/tmp") != 0 { println("FAIL: open should be refused when headless"); exit(1) }
    println("workspace OK (correctly refused while headless)")'

run_case "mac.fda: probe returns one of the three documented states" \
    "$APP/native_mac:$ROOT/macae" \
    'if native_fda_available() != 1 { println("FAIL: expected available"); exit(1) }
    p = native_fda_probe()
    if p != FDA_GRANTED { if p != FDA_DENIED { if p != FDA_UNDETERMINED {
        println("FAIL: unexpected probe result ${p}")
        exit(1)
    } } }
    println("fda OK: probe=${p}")'

exit $fail

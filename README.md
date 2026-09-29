# OpenDisk for Aether UI

A port of [OpenDisk](https://github.com/137137137/OpenDisk), a macOS SwiftUI
disk-usage app, to Aether UI. One codebase runs on Linux (GTK4), macOS (AppKit)
and Windows (Win32). Like the original, it is MIT-licensed; the notice is in
`opendisk/opendisk.ae` and `LICENSE`.

It scans a disk or folder and shows where the space went. You can browse the
folders from largest to smallest, read the rings chart, search every scanned
name, and gather files in the Collector to delete them together.

## What you need

This repo builds against three sibling checkouts:

```
scm/
  aether/        the Aether toolchain; `ae` must be on PATH, e.g. aether/build
  aeb/           the build runner; `aeb` on PATH
  aether-ui/     the UI toolkit — reached through this repo's `aether-ui` symlink
  macae/         macOS-only natives — reached through this repo's `macae` symlink
                 (optional: needed only when building on macOS; see below)
  OpenDisk-ae/   this repo
```

`aether-ui`, `build_support` and `macae` at the repo root are **relative
symlinks** into `../aether-ui` and `../macae`. Point them at another checkout
to build against it. The build takes aether-ui's `ui` and `vg` modules and
its per-OS backend link setup from there, so nothing here duplicates them.
(On Windows, clone with `core.symlinks=true`.)

`opendisk/.build.ae` only follows the `macae` symlink on a macOS build
(`std.os.platform() == "darwin"`); a Linux or Windows build never touches it,
so it doesn't need to exist there. See [macae](https://github.com/aether-lang-dev/macae)
if you don't have a sibling checkout yet — `mac.fsevents`, `mac.volume`,
`mac.quicklook`, `mac.trash`, `mac.workspace` and `mac.fda` are used today.

The port needs Aether ≥ 0.717.0, which carries three fixes it relies on (a
trailing block on a struct-field assignment; `_` bound inside a loop;
`fs.hard_link`, used by the tests).

## Build, run, test

```sh
aeb opendisk/.build.ae                       # → target/build/opendisk/bin/opendisk
./target/build/opendisk/bin/opendisk         # opens on the device screen
./target/build/opendisk/bin/opendisk ~/Downloads   # opens straight into a scan

test/run_tests.sh                            # unit suites (std.spec): no window needed
test/test_watch.sh                           # od_watch: stub everywhere, real FSEvents round-trip on macOS
test/test_native.sh                          # od_native: stub everywhere, all 5 macae calls exercised for real on macOS
AETHER_UI_WITH_DRIVER=1 aeb opendisk/.build.ae
spec/run.sh                                  # AetherUIDriver specs, one fresh app each
./ci.sh                                      # all five, in that order
```

In a sandbox or CI job whose `$HOME` is read-only, set `AETHER_CACHE_DIR` to a
writable directory: `ae run` caches compiled binaries there.

## Layout

| Path | What |
|---|---|
| `opendisk/` | the app: `opendisk.ae` builds the window, `od_*.ae` the rest, `od_stat.c` / `od_text.c` the per-OS C |
| `opendisk/watch_none/`, `opendisk/watch_mac/` | the two `od_watch` implementations; `.build.ae` puts exactly one on the module path per OS |
| `opendisk/native_none/`, `opendisk/native_mac/` | the two `od_native` implementations (volume/quicklook/trash/workspace/fda), same one-of-two-on-the-path rule |
| `test/` | unit suites, one per module area, `std.spec` — including `test_rescan.ae` (od_scan's incremental-merge logic, pure, no macae dependency) — plus `test_watch.sh` and `test_native.sh`, outside `std.spec` (see their headers) |
| `spec/` | AetherUIDriver specs, with `od_driver.ae` as their vocabulary and `run.sh` running them |

## How it maps onto OpenDisk

| OpenDisk (Swift) | Here | Tested by |
|---|---|---|
| `FileTree`, roll-up, hard-link dedup | `opendisk/od_tree.ae` | `test/test_tree.ae` |
| `TraversalScanner` (allocated sizes, same device, no symlinks) | `opendisk/od_scan.ae`, `od_stat.c` | `test/test_scanner.ae` |
| FSEvents incremental merge (macOS scan cache not ported — see "Where it differs") | `opendisk/od_watch.ae` seam (`watch_mac`/`watch_none`), `od_scan.ae`'s `merge_changed_paths` | `test/test_watch.sh`, `test/test_rescan.ae`, `spec/spec_incremental_rescan.ae` |
| Finder capacity, Quick Look, Trash, NSWorkspace, Full Disk Access probe | `opendisk/od_native.ae` seam, `native_mac`/`native_none` | `test/test_native.sh` |
| `ChartItem`, `RingsChartLayout`, `ChartPalette` | `opendisk/od_chart.ae` | `test/test_chart.ae` |
| `RingsChartView`, `ChartHoverTip` | `opendisk/od_draw.ae` | `spec/spec_chart.ae`, `spec/spec_chart_drag.ae` |
| `SearchIndex` | `od_search.ae`, `od_text.c` | `test/test_search.ae`, `spec/spec_search.ae` |
| `Collector` | `od_collector.ae` | `test/test_collector.ae`, `spec/spec_collector.ae` |
| `ProtectedPaths` | `od_protected.ae` (macOS, plus Linux and Windows rules) | `test/test_protected.ae` |
| `DeviceMonitor`, `DevicePickerView` | `od_devices.ae`, `od_recent.ae` | `test/test_devices.ae`, `spec/spec_picker.ae` |
| `DiskAnalyzer` view rules, `Formatters` | `od_view.ae`, `od_fmt.ae` | `test/test_view.ae`, `test/test_formatters.ae` |
| `DiskAnalysisView` and its bars | `od_app.ae`, `opendisk.ae` | `spec/spec_scan_list.ae` |

The constants and strings are OpenDisk's own:
- chart constants: 5 rings deep, 0.15% minimum share, 0.03 rad minimum angle, the six-hue palette
- list rules: at most 100 items below the root, nothing under 1 KB once the scan is done
- ByteCountFormatter's decimal units ("Zero KB", "1.5 MB", "1.07 GB")
- the reason strings for protected paths
- the Collector's undo depth (50), and deletion that is permanent (OpenDisk has no Trash step)

## Where it differs, and why

- **FSEvents incremental rescan, on macOS only.** A macOS build watches the
  scanned root (via [macae](https://github.com/aether-lang-dev/macae)'s
  `mac.fsevents`, which runs FSEvents in its fine-grained FILE_EVENTS mode)
  and, when something changes underneath it, rescans and merges in just the
  affected directories — `od_scan.ae`'s `merge_changed_paths` walks up from
  each changed path to the nearest directory the tree already has and swaps
  in a fresh subtree there via `od_tree.ae`'s `remove_child`/`node_add`
  (`Node.detached` and the search index's own staleness check are what let
  this be safe — both already existed for exactly this). Debounced to at
  most once every two seconds; a dropped/wrapped FSEvents batch (rare) falls
  back to a full rescan for that cycle instead of trusting partial data. Not
  carried across merges: whole-tree hard-link dedup (each rescanned
  directory starts its own dedup set — see `od_scan.ae`'s own note) and
  OpenDisk's macOS scan cache. `opendisk/od_watch.ae` is the seam
  (`watch_mac`/`watch_none`); Linux and Windows builds never link `macae` at
  all (gated in `opendisk/.build.ae` by `std.os.platform()`) and fall back to
  manual-Rescan-only, unchanged from before.
- **The disk capacity bar matches Finder's number on macOS**, purgeable space
  included, via macae's `mac.volume` (`native_capacity` in `od_native.ae`).
  Elsewhere it's `fs.statvfs`'s raw free-block count, as before. The
  "Purgeable Space" *row in the folder list* is a separate, still
  cross-platform thing (OpenDisk-ae's own list of known cache folders,
  `od_view.ae`) — unrelated to and not replaced by this.
- **Quick Look, on macOS, is real Quick Look** (the Space-bar preview panel,
  via `mac.quicklook`) — a new context menu item next to *Open*, on a row
  and on the chart. Elsewhere "Quick Look" still falls back to opening the
  file in its default app, the substitution this line used to describe
  unconditionally.
- **Deleting moves to the Trash on macOS** (`mac.trash`; Put Back works
  afterwards), via a pluggable remover on `od_collector.ae`'s `Collector`
  (default: permanent, unchanged elsewhere) that `od_app.ae` swaps in when
  `native_trash_available()`. The confirmation card's wording and button
  label switch accordingly.
- **"Show in Finder" and "Open" go through NSWorkspace on macOS**
  (`mac.workspace`): reveal actually selects the item instead of just
  opening its parent folder, and the app launches through the same API
  Finder itself uses. Elsewhere both still build a `file://` URL and hand
  it to the OS's generic opener.
- **A real Full Disk Access probe on macOS** (`mac.fda`): a banner on the
  device-picker screen when it's actually denied, with a button straight to
  the Settings pane — replacing "never knowing" with the same detection
  OpenDisk's own prompt was built on. Suppressed under a driver spec or
  `AETHER_UI_HEADLESS` (there's no user to act on it, and probing there is
  noise, not signal).
- **The macOS-only extras still not ported**: Move to Applications, Sparkle
  updates and sandbox bookmarks. The last is replaced by *Recent Folders*:
  folders you scanned before, stored in the OS's config directory
  (`$OPENDISK_CONFIG_DIR` overrides it).
- **Dragging from the chart is ported.** The canvas is a real drag source
  (`ui.draggable`, aether-ui's generic handle-based drag API — untested on a
  canvas anywhere in aether-ui before this): hovering a segment keeps the
  canvas armed with that item's path, live, so a drag started mid-gesture
  always carries whatever's actually under the pointer (`chart_move` /
  `update_chart_drag` in `od_app.ae`). The centre ring ("go back") and empty
  space both un-arm it. The chart's context menu still offers *Add to
  Collector* too, same as a list row does alongside its own drag.
- **The Collector's list is always visible** under the chart, rather than
  OpenDisk's hover pop-up.
- **Search name folding** is lowercase plus composed Latin accents (`od_text.c`),
  so a user typing "Café" matches a name macOS stored decomposed. Full Unicode
  folding would come from utf8proc once aether's contrib/i18n exposes one.
- **Windows:** `od_stat.c` and `od_text.c` cross-compile and link with
  mingw-w64 (`-Wall -Wextra`, clean), but the app has **not yet run** on
  Windows. `od_devices` lists drive letters, but capacity shows only where
  `statvfs` exists, which excludes Windows today.

## Test hooks

- `$OPENDISK_SCAN` or the first argument opens a folder directly.
- The chart's accessibility description names the hovered segment
  ("Movies, 2 MB, 80.3 percent"). The specs read it through
  `GET /widget/{id}/a11y`, and it is also what a screen reader hears.
- `$OPENDISK_CHART_PNG=<file>` writes the chart to a PNG on every repaint, off
  screen. That makes the chart visible where screenshots are not.

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
  OpenDisk-ae/   this repo
```

`aether-ui` and `build_support` at the repo root are **relative symlinks**
into `../aether-ui`. Point `aether-ui` at another checkout to build against
it. The build takes aether-ui's `ui` and `vg` modules and its per-OS backend
link setup from there, so nothing here duplicates them. (On Windows, clone
with `core.symlinks=true`.)

The port needs Aether ≥ 0.717.0, which carries three fixes it relies on (a
trailing block on a struct-field assignment; `_` bound inside a loop;
`fs.hard_link`, used by the tests).

## Build, run, test

```sh
aeb opendisk/.build.ae                       # → target/build/opendisk/bin/opendisk
./target/build/opendisk/bin/opendisk         # opens on the device screen
./target/build/opendisk/bin/opendisk ~/Downloads   # opens straight into a scan

test/run_tests.sh                            # unit suites (std.spec): no window needed
AETHER_UI_WITH_DRIVER=1 aeb opendisk/.build.ae
spec/run.sh                                  # AetherUIDriver specs, one fresh app each
./ci.sh                                      # all three, in that order
```

In a sandbox or CI job whose `$HOME` is read-only, set `AETHER_CACHE_DIR` to a
writable directory: `ae run` caches compiled binaries there.

## Layout

| Path | What |
|---|---|
| `opendisk/` | the app: `opendisk.ae` builds the window, `od_*.ae` the rest, `od_stat.c` / `od_text.c` the per-OS C |
| `test/` | unit suites, one per module area, `std.spec` |
| `spec/` | AetherUIDriver specs, with `od_driver.ae` as their vocabulary and `run.sh` running them |

## How it maps onto OpenDisk

| OpenDisk (Swift) | Here | Tested by |
|---|---|---|
| `FileTree`, roll-up, hard-link dedup | `opendisk/od_tree.ae` | `test/test_tree.ae` |
| `TraversalScanner` (allocated sizes, same device, no symlinks) | `opendisk/od_scan.ae`, `od_stat.c` | `test/test_scanner.ae` |
| `ChartItem`, `RingsChartLayout`, `ChartPalette` | `opendisk/od_chart.ae` | `test/test_chart.ae` |
| `RingsChartView`, `ChartHoverTip` | `opendisk/od_draw.ae` | `spec/spec_chart.ae` |
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

- **No FSEvents incremental rescans.** Every scan is a full scan, as OpenDisk
  does the first time. OpenDisk's macOS scan cache is not ported either.
- **The macOS-only extras are dropped.** That covers the Full Disk Access prompt,
  Move to Applications, Sparkle updates and sandbox bookmarks. The last is
  replaced by *Recent Folders*: folders you scanned before, stored in the OS's
  config directory (`$OPENDISK_CONFIG_DIR` overrides it).
- **"Purgeable Space"** is OpenDisk's list of known cache folders, with a Linux
  and a Windows version added (`od_view.ae`).
- **Quick Look is Open**, which uses the default app. *Show in Finder* is
  *Show in File Manager*.
- **Dragging from the chart is not ported.** The canvas has no drag source. The
  chart's context menu offers *Add to Collector* instead. List rows do drag,
  and a drop anywhere on the window collects.
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

<h1>
  <img alt="Containers" src="https://github.com/apple/container/raw/main/docs/assets/landing-movie.gif" width="0" height="0" />
  Containers
</h1>

A native **SwiftUI** desktop app for managing [Apple's `container`](https://github.com/apple/container) tool — run and inspect Linux containers, browse images, and control the system service, all from a polished Mac UI.

Containers is a thin, robust GUI **on top of the `container` command-line tool**. It shells out to the supported CLI and decodes its `--format json` output, so it stays compatible across `container` releases instead of binding to internal APIs.

---

## Requirements

- **macOS 26** on **Apple silicon** — required by `container` itself.
- Apple's [`container`](https://github.com/apple/container/releases) tool installed (the signed installer places it at `/usr/local/bin/container`).
- **Xcode 16+** and **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** to build from source.

> The app deploys to macOS 14 so it can launch and show a friendly "not installed" screen, but the backend it drives needs macOS 26.

## Build & run

This repo doesn't check in an `.xcodeproj`; it's generated from [`project.yml`](project.yml) with XcodeGen.

```bash
brew install xcodegen          # one-time
xcodegen generate              # creates ContainersUI.xcodeproj
open ContainersUI.xcodeproj    # then Run (⌘R) in Xcode
```

Or from the command line:

```bash
xcodegen generate
xcodebuild -scheme ContainersUI -configuration Debug build
```

### Tests

```bash
xcodegen generate
xcodebuild -scheme ContainersUI -destination 'platform=macOS' test
```

The unit tests are **host-less logic tests**: the test bundle compiles the UI-independent `Core/` sources directly and exercises them with a mock command runner and recorded CLI JSON fixtures — no live `container` backend, no GUI launch. They cover JSON decoding, exact argv construction, error classification, and formatting.

## Architecture

The app talks to `container` through one small, testable seam.

```
SwiftUI Views  ──▶  @Observable ViewModels  ──▶  Services  ──▶  ContainerCLI  ──▶  CommandRunner
 (Features/)         (per feature)              (Core/Services) (Core/CLI)         (Process)
                                                                                       │
                                                          MockCommandRunner ◀──────────┘  (tests)
```

- **`CommandRunner`** (`Core/CLI`) — a protocol over process execution. `ProcessCommandRunner` runs the real binary; `MockCommandRunner` feeds fixtures in tests.
- **`ContainerCLI`** — resolves the `container` binary, runs invocations, classifies failures into a typed `CLIError`, and decodes JSON with a decoder configured to match the CLI's encoder (ISO-8601 dates, no key-strategy remapping).
- **Services** — `ContainerService`, `ImageService`, `SystemService` build exact argv (via pure, unit-tested `…Arguments(…)` functions) and return `Codable` models.
- **Models** (`Core/Models`) — Swift structs that mirror the CLI's JSON shapes exactly, including the OCI config's PascalCase keys and `snake_case` `diff_ids`/`created_by`.
- **Design system** (`DesignSystem/`) — a small component library (soft pill controls, translucent material cards with gradient hairlines, status badges, springy motion) shared across screens.

### Why shell out to the CLI?

`container`'s Swift packages are only API-stable within patch versions, and talking to its XPC `apiserver` directly requires matching entitlements and tracks internal changes. The CLI is the documented, stable surface, and almost every read command supports `--format json`. Shelling out keeps this app decoupled and resilient — the same approach mature Docker/Podman GUIs take.

## Features (v1)

| Area | Capabilities |
|------|--------------|
| **Containers** | List (all/running), live stats, inspect, start/stop/restart/kill, delete, streaming logs, exec, and a full **Run** form. |
| **Images** | List, inspect (config/env/layers/platforms), **Pull** with streaming progress, tag, delete. |
| **System** | Service status, versions, disk usage, and start/stop the system service. |

The app auto-detects the `container` binary (and lets you set a custom path in **Settings**), and surfaces a clear state when the tool isn't installed or the service isn't running.

## Project layout

```
App/            App entry, root navigation, sidebar, settings, backend state
Core/
  CLI/          CommandRunner, ContainerCLI, CLIError, executable resolution
  Models/       Codable models + formatting + image-reference parsing
  Services/     ContainerService, ImageService, SystemService
DesignSystem/   Theme tokens + reusable components
Features/
  Containers/   Containers screen, row, detail, logs, run
  Images/       Images screen, row, detail, pull, tag
  System/       System screen
Resources/      Assets, entitlements, generated Info.plist
Tests/          Logic tests + fixtures + mock runner
project.yml     XcodeGen project definition
```

## Signing & distribution

The app runs **unsandboxed** (see `Resources/ContainersUI.entitlements`) because it spawns `/usr/local/bin/container`, which talks to a launchd service over XPC — the App Sandbox blocks that. Distribute with **Developer ID + notarization** (Hardened Runtime is enabled), not the Mac App Store. Set your `DEVELOPMENT_TEAM` in `project.yml`, or sign "to run locally" in Xcode for development.

## Status

v1. This is an independent project and is not affiliated with or endorsed by Apple. It complements the `container` tool, which remains under active development.

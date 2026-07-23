# Changelog

All notable changes to Pantalk Station are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.0.2] - 2026-07-23

### Added

- Add optional KasmVNC encoder statistics behind `STATION_VNC_STATS`, reporting
  framebuffer update counts, rect counts, pixel volumes, and compression ratios
  per session.
- Add a `make vnc-log` target. KasmVNC writes Xvnc's output to a per-session log
  rather than to the container log, so `make logs` never showed these.
- Use a host GPU when one is available. The desktop, Chrome, and Halloy now
  detect a DRI render node and enable hardware rendering, passing the device
  through from the Makefile. Hosts without `/dev/dri`, including Podman and
  Docker VMs on macOS and Windows, keep using software rendering.

### Changed

- Tune the kitty terminal for a software-rendered remote display. A blinking
  cursor alone produced 17 screen changes in 12 seconds on an idle terminal,
  each one a frame KasmVNC had to encode; the tuned configuration produces
  none.
- Update the GitHub Actions used by the CI, release, and tagging workflows.

### Fixed

- Remove the invalid `resize_draw_strategy` kitty setting, which the terminal
  had been rejecting as an unknown configuration key.

## [0.0.1] - 2026-07-23

### Added

- Add the browser-accessible Pantalk Station desktop image.
- Include Pantalk, Codex, Claude, Halloy, and a trusted local IRC room.
- Add persistent Docker volumes and a local Makefile workflow.
- Add automated validation, version tagging, GitHub releases, and GHCR image
  publishing.

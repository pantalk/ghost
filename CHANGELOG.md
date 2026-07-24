# Changelog

All notable changes to Pantalk Station are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.0.5] - 2026-07-24

### Changed

- Bundle Pantalk 0.0.10, which adds the XMPP/Jabber, Twitch, and Nostr
  connectors.

## [0.0.4] - 2026-07-24

### Added

- Add a supported Mattermost deployment using the official Mattermost Team
  Edition and PostgreSQL images with Pantalk Station.
- Add idempotent Mattermost administrator, team, channel, bot, and token
  provisioning.
- Add published-image and local-Dockerfile Compose workflows plus a live
  inbound and outbound messaging smoke test.
- Add an Ergo deployment using the official Ergo and The Lounge images with
  Pantalk Station.
- Add a live IRC smoke test covering browser availability plus inbound and
  outbound messages.

### Changed

- Make the base Station image transport-neutral. Messaging deployments now
  provide all provider-specific services and Pantalk configuration.
- Replace the bundled IRC starter with a local Pantalk connector while
  preserving Codex and Claude agent definitions.

### Removed

- Remove Ergo, Halloy, the IRC autostart path, IRC environment variables,
  IRC-specific volumes, and the Chat desktop entry from the Station image.

## [0.0.3] - 2026-07-23

### Added

- Add `STATION_IRC_CHANNELS` (`IRC_CHANNELS` in the Makefile) to control which
  channels the IRC server auto-joins clients to. The agents are only present in
  channels Ergo puts them in, so this is what makes additional channels
  reachable.

### Changed

- Let the Codex and Claude agents work in every channel instead of only
  `#station`, and answer direct messages without needing a `codex:` or
  `claude:` prefix.

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

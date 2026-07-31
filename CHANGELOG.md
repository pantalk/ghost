# Changelog

All notable changes to Pantalk Ghost are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.7] - 2026-07-31

### Fixed

- Update the shared Launcher desktop base to `0.1.3` so fixed-ownership mounts
  retain their host-managed permissions under Apple `container`.
- Write Codex and Claude runtime configuration without requesting ownership
  changes after the desktop selects the VM root account.

## [0.1.6] - 2026-07-30

### Added

- Expose the shared desktop screenshot endpoint as the Launcher `preview`
  interface.

### Changed

- Update the shared Launcher desktop base to `0.1.2`.

## [0.1.5] - 2026-07-30

### Changed

- Replace the single Launcher viewer and container port with the `desktop`
  `kasmweb` interface required by application schema version 2.

## [0.1.4] - 2026-07-30

### Changed

- Remove fixed desktop-resolution configuration from the Launcher manifest,
  local Docker workflow, and bundled Compose deployments. KasmVNC now sizes
  the remote desktop for the connected viewer.
- Remove the unused product-version copy from the Launcher application
  document. The root `VERSION` file remains authoritative.
- Update the shared Launcher desktop base to `0.1.1`.

## [0.1.3] - 2026-07-30

### Fixed

- Pass the temporary Launcher application archive to ORAS by relative path so
  its attachment path validation succeeds.

## [0.1.2] - 2026-07-30

### Fixed

- Install ORAS through its Node 24 setup action so the image-owned Launcher
  application artifact can be attached and published successfully.

## [0.1.1] - 2026-07-30

### Changed

- Publish the Launcher application definition and artwork as an OCI artifact
  attached to the final multi-architecture image digest.

## [0.1.0] - 2026-07-30

### Changed

- Build on the published Launcher desktop base
  (`ghcr.io/pdparchitect/launcher-image-base-desktop`) instead of assembling
  Ubuntu, Node, KasmVNC, Openbox, and the browser here. That desktop was
  originally ported *from* Ghost; now that several images share it, Ghost
  consumes it rather than keeping a second copy of a stack it no longer owns
  alone. The Dockerfile keeps only Pantalk and its agent runtimes, dropping
  from 408 lines to 155.
- **Breaking.** The desktop account is the base's `agent`, homed at
  `/home/agent`. Volume targets move from `/home/ghost/...` to
  `/home/agent/...`; an existing deployment must remount its volumes at the new
  paths or start from a fresh set. The Launcher catalogue manifest and both
  bundled Compose deployments are updated.
- **Breaking.** `GHOST_RESOLUTION` and `GHOST_VNC_STATS` are replaced by the
  base's `DESKTOP_RESOLUTION` and `DESKTOP_VNC_STATS`. Every other `GHOST_*`
  and `PANTALK_*` variable is unchanged.
- Declare ports the way the other Launcher desktops do: `6901` and the health
  check are inherited from the base rather than redeclared.
- Logs move from `/var/log/ghost` to the base's `/var/log/launcher-desktop`.
- Product files are installed through `overlay/`, which is copied over the
  base's defaults, rather than through per-file `COPY` instructions. The
  entrypoint is the base's: Pantalk's starter config and daemon come up from
  `/etc/desktop/startup.d/10-pantalk`, and the workspace seed moves to the
  path the base already copies into `/workspace`.

### Removed

- The Openbox, Cortile, KasmVNC, GTK-theme, and browser-wrapper sources, along
  with `init.sh`. All of them are the desktop base's now. Ghost's GTK theme,
  Openbox theme, and panel config turned out to be byte-identical to the
  base's, so only the wallpaper, favicon, landing page, root menu, and mascot
  remain as branding.

### Fixed

- The KasmVNC mascot survives the move. The base's `kasm-patch` knows nothing
  about it, so `kasm-mascot` injects it separately - after `kasm-patch`,
  because both rewrite the same `<head>` - and it stays content-hash versioned
  so browsers cannot serve a stale overlay against a fresh image.

## [0.0.10] - 2026-07-28

### Fixed

- Avoid `chmod` and ownership-preserving file installation on macOS folders
  mounted by Apple container. Its VirtioFS shares reject both ownership and
  permission changes, even when Ghost is already using the VM root account.

## [0.0.9] - 2026-07-28

### Fixed

- Start correctly with macOS folders mounted by Apple container. Those
  VirtioFS shares are exposed as root-owned and reject ownership changes, so
  Ghost now detects fixed ownership and runs as root inside that container's
  dedicated Linux VM. Ownership-mutable Docker volumes continue to use the
  unprivileged `ghost` account.

## [0.0.8] - 2026-07-27

### Added

- Publish one multi-architecture Ghost image for `linux/amd64` and
  `linux/arm64`, with native build and desktop smoke tests for both
  architectures before their digests are combined into a release manifest.

### Changed

- Keep Google Chrome on AMD64 and use signed Debian Chromium on ARM64 behind
  the same launcher, GTK theme, managed policy, and desktop integration.
- Let local builds and the Ergo and Mattermost deployments select the host
  architecture automatically instead of forcing `linux/amd64`.

## [0.0.7] - 2026-07-27

### Added

- Add an image-owned `workspace/` seed with a default `AGENT.md`. Container
  startup copies missing seed files into the persistent `/workspace` volume
  without replacing user files, so defaults reach both new and existing
  workspaces.
- Add a guided runtime authentication helper for Codex device, browser, and
  API-key login; Claude subscription, Console, setup-token, and SSO login; and
  Kimi Code's interactive `/login` flow.
- Add persistent Kimi Code state, Ranger workspace/home bookmarks, a Pantalk
  daemon status badge, desktop log actions, a custom favicon, and reproducible
  image-size reporting.
- Add fast shell, behavior, and pinned-metadata checks and run them before the
  CI image build.
- Add the Pantalk mascot to the lower-left of the KasmVNC client page: an
  unframed ghost drifting gently in place over a soft accent glow, reusing the
  site's palette, float animation, and hover treatment. It is drawn by the
  viewer's browser rather than the remote desktop, so it adds no X client and
  no encoder load.
- Add `ghost-harness`, which opens the agent harness the operator last signed
  in to, bound to `Ctrl+Shift+G` and to clicking the desktop mascot. Signing in
  through `agent-runtime-login` is what selects the harness, so there is no
  separate preference to maintain; a status check is not a sign-in and leaves
  the selection alone. The harness starts in `/workspace`, matching the
  `workdir` the chat-side agents use, rather than the session home directory
  Openbox would otherwise pass down. Repeated activation raises the existing
  window instead of stacking terminals.
- Declare Codex's sandbox mode as `danger-full-access` at boot. Codex sandboxes
  commands with bubblewrap, which cannot create a user namespace inside the
  container, so no sandbox mode is enforceable and Codex warned on every start
  about falling back to its bundled copy. Installing the distro package only
  adds a second binary that fails identically. The container is the boundary;
  the setting now says so. Override with `GHOST_CODEX_SANDBOX_MODE`.
- Record the workspace as trusted for Codex and Claude Code at boot, so the
  harness opened from the desktop does not sit on a per-directory trust prompt
  for a directory the chat-side agents already work in unattended. This grants
  no access the chat path did not already have; set `GHOST_TRUST_WORKSPACE` to
  `false` to keep both prompts.

### Changed

- Pin GTK and Chrome's Linux UI typography to Noto Sans 9, matching every
  Openbox title, menu, and on-screen-display font declaration instead of
  inheriting GTK's larger Sans 10 default.
- Give Chrome a self-contained near-black GTK system theme that darkens native
  menus and popups as well as the tab strip, active tab, toolbar, controls, and
  address field; render Chrome's window controls from the same XBM masks and
  state colors as Openbox, square the GTK-controlled outer frame corners, and
  replace the bundled welcome card with the terminal's ASCII banner on pure
  black.
- Outline the focused window in white. The wallpaper and every window
  frame are near-black, so an unfocused-looking window had no visible edge
  against the desktop; unfocused frames stay dark so exactly one window
  reads as active.
- Remove the window handle, which drew a second line under the client area with
  a resize grip boxed off at each end. Resizing stays available through the
  window edges and corners and through Alt+right-drag anywhere on the frame.
- Start terminals in `/workspace` instead of the home directory, so the
  desktop and the chat-side agents work in the same tree. Openbox chdirs to
  `$HOME` at startup whatever directory it was started from and hands that to
  everything it launches, so this is set in the shell - the one place every
  terminal passes through - and only when the shell landed in `$HOME`, which
  leaves non-interactive shells and deliberate directories alone.
- Widen the window grab margin with client padding. Removing the handle left a
  1px frame to grab at the bottom against a 28px titlebar, so the bottom
  corners were nearly unhittable. Client padding adds frame around the client
  and paints it in the frame background, taking the grabbable ring from 1px to
  7px while the focus outline stays 1px.
- Rename the product to Pantalk Ghost across the repository, container image,
  local directory, runtime identifiers, deployment resources, and
  documentation.
- Rename the desktop account and home directory to `ghost` and `/home/ghost`,
  and render the `@ghost` shell prompt in neon green.
- Replace the random third-party wallpaper set with a deterministic
  Pantalk-branded desktop background based on the site's palette and subtle
  grid treatment.
- Pin Node.js tooling and all globally installed agent CLIs, and use the pinned
  Claude Code npm package instead of the floating installer.
- Pass only DRI render nodes into the container and enable hardware rendering
  only when the desktop user can actually open one.
- Normalize named-volume ownership once per volume lifetime instead of walking
  growing workspace and runtime trees on every boot.
- Remove the unused hardware X server and `x11-xserver-utils` dependency chain;
  KasmVNC already supplies Xvnc.
- Keep the image-owned Tint2 configuration authoritative, add conventional
  Kitty copy/paste bindings, reduce the Docker build context, and skip full CI
  builds for documentation-only changes.

### Fixed

- Keep the KasmVNC browser title stable instead of replacing it with a
  container hostname after connection.
- Replace the obsolete welcome-screen instruction for the removed bundled Chat
  menu with the current transport-neutral deployment flow.
- Version the injected mascot asset URLs by content hash. KasmVNC serves them
  with no cache-control, etag, or last-modified, so browsers had nothing to
  revalidate against and kept running a stale overlay against a freshly built
  image.

## [0.0.6] - 2026-07-24

### Added

- Preinstall Kimi Code (`@moonshot-ai/kimi-code`), so the `kimi` binary is
  available to Pantalk's `acp` driver via `command: kimi acp`.

### Changed

- Bundle Pantalk 0.0.11, which adds the `acp` driver for Agent Client Protocol
  agents and an agent-level `env` map honored by every driver.

## [0.0.5] - 2026-07-24

### Changed

- Bundle Pantalk 0.0.10, which adds the XMPP/Jabber, Twitch, and Nostr
  connectors.

## [0.0.4] - 2026-07-24

### Added

- Add a supported Mattermost deployment using the official Mattermost Team
  Edition and PostgreSQL images with Pantalk Ghost.
- Add idempotent Mattermost administrator, team, channel, bot, and token
  provisioning.
- Add published-image and local-Dockerfile Compose workflows plus a live
  inbound and outbound messaging smoke test.
- Add an Ergo deployment using the official Ergo and The Lounge images with
  Pantalk Ghost.
- Add a live IRC smoke test covering browser availability plus inbound and
  outbound messages.

### Changed

- Make the base Ghost image transport-neutral. Messaging deployments now
  provide all provider-specific services and Pantalk configuration.
- Replace the bundled IRC starter with a local Pantalk connector while
  preserving Codex and Claude agent definitions.

### Removed

- Remove Ergo, Halloy, the IRC autostart path, IRC environment variables,
  IRC-specific volumes, and the Chat desktop entry from the Ghost image.

## [0.0.3] - 2026-07-23

### Added

- Add `GHOST_IRC_CHANNELS` (`IRC_CHANNELS` in the Makefile) to control which
  channels the IRC server auto-joins clients to. The agents are only present in
  channels Ergo puts them in, so this is what makes additional channels
  reachable.

### Changed

- Let the Codex and Claude agents work in every channel instead of only
  `#ghost`, and answer direct messages without needing a `codex:` or
  `claude:` prefix.

## [0.0.2] - 2026-07-23

### Added

- Add optional KasmVNC encoder statistics behind `GHOST_VNC_STATS`, reporting
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

- Add the browser-accessible Pantalk Ghost desktop image.
- Include Pantalk, Codex, Claude, Halloy, and a trusted local IRC room.
- Add persistent Docker volumes and a local Makefile workflow.
- Add automated validation, version tagging, GitHub releases, and GHCR image
  publishing.

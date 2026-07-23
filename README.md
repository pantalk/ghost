# Pantalk Station

<img width="3456" height="2234" alt="tpsmlhvh-6902 euw devtunnels ms_(MacBook Pro 16_)" src="https://github.com/user-attachments/assets/8dafdf9a-9f69-4961-8566-304a6b2371a7" />

Pantalk Station is a browser-accessible graphical environment for running
Pantalk and AI agents locally. It is a deliberately small fork of the original
CBK sandbox desktop: the same Openbox environment, Simple Desktops wallpapers,
Tint2 panel, Triste-Crimson theme, Kitty terminal, and on-demand Cortile tiling.

Station includes:

- CBK branding is replaced with Pantalk Station.
- VS Code is not installed or shown in the application menu.
- `pantalk` and `pantalkd` are installed from the pinned Pantalk release.
- Halloy provides a native local agent-chat client with a black,
  terminal-inspired Pantalk theme.
- Ergo provides a loopback-only IRC room with no accounts or passwords.
- Codex and Claude are registered as agents in the starter Pantalk config.
- Docker persistence is included for IRC, Pantalk, Halloy, and agent state.
- A Makefile provides the local build, run, and test workflow.

## Run locally

Build and start Station:

```bash
make up
```

Open <http://127.0.0.1:6902>. The browser is only a KasmVNC client for the
Linux environment; there is no separate dashboard.

Other useful commands:

```bash
make build
make run
make recreate
make test
make logs
make status
make stop
```

To select another port or initial resolution:

```bash
PORT=8080 RESOLUTION=1600x900 make up
```

The default port binds only to `127.0.0.1`. Do not change `BIND_ADDRESS`
unless the no-password environment is intentionally being exposed.

## Run the published image

Official releases are published to GitHub Container Registry:

```bash
docker pull ghcr.io/pantalk/station:latest
docker run --detach \
  --name pantalk-station \
  --shm-size 1g \
  --publish 127.0.0.1:6902:6901 \
  ghcr.io/pantalk/station:latest
```

Open <http://127.0.0.1:6902>. Use the Makefile workflow when persistent
configuration, chat history, agent authentication, and workspace volumes are
needed.

## Local agent room

Right-click the desktop and select **Chat**. Halloy connects
automatically to the local `#station` IRC channel as `operator`. No IRC
registration, username, or password setup is required.

Address either agent directly:

```text
codex: explain the repository structure
claude: review the current changes
```

`@codex` and `@claude` mentions also work. Explicit addressing prevents the
two agents from responding to each other and creating a loop.

The agent CLIs still require their normal local authentication. Their
configuration is persisted in the `pantalk-station-codex` and
`pantalk-station-claude` Docker volumes. Open **Setup** in the desktop menu
to launch either login flow without leaving Station.

This configuration deliberately assumes a trusted local environment:

- KasmVNC has no browser password.
- Ergo listens only on `127.0.0.1` inside the container.
- IRC has no account registration, connection password, or TLS.
- Codex may write within `/workspace` without interactive approval.
- Claude uses its noninteractive `acceptEdits` permission mode.

Do not publish port 6901 or change `BIND_ADDRESS` on an untrusted host.

## Pantalk configuration

The image pins Pantalk to the release declared in the Makefile. Override the
build argument when a different release is needed:

```bash
PANTALK_VERSION=VERSION make build
```

On first boot, Station creates `~/.config/pantalk/config.yaml` with two IRC
bots and two matching agent definitions:

- IRC nickname `codex` uses the native Pantalk Codex driver.
- IRC nickname `claude` uses the native Pantalk Claude driver.

Both join `#station` through the embedded IRC server. Pantalk configuration,
state, agent authentication, IRC state, Halloy configuration, and `/workspace`
use persistent Docker volumes.

When upgrading from the original Station starter config, the untouched
`station-local` configuration is migrated automatically and saved beside the
new file as `config.yaml.station-v1.bak`. Customized Pantalk configurations
are never replaced.

Disable automatic daemon startup with:

```bash
PANTALK_AUTOSTART=false make recreate
```

Disable the embedded IRC server with:

```bash
IRC_AUTOSTART=false make recreate
```

## Profiling the desktop

If the remote desktop feels slow, enable the KasmVNC encoder statistics:

```bash
VNC_STATS=true make recreate
make vnc-log
```

This raises the log level of KasmVNC's `EncodeManager` writer only, which
reports framebuffer update counts, rect counts, pixel volumes, and compression
ratios per encoding.

Statistics accumulate only while a browser is connected, and the summary is
written when that browser disconnects - so connect, use the desktop, then close
the tab before reading the log. KasmVNC writes them to its own session log
inside the container rather than to the container log, which is why `make logs`
does not show them.

As a baseline, a settled idle desktop reports roughly four framebuffer updates
and about 90 KiB of traffic for a thirty second session, most of it the single
full-screen paint sent when the client connects. Substantially more than that
means something on the desktop is repainting continuously.

The browser-side view of the same picture lives in the KasmVNC control panel:
enable performance statistics to see CPU, network, and FPS.

## Environment

Right-click the background to open the original application menu:

- Terminal
- Ranger file manager
- htop task manager
- Chat, powered by Halloy
- Chrome
- Setup, with Codex and Claude login actions
- Cortile tiling controls

The desktop starts in floating mode. Press `Ctrl+Shift+T` or use the menu to
toggle tiling.

## Releases

Station releases are driven by the `VERSION` file. A successful CI run on
`main` creates the matching tag, publishes the versioned image and stable
`latest` tag to GitHub Container Registry, and creates a GitHub Release.

See [RELEASES.md](RELEASES.md) for the release procedure and package visibility
requirements.

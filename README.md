# Pantalk Station

<img width="3456" height="2234" alt="tpsmlhvh-6902 euw devtunnels ms_(MacBook Pro 16_)" src="https://github.com/user-attachments/assets/8dafdf9a-9f69-4961-8566-304a6b2371a7" />

**Station is the showcase for how easy this is.**

[Pantalk](https://github.com/pantalk/pantalk) puts the coding agent you already
run into the chat apps your team already uses - any agent, any chat - without
welding the two together. The agent never learns which chat app it is talking
to, and the chat app never learns which agent is answering. Station is that
claim, assembled and running, so you can see it instead of reading about it.

It is a browser-accessible Linux desktop with Pantalk, Codex, and Claude Code
already installed and registered as agents. Boot it, log into a harness, bring
up a deployment, and a real chat server has a real agent in it a few minutes
later. Changing which harness answers is one `driver:` line.

Station also demonstrates **one subscription, whole team**. Authenticate Codex or
Claude Code once inside Station, and everyone reaches that single install from
the chat client they already have open - no per-person license, no local setup,
and nobody else needing a terminal. Pantalk keys sessions by user, channel, and
thread, so each teammate still gets an isolated conversation.

Note that the desktop itself is a single-tenant, trusted-host environment (see
[Security posture](#harness-authentication)) - what the team shares is the
harness *through chat*, not the desktop. Run Station somewhere you control and
let Pantalk be the front door.

Underneath, it is a deliberately small fork of the original CBK sandbox desktop:
the same Openbox environment, Simple Desktops wallpapers, Tint2 panel,
Triste-Crimson theme, Kitty terminal, and on-demand Cortile tiling.

Station includes:

- CBK branding is replaced with Pantalk Station.
- VS Code is not installed or shown in the application menu.
- `pantalk` and `pantalkd` are installed from the pinned Pantalk release.
- Codex and Claude Code are registered as agents in the starter Pantalk config,
  so both harnesses are one config line away from any bot.
- Docker persistence is included for Pantalk, agent authentication, and the
  workspace.
- Messaging systems are added through deployment recipes rather than bundled
  into the Station image - the image stays transport-neutral on purpose, because
  the point is that the platform is interchangeable.
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

## Deployments

Deployments are where the pluggability becomes visible. Each one combines the
same unmodified Station image with a different messaging system, on that
system's official images. Nothing about Station changes between them - only the
Pantalk configuration mounted over the starter.

The initial [Mattermost deployment](deployments/mattermost/README.md) starts
Mattermost Team Edition, PostgreSQL, and Station; provisions `codex` and
`claude` bot accounts; and supports both the published Station image and a local
Dockerfile build.

```bash
cd deployments/mattermost
make up
```

The [Ergo deployment](deployments/ergo/README.md) starts an external Ergo IRC
server, The Lounge browser client, and Station:

```bash
cd deployments/ergo
make up
```

Two deployments, two protocols, one image, both harnesses available in each.
Deployment recipes do not publish modified messaging-server images. See the
[deployment index](deployments/README.md).

## Harness authentication

The harness CLIs still require their normal local authentication. Their
configuration is persisted in the `pantalk-station-codex` and
`pantalk-station-claude` Docker volumes. Open **Setup** in the desktop menu
to launch either login flow without leaving Station.

Authenticate one or both. Which one ends up answering a given conversation is
decided later, in Pantalk config, and can be changed without touching either
login.

The base image does not contain a messaging server or client. Use a deployment
recipe to connect the authenticated harnesses to Mattermost, Ergo, or another
supported messaging system.

Station deliberately assumes a trusted local environment:

- KasmVNC has no browser password.
- Codex may write within `/workspace` without interactive approval.
- Claude uses its noninteractive `acceptEdits` permission mode.

Do not publish port 6901 or change `BIND_ADDRESS` on an untrusted host.

## Pantalk configuration

The image pins Pantalk to the release declared in the Makefile. Override the
build argument when a different release is needed:

```bash
PANTALK_VERSION=VERSION make build
```

On first boot, Station creates `~/.config/pantalk/config.yaml` with a local
connector plus Codex and Claude Code agent definitions. It does not connect to
an external messaging service. Each deployment mounts its provider-specific
Pantalk configuration over this starter - the agent definitions carry across
unchanged, which is exactly the property Station is meant to demonstrate.

When upgrading an untouched image that still has the bundled IRC starter,
Station saves it as `config.yaml.station-irc.bak` and installs the
transport-neutral starter. Customized Pantalk configurations are never
replaced.

Disable automatic daemon startup with:

```bash
PANTALK_AUTOSTART=false make recreate
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

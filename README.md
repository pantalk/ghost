# Pantalk Ghost

**An always-on agent computer for the harnesses you already use.**

## Quick start

### Launcher (recommended)

The easiest way to run Ghost is with
[Launcher](https://github.com/pdparchitect/launcher). Launcher discovers,
installs, starts, stops, and updates Ghost while managing its container, ports,
and persistent storage for you.

1. [Download the latest Launcher release](https://github.com/pdparchitect/launcher/releases/latest).
2. Open **Marketplace**, select **Pantalk Ghost**, and install it.
3. Choose **Open agent** when installation finishes, then open **Setup** from
   the desktop menu to sign in to a harness.

Launcher uses Apple `container` on macOS and Docker on Linux.

### Run the container manually

Ghost also publishes native AMD64 and ARM64 images. Choose the container
runtime installed on your host.

#### Docker

```bash
docker run --detach \
  --name pantalk-ghost \
  --shm-size 1g \
  --publish 127.0.0.1:6901:6901 \
  --publish 127.0.0.1:6902:6902 \
  ghcr.io/pantalk/ghost:latest
```

#### Podman

```bash
podman run --detach \
  --name pantalk-ghost \
  --shm-size 1g \
  --publish 127.0.0.1:6901:6901 \
  --publish 127.0.0.1:6902:6902 \
  ghcr.io/pantalk/ghost:latest
```

#### Apple container

Apple's [`container`](https://github.com/apple/container) tool requires Apple
silicon and macOS 26 or later. Start its service once, then run Ghost with
enough memory for the desktop and agent harness:

```bash
container system start

container run --detach \
  --name pantalk-ghost \
  --memory 4g \
  --shm-size 1g \
  --publish 127.0.0.1:6901:6901 \
  --publish 127.0.0.1:6902:6902 \
  ghcr.io/pantalk/ghost:latest
```

Apple exposes macOS host-folder mounts as fixed, root-owned shares. When Ghost
detects those mounts, it runs as root inside that container's isolated Linux VM
so its workspace and configuration remain writable. Named volumes and
ownership-mutable Docker or Podman storage continue to run as `ghost`.

Open <http://127.0.0.1:6901>. This is the Ghost computer itself, presented
through KasmVNC rather than a separate dashboard. Open **Setup** from the
desktop menu and sign in to Codex, Claude Code, or Kimi Code.
The separate current-desktop preview is available at
<http://127.0.0.1:6902/preview.jpg>.

The standalone image starts with Pantalk's local connector. To connect the
authenticated harness to a real chat system, use one of the
[deployment recipes](#deployments).

<img width="2560" height="1440" alt="Pantalk Ghost running as a persistent Linux agent computer in a browser" src="https://github.com/user-attachments/assets/e6d199ee-9a8e-49a6-a8a6-a9ff320bd490" />

This short command is for trying Ghost. Its state directories use anonymous
volumes, so replacing the container loses their association and leaves the old
volumes behind on disk. Use named volumes for a computer you intend to keep.

### Persistent setup

For a long-lived Ghost, add a restart policy and name every persistent volume:

```bash
docker run --detach \
  --name pantalk-ghost \
  --restart unless-stopped \
  --shm-size 1g \
  --publish 127.0.0.1:6901:6901 \
  --publish 127.0.0.1:6902:6902 \
  --volume pantalk-ghost-workspace:/workspace \
  --volume pantalk-ghost-config:/home/agent/.config/pantalk \
  --volume pantalk-ghost-state:/home/agent/.local/share/pantalk \
  --volume pantalk-ghost-codex:/home/agent/.codex \
  --volume pantalk-ghost-claude:/home/agent/.claude \
  --volume pantalk-ghost-kimi:/home/agent/.kimi \
  ghcr.io/pantalk/ghost:latest
```

Podman accepts the same command with `podman` in place of `docker`. With
Apple's tool, use `container` in place of `docker`, remove
`--restart unless-stopped`, and add `--memory 4g`. Apple `container` preserves
the named volumes and stopped container but does not expose a Docker-style
restart policy; restart it with `container start pantalk-ghost`.

Pantalk configuration and history, runtime credentials, and workspace files
then survive container recreation and image upgrades.

Create another container with a different name and volume prefix when each
agent needs its own identity, credentials, browser sessions, workspace, and
lifecycle.

### Build from source

From this directory, build and start the local image:

```bash
make run
```

The Makefile selects `linux/amd64` or `linux/arm64` from the host. Override it
explicitly with `PLATFORM=linux/arm64 make run` when building for another
architecture.

Open <http://127.0.0.1:6901>. The current desktop preview is available at
<http://127.0.0.1:6902/preview.jpg>. To select other ports:

```bash
RUN_PORT=8080 RUN_PREVIEW_PORT=8081 make run
```

Like the shared Launcher image workflow, `make run` builds before recreating
the container. Use `make recreate` to skip the build, or `make up` as an alias
for `make run`.

The default port binds only to `127.0.0.1`. Do not change `BIND_ADDRESS`
unless the no-password environment is intentionally being exposed.

Useful development and lifecycle commands:

```bash
make check
make build
make run
make recreate
make test
make logs
make status
make size-report
make stop
```

## What Ghost is

OpenClaw and Hermes have made the always-on agent easy to understand: give an
agent a persistent computer, keep it running, and reach it from chat whenever
work needs doing. Ghost belongs in that category, but makes a different
architectural choice. **Ghost is not another agent runtime.** It turns the
agentic harnesses you already trust - Codex, Claude Code, Goose, Kimi Code, or
another Pantalk-compatible harness - into the agent.

The split is deliberate:

- **Ghost provides the computer:** a persistent Linux workspace, browser
  desktop, terminal, saved harness credentials, Pantalk daemon, and a stable
  place to run continuously.
- **Your harness provides the agent:** its reasoning loop, model access, tools,
  skills, approval policy, configuration, and the behavior you already know.
- **Pantalk provides the reach:** it connects that harness to Mattermost,
  Slack, Discord, IRC, SMS, and other chat systems without teaching the
  harness about any of them.

The current image includes Pantalk, Codex, Claude Code, and Kimi Code. Codex and
Claude Code are already registered in the starter config; Kimi Code is ready to
attach through Pantalk's ACP driver. Goose and other command or ACP harnesses
fit the same model once installed. Ghost does not ask you to abandon a mature
harness for a thinner built-in agent just to gain persistence and chat access.

Boot the computer, authenticate the harness you already use, and connect a
deployment. A few minutes later that harness is working from a real chat
server, with a durable workspace and its normal tools. Changing which harness
answers is one `driver:` line; changing the chat system does not change the
harness at all.

Ghost also demonstrates **one subscription, whole team**. Authenticate Codex or
Claude Code once inside Ghost, and everyone reaches that single install from
the chat client they already have open - no per-person local setup and nobody
else needing a terminal. Pantalk keys sessions by user, channel, and thread, so
each teammate still gets an isolated conversation.

The desktop itself remains a single-tenant, trusted-host environment. What the
team shares is the harness _through chat_, not the desktop. Run Ghost somewhere
you control, keep its desktop private, and let Pantalk be the front door. See
[Harness authentication](#harness-authentication) for the security model.

## Technical model

```text
Mattermost, Slack, Discord, IRC, SMS, or another chat system
                              |
                              v
                    Pantalk deployment
                connector + routing + sessions
                              |
                              v
                     Pantalk Ghost
        persistent workspace + credentials + Linux desktop
                              |
                              v
          Codex, Claude Code, Kimi Code, Goose, or another
                   command/ACP agentic harness
```

Messaging servers stay outside the image. A deployment supplies the connector
configuration, while the same Ghost image and harness definitions work across
providers. Pantalk maintains chat-side routing and session isolation; the
selected harness continues to own reasoning, tools, permissions, model access,
and execution.

Underneath, Ghost is a deliberately small fork of the original CBK sandbox
desktop: an Openbox environment, Tint2 panel, Pantalk theme, Kitty terminal,
and on-demand Cortile tiling. The browser UI is a KasmVNC view of that real
Linux desktop, which lets both the operator and the harness use the same
browser, terminal, filesystem, and display.

### What the image includes

- `pantalk` and `pantalkd` from the pinned Pantalk release;
- Codex, Claude Code, and Kimi Code as installed harnesses;
- starter Codex and Claude Code agent definitions, with Kimi Code ready to
  attach through ACP;
- support for Goose and other command or ACP harnesses once installed;
- Google Chrome on AMD64 or Chromium on ARM64, plus Kitty, Git, GitHub CLI,
  Docker CLI, Python, Node.js, pnpm, Ranger, htop, and common development
  tools;
- persistent paths for Pantalk state, harness authentication, and `/workspace`;
- the Openbox, Tint2, KasmVNC, and Cortile browser-desktop stack; and
- a Makefile for local build, lifecycle, validation, and size-report workflows.

VS Code and messaging servers are deliberately absent. Messaging systems are
composed around the unmodified image through deployment recipes, keeping Ghost
transport-neutral.

## Deployments

Deployments are where the pluggability becomes visible. Each one combines the
same unmodified Ghost image with a different messaging system, on that
system's official images. Nothing about Ghost changes between them - only the
Pantalk configuration mounted over the starter.

The initial [Mattermost deployment](deployments/mattermost/README.md) starts
Mattermost Team Edition, PostgreSQL, and Ghost; provisions `codex` and
`claude` bot accounts; and supports both the published Ghost image and a local
Dockerfile build.

```bash
cd deployments/mattermost
make up
```

The [Ergo deployment](deployments/ergo/README.md) starts an external Ergo IRC
server, The Lounge browser client, and Ghost:

```bash
cd deployments/ergo
make up
```

Two deployments, two protocols, one image, both harnesses available in each.
Deployment recipes do not publish modified messaging-server images. See the
[deployment index](deployments/README.md).

## Harness authentication

The harness CLIs still require their normal local authentication. Their
configuration is persisted in the `pantalk-ghost-codex`,
`pantalk-ghost-claude`, and `pantalk-ghost-kimi` Docker volumes. Open
**Setup** in the desktop menu to launch a guided login flow without leaving
Ghost.

Authenticate any runtime you intend to use. Which one ends up answering a
given conversation is decided later, in Pantalk config, and can be changed
without repeating the runtime logins.

Kimi Code is installed but is not part of the starter agent definitions. Its
Setup action opens Kimi Code; run `/login` there, then add an `acp` agent with
`command: kimi acp` when you want to use it.

The base image does not contain a messaging server or client. Use a deployment
recipe to connect the authenticated harnesses to Mattermost, Ergo, or another
supported messaging system.

Ghost deliberately assumes a trusted local environment:

- KasmVNC has no browser password.
- Codex may write within `/workspace` without interactive approval.
- Claude uses its noninteractive `acceptEdits` permission mode.
- Codex runs with `sandbox_mode = "danger-full-access"`. Its sandbox uses
  bubblewrap, which cannot create a user namespace inside the container, so no
  sandbox mode is enforceable here regardless of what is configured — installing
  the distro package only adds a second binary that fails identically. The
  setting is declared so the configuration states what is actually true instead
  of implying a boundary that does not exist. The boundary is the container.
  Override with `GHOST_CODEX_SANDBOX_MODE`, or set it empty to omit the setting.

Do not publish ports 6901 or 6902 or change `BIND_ADDRESS` on an untrusted
host.

### Authentication is delegated by design

KasmVNC is started with browser authentication and TLS disabled. The password
file created at boot only satisfies a KasmVNC startup check; it is not an
access-control layer.

The default loopback bind is therefore the only boundary until an external
access layer is added. If Ghost must be reachable beyond the host, put it
behind the identity-aware proxy, TLS termination, session controls, and audit
policy already used by that environment. Treat exposing Ghost without such a
layer as publishing an unauthenticated privileged workstation.

## Pantalk configuration

The image pins Pantalk to the release declared in the Makefile. Override the
build argument when a different release is needed:

```bash
PANTALK_VERSION=VERSION make build
```

On first boot, Ghost creates `~/.config/pantalk/config.yaml` with a local
connector plus Codex and Claude Code agent definitions. It does not connect to
an external messaging service. Each deployment mounts its provider-specific
Pantalk configuration over this starter - the agent definitions carry across
unchanged, which is exactly the property Ghost is meant to demonstrate.

When upgrading an untouched image that still has the bundled IRC starter,
Ghost saves it as `config.yaml.ghost-irc.bak` and installs the
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

Run `make size-report` after a build to measure how much of the image belongs
to the graphical package closure and to list its largest layers. The desktop
remains because it makes the environment inspectable, supports runtime login,
and supplies a Chromium-family browser, screen capture, and input control for
computer-use workflows. See [IMAGE-SIZE.md](IMAGE-SIZE.md) for the rationale
and trimming details.

## Environment

Right-click the background to open the original application menu:

- Terminal
- Ranger file manager
- htop task manager
- Browser (Google Chrome on AMD64, Chromium on ARM64)
- Setup, with guided Codex, Claude Code, and Kimi Code login actions
- Pantalk daemon and KasmVNC logs
- Cortile tiling controls

The desktop starts in floating mode. Press `Ctrl+Shift+T` or use the menu to
toggle tiling. The panel reports whether `pantalkd` is running, and Ranger
opens in `/workspace` with `W` and `H` bookmarks for the workspace and home.

The harness opens in `/workspace`, the same directory the chat-side agents use,
and that directory is recorded as trusted for Codex and Claude Code at boot so
neither stops on a per-directory trust prompt. That grants no access the chat
path does not already have; set `GHOST_TRUST_WORKSPACE=false` to keep the
prompts.

Press `Ctrl+Shift+G`, or click the Pantalk ghost in the lower-left corner, to open
the harness you last signed in to. Signing in through Setup is what selects it,
so there is no separate preference to keep in sync. The ghost is drawn by your
browser rather than the remote desktop, so it costs the session nothing; only
the ghost itself takes clicks, and the rest of that corner still belongs to the
desktop underneath.

The wallpaper, KasmVNC surround, Openbox chrome and menus, Tint2 panel, browser
landing page, and Kitty terminal all use the Pantalk site's dark-theme tokens:

| Site token | Value | Desktop use |
| --- | --- | --- |
| `background` | `#080A0C` | wallpaper, terminal, menus, and browser ground |
| `background-secondary` | `#0F1215` | panel and inactive window chrome |
| `background-tertiary` / `background-quaternary` | `#151A1E` / `#1D2126` | active and hovered surfaces |
| `stroke` / `stroke-secondary` | `#282E33` / `#202427` | separators and inactive outlines |
| `accent` / `accent-secondary` | `#24DBC9` / `#50E2D4` | focus, selection, cursor, links, and hover |
| `content` / `content-secondary` | `#FFFFFF` / `#818C98` | primary and muted text |

The terminal's red, yellow, blue, and magenta ANSI channels are muted
supporting colours because the Pantalk site intentionally defines only teal
accents. They remain semantic terminal colours rather than desktop accents.

## Relationship to the Launcher desktop base

Ghost is a product image on top of
`ghcr.io/pdparchitect/launcher-image-base-desktop`. That base was originally
ported *from* this desktop; now that several images share it, Ghost consumes it
rather than keeping a second copy of a stack it no longer owns alone. The base
supplies Ubuntu, Node, KasmVNC, Openbox, Cortile, tint2, kitty, the browser, the
GTK theme, the `agent` account, and the entrypoint. This repository supplies
Pantalk and overlays its site palette onto those shared desktop components.

That split is what the source layout reflects:

| Path                             | What it is                                      |
| -------------------------------- | ----------------------------------------------- |
| `Dockerfile`                     | Pantalk and the agent runtimes                   |
| `overlay/`                       | Pantalk files and themed base overrides           |
| `overlay/etc/desktop/startup.d/` | Programs the entrypoint runs before the session  |
| `deployments/`                   | Compose recipes; not part of the image           |

Three consequences are worth knowing:

- The desktop user is `agent`, homed at `/home/agent`, and logs live in
  `/var/log/launcher-desktop`.
- Desktop-level settings use the base's names — `DESKTOP_VNC_STATS` and
  `DESKTOP_TITLE`. Ghost- and Pantalk-level settings keep their `GHOST_*` and
  `PANTALK_*` names.
- The mascot is Ghost's own. The base's `kasm-patch` does not know about it, so
  `kasm-mascot` injects it separately after the base has branded the client.

To build against a different base, override `DESKTOP_IMAGE`:

```bash
make run DESKTOP_IMAGE=ghcr.io/pdparchitect/launcher-image-base-desktop:0.2.0
```

## Pinned components

Ghost pins the tools that are downloaded during a build so rebuilding the
same source does not silently install a different agent runtime:

| Component      | Version   |
| -------------- | --------- |
| Pantalk        | `0.0.12`  |
| agent-browser  | `0.33.0`  |
| GitHub Copilot | `1.0.75`  |
| Codex          | `0.145.0` |
| ChatBotKit CLI | `1.38.0`  |
| Kimi Code      | `0.29.1`  |
| Claude Code    | `2.1.220` |

`make check` verifies that the Makefile and Dockerfile pins stay synchronized.

## Releases

Ghost releases are driven by the `VERSION` file. A successful CI run on
`main` creates the matching tag, publishes the versioned image and stable
`latest` tag to GitHub Container Registry, and creates a GitHub Release.

See [RELEASES.md](RELEASES.md) for the release procedure and package visibility
requirements.

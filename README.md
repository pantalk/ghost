# Pantalk Ghost

<img width="2560" height="1440" alt="Pantalk Ghost running as a persistent Linux agent computer in a browser" src="https://github.com/user-attachments/assets/e6d199ee-9a8e-49a6-a8a6-a9ff320bd490" />

**An always-on agent computer for the harnesses you already use.**

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
the chat client they already have open - no per-person license, no local setup,
and nobody else needing a terminal. Pantalk keys sessions by user, channel, and
thread, so each teammate still gets an isolated conversation.

Note that the desktop itself is a single-tenant, trusted-host environment (see
[Security posture](#harness-authentication)) - what the team shares is the
harness _through chat_, not the desktop. Run Ghost somewhere you control and
let Pantalk be the front door.

Underneath, it is a deliberately small fork of the original CBK sandbox desktop:
the same Openbox environment, Tint2 panel, Triste-Crimson theme, Kitty
terminal, and on-demand Cortile tiling, with Pantalk's own branded wallpaper.

The image includes:

- CBK branding is replaced with Pantalk Ghost.
- VS Code is not installed or shown in the application menu.
- `pantalk` and `pantalkd` are installed from the pinned Pantalk release.
- Codex, Claude Code, and Kimi Code are installed as available harnesses;
  Pantalk can also drive Goose and other command or ACP harnesses.
- Codex and Claude Code are registered as agents in the starter Pantalk config,
  so both harnesses are one config line away from any bot.
- Docker persistence is included for Pantalk, agent authentication, and the
  workspace.
- Messaging systems are added through deployment recipes rather than bundled
  into the Ghost image - the image stays transport-neutral on purpose, because
  the point is that the platform is interchangeable.
- A Makefile provides the local build, run, and test workflow.

## Run locally

Build and start Ghost:

```bash
make up
```

Open <http://127.0.0.1:6902>. The browser is only a KasmVNC client for the
Linux environment; there is no separate dashboard.

Other useful commands:

```bash
make build
make check
make run
make recreate
make test
make logs
make status
make size-report
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
docker pull ghcr.io/pantalk/ghost:latest
docker run --detach \
  --name pantalk-ghost \
  --platform linux/amd64 \
  --shm-size 1g \
  --publish 127.0.0.1:6902:6901 \
  ghcr.io/pantalk/ghost:latest
```

Open <http://127.0.0.1:6902>. This short command is for trying Ghost: the
image-declared state directories become anonymous volumes. Replacing the
container loses the association with those volumes and leaves them behind on
disk.

For a long-lived Ghost, use the Makefile or name every persistent volume:

```bash
docker run --detach \
  --name pantalk-ghost \
  --platform linux/amd64 \
  --restart unless-stopped \
  --shm-size 1g \
  --publish 127.0.0.1:6902:6901 \
  --volume pantalk-ghost-workspace:/workspace \
  --volume pantalk-ghost-config:/home/ghost/.config/pantalk \
  --volume pantalk-ghost-state:/home/ghost/.local/share/pantalk \
  --volume pantalk-ghost-codex:/home/ghost/.codex \
  --volume pantalk-ghost-claude:/home/ghost/.claude \
  --volume pantalk-ghost-kimi:/home/ghost/.kimi \
  ghcr.io/pantalk/ghost:latest
```

Pantalk configuration and history, runtime credentials, and workspace files
then survive container recreation and image upgrades.

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

Do not publish port 6901 or change `BIND_ADDRESS` on an untrusted host.

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
and supplies Chrome, screen capture, and input control for computer-use
workflows. See [IMAGE-SIZE.md](IMAGE-SIZE.md) for the rationale and trimming
details.

## Environment

Right-click the background to open the original application menu:

- Terminal
- Ranger file manager
- htop task manager
- Chrome
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

## Pinned components

Ghost pins the tools that are downloaded during a build so rebuilding the
same source does not silently install a different agent runtime:

| Component      | Version   |
| -------------- | --------- |
| Pantalk        | `0.0.11`  |
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

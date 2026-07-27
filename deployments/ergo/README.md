# Ergo Deployment

This deployment combines the official Ergo IRC server and The Lounge browser
client images with Pantalk Ghost. Ghost runs `pantalkd`, Codex, and Claude
in a persistent graphical agent environment.

The deployment provides:

- An Ergo IRC network persisted in a Docker volume.
- A browser client locked to the local Ergo network.
- A shared `#ghost` channel.
- `codex` and `claude` IRC bots connected through Pantalk.
- Direct-message, mention, and explicit `codex:` or `claude:` routing.

General channel messages do not invoke either agent. Messages from one agent
are also excluded from the other agent's routing rule to prevent recursive
agent conversations.

## Requirements

- Docker Engine
- Docker Compose as the `docker compose` plugin
- Bash and curl
- An AMD64 or ARM64 host with Docker

## Start with the published Ghost image

```bash
make up
```

Open:

- The Lounge: <http://127.0.0.1:9000>
- Ghost: <http://127.0.0.1:6902>

The Lounge runs in public mode and does not require a login. Its connection
screen is locked to the local Ergo server and joins `#ghost` automatically.
Choose a different nickname if `operator` is already connected.

Open **Setup** in the Ghost desktop to authenticate Codex and Claude. After
login, send a direct message to `codex` or `claude`, mention them, or start a
channel message with `codex:` or `claude:`.

Show all local endpoints:

```bash
make urls
```

## Build Ghost locally

Use the repository Dockerfile instead of the published Ghost image:

```bash
make dev
```

`compose.dev.yaml` builds the `ghost` target with the Ghost repository root
as its Docker context. Ghost remains transport-neutral; this deployment
connects Pantalk to the external Ergo container.

## Validate and test

Validate the scripts, rendered Pantalk configuration, and merged Compose
configurations:

```bash
make validate
```

Run a live IRC messaging smoke test:

```bash
make smoke
```

The smoke test verifies both browser endpoints, both configured bots, an
outbound Pantalk message observed on IRC, and an inbound IRC message recorded
by Pantalk. The inbound message does not address an agent, so unauthenticated
harnesses are not invoked during the test.

Build locally, start the deployment, and run the smoke test:

```bash
make test
```

Stop the deployment without deleting data:

```bash
make down
```

## Configuration and state

The first `make up` copies `.env.example` to the ignored `.env` file. Edit it
to change image versions, bind addresses, ports, the IRC channel, or the Ghost
resolution. `make up` renders the Pantalk configuration under the ignored
`.state` directory.

Ergo stores its generated configuration, account data, registered channels,
history, and TLS keys in the `ergo-data` Docker volume. Ghost keeps agent
authentication, Pantalk state, and `/workspace` in separate persistent volumes.

## Security

The IRC, web-client, and Ghost ports bind to `127.0.0.1` by default. The
deployment intentionally uses an open local IRC network and The Lounge public
mode for straightforward local access.

Do not expose these ports to an untrusted network. Ghost's desktop has no
browser password, and the generated agents can write inside `/workspace`
without interactive approval.

For a shared or internet-facing installation, enable Ergo account
authentication and TLS, use The Lounge private mode, add a supported reverse
proxy, and review both upstream projects' production guidance.

## Current messaging coverage

Supported by this deployment:

- Direct messages
- Public channels joined by the bots
- Explicit mentions and name-prefixed invocations
- Conversation isolation by IRC target
- Long-text splitting and plain-text formatting
- Connector reconnection and channel rejoin
- Pantalk-initiated outbound messages

Missing or partial:

- Native IRC threads
- Reactions
- Attachments
- Rich interactive components
- Strong user identity without Ergo account authentication

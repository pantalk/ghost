# Mattermost Deployment

This deployment combines the official Mattermost Team Edition and PostgreSQL
images with Pantalk Ghost. Mattermost provides the collaborative chat
surface. Ghost runs `pantalkd`, Codex, and Claude in one persistent graphical
agent environment.

Provisioning creates:

- An initial Mattermost system administrator.
- A `pantalk` team and `agents` channel.
- `codex` and `claude` Mattermost bot accounts.
- Bot access tokens stored only under the ignored `.state` directory.
- A Pantalk configuration that routes direct messages and explicit mentions to
  the matching agent.

General channel messages do not invoke either agent. This prevents agents from
responding to each other recursively.

## Requirements

- Docker Engine
- Docker Compose as the `docker compose` plugin
- Bash, curl, and OpenSSL
- An AMD64 or ARM64 host with Docker

## Start with the published Ghost image

```bash
make up
```

The first run generates `.env`, starts Mattermost, provisions the users and
bots, and then starts Ghost.

Open:

- Mattermost: <http://127.0.0.1:8065>
- Ghost: <http://127.0.0.1:6902>

Show the generated Mattermost administrator login:

```bash
make credentials
```

Open **Setup** in the Ghost desktop to authenticate Codex and Claude. Their
authentication is kept in persistent Docker volumes. After login, direct
message `codex` or `claude`, or mention `@codex` or `@claude` in the `agents`
channel.

## Build Ghost locally

Use the repository Dockerfile instead of the published Ghost image:

```bash
make dev
```

`compose.dev.yaml` builds the `ghost` target with the Ghost repository root
as its Docker context. This includes local Ghost changes. The Dockerfile still
downloads the Pantalk release selected by `PANTALK_VERSION`; it does not compile
the sibling Pantalk Go source.

## Validate and test

Validate the scripts and merged Compose configurations:

```bash
make validate
```

Run a live messaging smoke test:

```bash
make smoke
```

The smoke test verifies both browser endpoints, both configured bots, an
outbound Pantalk message, and an inbound Mattermost message. It deliberately
uses a normal channel message so unauthenticated agent harnesses are not invoked
during the test.

Build locally, start the deployment, and run the smoke test:

```bash
make test
```

## Configuration and state

The generated `.env` contains the PostgreSQL password and initial Mattermost
administrator password. Back it up with the deployment volumes. Losing it while
retaining the PostgreSQL volume requires manual credential recovery.

Generated bot tokens, the rendered Pantalk configuration, and the temporary
`mmctl` password file live under `.state/`. Both `.env` and `.state/` are
ignored by Git. The `.state` parent directory is private; the nested secrets
directory is mounted read-only so Mattermost's unprivileged user can read the
password during provisioning.

Edit `.env` to change image versions, bind addresses, ports, or initial
resource names. Run `make provision` after changing the Mattermost team or
channel.

Stop the deployment without deleting data:

```bash
make down
```

## Security

Both browser ports bind to `127.0.0.1` by default.

Ghost's KasmVNC desktop has no browser password. Do not expose its port to an
untrusted network. The generated agents can write inside `/workspace` without
interactive approval, so only trusted Mattermost users should be allowed to
message them.

The provisioning process uses Mattermost local administration to create or
repair the initial administrator, then authenticates `mmctl` long enough to
create bots and tokens. Stored `mmctl` credentials are removed when
provisioning finishes.

For an internet-facing Mattermost installation, add TLS and a supported reverse
proxy, replace the local email defaults, and review Mattermost's production
deployment guidance before changing `MATTERMOST_BIND_ADDRESS`.

## Current messaging coverage

Supported by this deployment:

- Direct messages
- Explicit mentions
- Public and private channels where the bots are members
- Thread-isolated Pantalk conversations
- Long text chunking and Mattermost markdown
- Reconnection through the Pantalk Mattermost connector

Missing or partial:

- Mattermost reactions
- Inbound and outbound file attachments
- Rich interactive Mattermost components

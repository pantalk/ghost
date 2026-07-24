# Station Deployments

Deployments combine Pantalk Station with self-hosted messaging systems. Each
deployment uses the messaging system's official container images and the
published Station image. Development overrides build Station directly from
this repository.

The Station image is identical across every deployment below. Only the mounted
Pantalk configuration differs, and the Codex and Claude Code agent definitions
carry across untouched - which is the whole demonstration: the harness does not
change when the platform does.

## Available deployments

| Deployment                         | Status  | Messaging system    |
| ---------------------------------- | ------- | ------------------- |
| [Mattermost](mattermost/README.md) | Initial | Mattermost Team     |
| [Ergo](ergo/README.md)             | Initial | Ergo and The Lounge |

Deployment directories own their Compose files, provisioning, validation,
smoke tests, and operational documentation. They do not publish replacement
images for upstream services.

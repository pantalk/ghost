# Station Deployments

Deployments combine Pantalk Station with self-hosted messaging systems. Each
deployment uses the messaging system's official container images and the
published Station image. Development overrides build Station directly from
this repository.

## Available deployments

| Deployment                         | Status  | Messaging system    |
| ---------------------------------- | ------- | ------------------- |
| [Mattermost](mattermost/README.md) | Initial | Mattermost Team     |
| [Ergo](ergo/README.md)             | Initial | Ergo and The Lounge |

Deployment directories own their Compose files, provisioning, validation,
smoke tests, and operational documentation. They do not publish replacement
images for upstream services.

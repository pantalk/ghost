# Releasing Pantalk Ghost

Pantalk Ghost releases are driven by the `VERSION` file.

## Release process

1. Update `VERSION` with a semantic version without a `v` prefix.
2. Move the relevant entries from `Unreleased` into a matching version section
   in `CHANGELOG.md`.
3. Merge the release change into `main`.
4. CI builds and smoke-tests the Ghost image.
5. After CI succeeds, the tag workflow creates an annotated `v*` tag at the
   exact tested commit.
6. The release workflow publishes the image to
   `ghcr.io/pantalk/ghost`, creates its immutable version tags, and creates a
   matching GitHub Release.

Existing tags and releases are never replaced.

## Image tags

Stable releases publish the following tags:

- `vX.Y.Z`
- `X.Y.Z`
- `X.Y`
- `latest`

Prereleases publish the versioned tags but do not move `latest`.

Each tag is a multi-architecture image supporting `linux/amd64` and
`linux/arm64`. Docker selects the matching image automatically. CI builds and
smoke-tests each architecture on a native GitHub-hosted runner before the
release workflow combines their digests into one manifest.

## Package visibility

The workflow can create and update the GitHub Container Registry package using
the repository's `GITHUB_TOKEN`. After the first publication, an organization
owner must make the package public in GitHub package settings so anyone can pull
it without authentication.

<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->

# teamtype-docker

Unofficial container image for [Teamtype](https://github.com/teamtype/teamtype) (formerly Ethersync) — peer-to-peer, editor-agnostic collaborative editing of local text files.

> **Not affiliated with the Teamtype project.** This repository only packages the official, unmodified release binaries into a container image. Please report Teamtype bugs [upstream](https://github.com/teamtype/teamtype/issues), and packaging bugs here.

The main use case is a [cloud peer](https://teamtype.github.io/teamtype/connection-making.html#cloud-peer): an always-online Teamtype daemon on a server that your team can connect to whenever they like, so everybody's changes end up in one place even when no two people are online at the same time. You work on local files with your own editor; Teamtype synchronizes them with the container in the background.

## What's in the image

| | |
| --- | --- |
| Teamtype | Latest upstream release at build time (official static binary, unmodified) |
| Base image | `alpine:3.22` + `ca-certificates` |
| Platforms | `linux/amd64`, `linux/arm64` |
| Runs as | uid/gid `1000`, non-root |
| Shared directory | `/project` |

## Quick start

First, create the host directory and ensure it is writable by UID 1000:

```bash
mkdir -p project && sudo chown 1000:1000 project
```

Start the container with Docker:

```bash
docker run -d --name teamtype \
  -v "$PWD/project:/project" \
  ghcr.io/watermelon1024/teamtype-docker:latest
```

Or with Compose — copy [docker-compose.yml](docker-compose.yml) and run:

```bash
docker compose up -d
docker compose logs -f
```

The log outputs two ways to connect — a one-time **join code** and a permanent **secret address**:

```console
To connect to you, another person can run:

    teamtype join 5-hamburger-endorse

Secret address: 429e94...0e9819#32374e...4a6789
```

On your machine, create or enter the directory you want to sync:

```bash
mkdir my-project && cd my-project
```

Then connect using either method:

- **Method 1: One-time join code** (quickest for initial setup):

  ```bash
  teamtype join 5-hamburger-endorse
  ```

  Once paired, Teamtype automatically saves the secret address to `.teamtype/config`. For subsequent runs in this directory, simply execute `teamtype join` without arguments.

- **Method 2: Secret address** (for additional teammates or permanent setup):
  Because join codes expire after a single use, other team members can connect directly using the secret address:

  ```bash
  echo "peer = 429e94...0e9819#32374e...4a6789" >> .teamtype/config
  teamtype join
  ```

Files sync automatically on disk, but you can install a [Teamtype editor plugin](https://github.com/teamtype/teamtype#2-install-an-editor-plugin) (Neovim, VS Code/Codium) to see live cursors and peer selections.

## Configuration

The shared directory inside the container is always `/project` — mount it wherever you like on the host. All settings below are optional; the defaults run a `share` daemon.

| Variable | Default | Description |
| --- | --- | --- |
| `TEAMTYPE_COMMAND` | `share` | `share` to host a directory, `join` to connect to somebody else's. |
| `TEAMTYPE_SHOW_SECRET_ADDRESS` | `true` | Print the secret address on startup (`share` only). |
| `TEAMTYPE_NO_JOIN_CODE` | `false` | Skip the one-time Magic Wormhole join code (`share` only). |
| `TEAMTYPE_USERNAME` | unset | Name shown next to this peer's cursor. Falls back to the Git username, then `Anonymous`. |
| `TEAMTYPE_PEER` | unset | Secret address to connect to. Appended to `.teamtype/config` if no `peer` is configured yet. |
| `TEAMTYPE_JOIN_CODE` | unset | One-time join code, used when `TEAMTYPE_COMMAND=join`. |
| `TEAMTYPE_SYNC_VCS` | `false` | Experimental: also synchronise `.git/` and `.jj/`. |
| `TEAMTYPE_EXTRA_ARGS` | unset | Extra flags appended verbatim, e.g. `--iroh-relay https://relay.example.org`. |

Anything you pass after the image name replaces the generated command line, so the CLI stays reachable:

```bash
docker run --rm ghcr.io/watermelon1024/teamtype-docker:latest --help
docker run --rm -v "$PWD/project:/project" ghcr.io/watermelon1024/teamtype-docker:latest \
  join 5-hamburger-endorse --username alice
```

Settings that have no CLI flag (custom relays, `emit_*` toggles) go into `project/.teamtype/config` on the host — see the [configuration docs](https://teamtype.github.io/teamtype/configuration.html).

## File permissions

The container runs as uid/gid `1000` by default and needs read/write access to the mounted directory. Either `chown 1000:1000` the host directory, or set the container user to match your host UID:

```yaml
user: "1001:1001"   # docker-compose.yml, or --user $(id -u):$(id -g)
```

The entrypoint creates `/project/.teamtype/` and sets it to mode `700` before starting the daemon. Both steps are required: Teamtype asks an interactive yes/no question when the directory is missing (impossible in a container), and refuses to start when group or others have any access to the directory holding its editor socket.

## Networking

Teamtype connects peers with [iroh](https://www.iroh.computer/), which binds a random UDP port and does NAT traversal by itself. There is no fixed listening port, so `ports:` mappings are pointless:

- **Bridge networking (default)** works, but Docker's NAT usually defeats hole punching, so traffic falls back to the public iroh relays. Fine for text; adds latency.
- **`network_mode: host`** (Linux only) gives peers a real chance at a direct connection. Recommended on a server.

Outbound access is required to `relay.magic-wormhole.io` (join codes) and the iroh relay/DNS servers. Both can be self-hosted — see [running your own relays](https://teamtype.github.io/teamtype/relays.html) and set them via `TEAMTYPE_EXTRA_ARGS`.

## Persistence

Everything lives in the mounted directory, so backing it up is enough:

| Path | Contents |
| --- | --- |
| `project/` | Your actual files. |
| `project/.teamtype/key` | The node's private key. **Delete this and the secret address changes**, and every peer has to reconnect. |
| `project/.teamtype/doc` | The CRDT history, used to merge edits made while peers were offline. |
| `project/.teamtype/config` | Username, peer address, relay settings. |

`docker stop` sends `SIGTERM`, which the daemon handles and shuts down cleanly.

For project history, you can initialize a Git repository inside the shared directory. Teamtype ignores `.git/` by default to avoid repository conflicts across peers (set `TEAMTYPE_SYNC_VCS=true` to synchronize it) — see [working with Git](https://teamtype.github.io/teamtype/git-integration.html).

## Security notes

- **A secret address is a password.** Anyone holding it gets read/write access to the whole shared directory. It appears in `docker logs`, so treat container logs as secrets, and prefer `TEAMTYPE_SHOW_SECRET_ADDRESS=false` once your peers are set up.
- A join code is single-use, but valid for anybody who sees it first. Send it over a channel you trust.
- Teamtype synchronises the whole directory tree. Do not point it at a directory containing credentials you would not hand to every peer.

## Building it yourself

```bash
# Build using the default version pinned in Dockerfile:
docker build -t teamtype-docker .

# Or build a specific upstream release:
docker build -t teamtype-docker --build-arg TEAMTYPE_VERSION=0.9.2 .
```

The published container images automatically track upstream releases: CI resolves the latest release from GitHub, builds images tagged with `:latest` and `:<teamtype-version>`, and runs scheduled weekly rebuilds for security updates. `ARG TEAMTYPE_VERSION` in the [Dockerfile](Dockerfile) serves as the default fallback for local builds.

## Where the binary comes from

The image packages the official static release binary downloaded directly over HTTPS from GitHub at build time. Upstream currently does not publish checksums or cryptographic signatures.

To provide provenance and an audit trail, the build records the computed SHA256 checksums inside `/usr/share/doc/teamtype/SHA256SUMS`:

```console
$ docker run --rm --entrypoint cat ghcr.io/watermelon1024/teamtype-docker:latest \
    /usr/share/doc/teamtype/SHA256SUMS
# teamtype v0.9.2 for amd64, downloaded 2026-07-09T04:11:07Z
# https://github.com/teamtype/teamtype/releases/download/v0.9.2/teamtype-x86_64-linux-static.tar.gz
d8fff3ad796db2868d5d342727cc7fe6a160e28ae24aed5838e0175fd7c1efac  teamtype-x86_64-linux-static.tar.gz
d8b9ff78561100637bf180fd9101649b1a97c0d445850206c531e512983d16cd  teamtype
```

These checksums are also published to the summary page of each [GitHub Actions run](actions/workflows/docker.yml). Because builds download assets fresh rather than using cached layers, any upstream replacement of assets can be verified against previous run records.

## Tags

| Tag | Meaning |
| --- | --- |
| `latest` | Newest build. Follows upstream, so the Teamtype version inside it changes over time. |
| `0.9.2` | A specific Teamtype version. Published automatically whenever upstream releases. |
| `v1.2.3` | A release tag of *this* packaging repository. |

Pin `:<teamtype-version>` if you do not want the daemon to change version underneath you.

## License

Teamtype is free software licensed under the **GNU AGPL-3.0-or-later**, copyright its authors. Everything in this repository is published under the same license — see [LICENSE](LICENSE).

Because this image contains an AGPL binary, distributing it means conveying AGPL software, and the corresponding source has to be available to anyone who receives the image. The packaged binary is the **unmodified** official release of a specific upstream tag, and every image records which one:

```console
$ docker inspect --format '{{index .Config.Labels "org.teamtype.upstream.source"}}' \
    ghcr.io/watermelon1024/teamtype-docker:latest
https://github.com/teamtype/teamtype/tree/v0.9.2
```

The image labels `org.teamtype.upstream.source` and `org.teamtype.upstream.source.tarball` point directly to the exact upstream source code and archive for each release. The upstream license text is also provided inside the image at `/usr/share/doc/teamtype/LICENSE.md`.

## Credits

All the actual work is done by the [Teamtype authors](https://github.com/teamtype/teamtype/graphs/contributors). If you find this useful, go [support them](https://teamtype.github.io/teamtype/).

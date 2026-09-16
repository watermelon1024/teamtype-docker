# syntax=docker/dockerfile:1
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Unofficial container image packaging official static binaries for Teamtype.

ARG ALPINE_VERSION=3.22
ARG TEAMTYPE_VERSION=0.9.2


# Fetch stage: runs on the native build platform to avoid QEMU emulation overhead
FROM --platform=${BUILDPLATFORM} alpine:${ALPINE_VERSION} AS fetch

ARG TEAMTYPE_VERSION
ARG TARGETARCH

RUN apk add --no-cache curl tar

# Upstream publishes neither checksums nor signatures; record download hashes inside image for auditability
WORKDIR /out
RUN set -eu; \
    case "${TARGETARCH}" in \
    amd64) asset="teamtype-x86_64-linux-static.tar.gz" ;; \
    arm64) asset="teamtype-aarch64-linux-static.tar.gz" ;; \
    *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/teamtype/teamtype/releases/download/v${TEAMTYPE_VERSION}/${asset}"; \
    echo "Downloading ${url}"; \
    curl -fsSL --retry 3 -o "${asset}" "${url}"; \
    tar -xzf "${asset}"; \
    chmod 0755 teamtype; \
    { echo "# teamtype v${TEAMTYPE_VERSION} for ${TARGETARCH}, downloaded $(date -u +%FT%TZ)"; \
    echo "# ${url}"; \
    sha256sum "${asset}" teamtype; \
    } | tee SHA256SUMS; \
    rm "${asset}"


# Runtime stage
FROM alpine:${ALPINE_VERSION}

ARG TEAMTYPE_VERSION

# ca-certificates is needed for TLS connections to Magic Wormhole and iroh relays
RUN apk add --no-cache ca-certificates \
    && addgroup -g 1000 teamtype \
    && adduser -D -u 1000 -G teamtype -h /home/teamtype teamtype \
    && mkdir -p /project \
    && chown teamtype:teamtype /project

COPY --from=fetch /out/teamtype    /usr/local/bin/teamtype
COPY --from=fetch /out/SHA256SUMS  /usr/share/doc/teamtype/SHA256SUMS
COPY --from=fetch /out/LICENSE.md  /usr/share/doc/teamtype/LICENSE.md
COPY --from=fetch /out/README.md   /usr/share/doc/teamtype/README.md
COPY docker-entrypoint.sh          /usr/local/bin/docker-entrypoint.sh

ENV HOME=/home/teamtype \
    TEAMTYPE_COMMAND=share \
    TEAMTYPE_SHOW_SECRET_ADDRESS=true

USER teamtype
WORKDIR /project

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD test -S /project/.teamtype/socket || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]

LABEL org.opencontainers.image.title="teamtype" \
    org.opencontainers.image.description="Unofficial container image for Teamtype, peer-to-peer collaborative editing of local text files" \
    org.opencontainers.image.version="${TEAMTYPE_VERSION}" \
    org.opencontainers.image.licenses="AGPL-3.0-or-later" \
    org.opencontainers.image.url="https://github.com/teamtype/teamtype" \
    org.opencontainers.image.documentation="https://teamtype.github.io/teamtype/" \
    org.opencontainers.image.vendor="Unofficial packaging; not affiliated with the Teamtype project" \
    org.teamtype.upstream.version="v${TEAMTYPE_VERSION}" \
    org.teamtype.upstream.source="https://github.com/teamtype/teamtype/tree/v${TEAMTYPE_VERSION}" \
    org.teamtype.upstream.source.tarball="https://github.com/teamtype/teamtype/archive/refs/tags/v${TEAMTYPE_VERSION}.tar.gz"

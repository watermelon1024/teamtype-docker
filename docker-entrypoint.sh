#!/bin/sh
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Prepares the shared directory and launches the Teamtype daemon.
# Translates TEAMTYPE_* environment variables into CLI flags if no arguments are given.

set -eu

# Escape hatch: `docker run ... sh` or custom commands execute verbatim for debugging
case "${1:-}" in
    sh | ash | /*)
        exec "$@"
        ;;
esac

DIR=/project

log() { printf '[entrypoint] %s\n' "$*" >&2; }

is_true() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1 | true | yes | y | on) return 0 ;;
        *) return 1 ;;
    esac
}

# Teamtype asks an interactive y/n question if .teamtype/ is missing,
# and hard-fails if permissions on the socket directory are broader than 700.
mkdir -p "$DIR/.teamtype" 2>/dev/null || true
chmod 700 "$DIR/.teamtype" 2>/dev/null || true

# Test actual writability: `test -w` only checks permission bits and falsely passes on read-only mounts
if ! touch "$DIR/.teamtype/.write-test" 2>/dev/null; then
    log "ERROR: cannot write to '$DIR/.teamtype' as uid=$(id -u) gid=$(id -g)."
    log "       The mount has to be writable by that user -- either chown the host directory to 1000:1000,"
    log "       or run the container as its owner, e.g. \`user: \"\$(id -u):\$(id -g)\"\`."
    exit 1
fi
rm -f "$DIR/.teamtype/.write-test"

# `peer` has no CLI flag in upstream Teamtype, so append to config if not configured yet
CONFIG="$DIR/.teamtype/config"
if [ -n "${TEAMTYPE_PEER:-}" ] && ! grep -qs '^[[:space:]]*peer[[:space:]]*=' "$CONFIG"; then
    log "Adding the peer address from TEAMTYPE_PEER to $CONFIG"
    printf 'peer = %s\n' "$TEAMTYPE_PEER" >>"$CONFIG"
fi

# Build command line from environment variables when started without arguments
if [ "$#" -eq 0 ]; then
    COMMAND="${TEAMTYPE_COMMAND:-share}"
    set -- "$COMMAND"

    if [ "$COMMAND" = "join" ] && [ -n "${TEAMTYPE_JOIN_CODE:-}" ]; then
        set -- "$@" "$TEAMTYPE_JOIN_CODE"
    fi

    if [ "$COMMAND" = "share" ]; then
        if is_true "${TEAMTYPE_SHOW_SECRET_ADDRESS:-true}"; then
            set -- "$@" --show-secret-address
        fi
        if is_true "${TEAMTYPE_NO_JOIN_CODE:-}"; then
            set -- "$@" --no-join-code
        fi
    fi

    if [ -n "${TEAMTYPE_USERNAME:-}" ]; then
        set -- "$@" --username "$TEAMTYPE_USERNAME"
    fi

    if is_true "${TEAMTYPE_SYNC_VCS:-}"; then
        set -- "$@" --sync-vcs
    fi

    set -- "$@" --directory "$DIR"

    # shellcheck disable=SC2086
    set -- "$@" ${TEAMTYPE_EXTRA_ARGS:-}
fi

# Hand over PID 1 to the daemon so it receives SIGTERM on `docker stop`
log "Running: teamtype $*"
exec teamtype "$@"

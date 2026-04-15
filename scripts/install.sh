#!/bin/sh
# install.sh — download and install the distill binary from GitHub Releases.
#
# Usage:
#   curl -sfL https://raw.githubusercontent.com/damnhandy/distill/main/scripts/install.sh | sh
#
# Options (pass after '--' when piping through sh -s):
#   -b <dir>    Installation directory. Default: /usr/local/bin
#   -d          Enable debug output
#   <version>   Tag to install (e.g. v1.0.0). Default: latest release
#
# Examples:
#   # Install latest to /usr/local/bin (may need sudo)
#   curl -sfL https://raw.githubusercontent.com/damnhandy/distill/main/scripts/install.sh | sudo sh
#
#   # Install specific version to ~/bin (no sudo needed)
#   curl -sfL https://raw.githubusercontent.com/damnhandy/distill/main/scripts/install.sh | sh -s -- -b ~/bin v1.2.3

set -e

REPO="damnhandy/distill"
BINARY="distill"
GITHUB_RELEASES="https://github.com/${REPO}/releases"
GITHUB_API="https://api.github.com/repos/${REPO}/releases"

# ── Defaults ─────────────────────────────────────────────────────────────────

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
VERSION=""
DEBUG=""

# ── Helpers ───────────────────────────────────────────────────────────────────

log()   { printf '%s\n' "$*" >&2; }
debug() { [ -n "$DEBUG" ] && printf 'debug: %s\n' "$*" >&2 || true; }
fatal() { log "error: $*"; exit 1; }

# http_get <url> <output_file>
http_get() {
    url="$1"
    dest="$2"
    if command -v curl >/dev/null 2>&1; then
        debug "curl -fsSL $url"
        curl -fsSL "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        debug "wget -q $url"
        wget -q "$url" -O "$dest"
    else
        fatal "neither curl nor wget found; please install one and retry"
    fi
}

# http_get_stdout <url>
http_get_stdout() {
    url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O -
    else
        fatal "neither curl nor wget found; please install one and retry"
    fi
}

# ── Platform detection ────────────────────────────────────────────────────────

detect_os() {
    os="$(uname -s)"
    case "$os" in
        Linux)  printf 'linux' ;;
        Darwin) printf 'darwin' ;;
        *)      fatal "unsupported OS: $os" ;;
    esac
}

detect_arch() {
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)           printf 'amd64' ;;
        aarch64|arm64)          printf 'arm64' ;;
        *)                      fatal "unsupported architecture: $arch" ;;
    esac
}

# ── Version resolution ────────────────────────────────────────────────────────

latest_version() {
    debug "querying GitHub API for latest release"
    ver="$(http_get_stdout "${GITHUB_API}/latest" | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
    [ -n "$ver" ] || fatal "could not determine latest release; check https://github.com/${REPO}/releases"
    printf '%s' "$ver"
}

# ── Checksum verification ─────────────────────────────────────────────────────

verify_checksum() {
    archive="$1"
    checksum_file="$2"
    archive_name="$(basename "$archive")"

    expected="$(grep " ${archive_name}$" "$checksum_file" | awk '{print $1}')"
    [ -n "$expected" ] || fatal "checksum entry for ${archive_name} not found in checksums.txt"

    if command -v sha256sum >/dev/null 2>&1; then
        actual="$(sha256sum "$archive" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
    else
        log "warning: no sha256 tool found; skipping checksum verification"
        return 0
    fi

    debug "expected: $expected"
    debug "actual:   $actual"

    [ "$expected" = "$actual" ] || fatal "checksum mismatch for ${archive_name}"
    debug "checksum verified"
}

# ── Argument parsing ──────────────────────────────────────────────────────────

parse_args() {
    while getopts ":b:dh" opt; do
        case "$opt" in
            b) INSTALL_DIR="$OPTARG" ;;
            d) DEBUG=1 ;;
            h)
                log "Usage: install.sh [-b <dir>] [-d] [<version>]"
                log "  -b  Installation directory (default: /usr/local/bin)"
                log "  -d  Enable debug output"
                log "  -h  Show this help"
                exit 0
                ;;
            :) fatal "option -${OPTARG} requires an argument" ;;
            ?) fatal "unknown option: -${OPTARG}" ;;
        esac
    done
    shift $((OPTIND - 1))
    [ -n "$1" ] && VERSION="$1"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"

    OS="$(detect_os)"
    ARCH="$(detect_arch)"

    if [ -z "$VERSION" ]; then
        VERSION="$(latest_version)"
    fi

    # Strip leading 'v' for the archive name (goreleaser uses the tag as-is in URLs
    # but the archive name uses the bare version).
    BARE_VERSION="${VERSION#v}"

    ARCHIVE_NAME="${BINARY}_${OS}_${ARCH}"
    ARCHIVE_FILE="${ARCHIVE_NAME}.tar.gz"
    DOWNLOAD_BASE="${GITHUB_RELEASES}/download/${VERSION}"

    log "Installing ${BINARY} ${VERSION} (${OS}/${ARCH}) → ${INSTALL_DIR}"

    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    log "Downloading archive..."
    http_get "${DOWNLOAD_BASE}/${ARCHIVE_FILE}" "${tmpdir}/${ARCHIVE_FILE}"

    log "Downloading checksums..."
    http_get "${DOWNLOAD_BASE}/checksums.txt" "${tmpdir}/checksums.txt"

    log "Verifying checksum..."
    verify_checksum "${tmpdir}/${ARCHIVE_FILE}" "${tmpdir}/checksums.txt"

    log "Extracting..."
    tar -xzf "${tmpdir}/${ARCHIVE_FILE}" -C "${tmpdir}"

    # Ensure the install directory exists.
    mkdir -p "${INSTALL_DIR}"

    log "Installing to ${INSTALL_DIR}/${BINARY}..."
    install -m 755 "${tmpdir}/${BINARY}" "${INSTALL_DIR}/${BINARY}"

    log ""
    log "${BINARY} ${VERSION} installed successfully."
    log "Run: ${INSTALL_DIR}/${BINARY} --help"
}

main "$@"

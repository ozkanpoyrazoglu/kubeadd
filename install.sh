#!/bin/sh
# Install kubeadd on macOS or Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/ozkanpoyrazoglu/kubeadd/main/install.sh | sh
#
# Environment variables:
#   PREFIX=/usr/local        install into $PREFIX/bin (default: ~/.local, no sudo needed)
#   KUBEADD_VERSION=v2.0.0   install a tag, branch or commit (default: main)
#
# Uninstall:
#   curl -fsSL https://raw.githubusercontent.com/ozkanpoyrazoglu/kubeadd/main/install.sh | sh -s -- --uninstall
set -eu

REPO="ozkanpoyrazoglu/kubeadd"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
TARGET="$BIN_DIR/kubeadd"

info() { printf '%s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*"; }
fail() { printf '❌ %s\n' "$*" >&2; exit 1; }

usage() {
    info "Usage: install.sh [--uninstall]"
    info "  PREFIX=/usr/local        install into \$PREFIX/bin (default: ~/.local)"
    info "  KUBEADD_VERSION=v2.0.0   install a tag, branch or commit (default: main)"
}

uninstall() {
    if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
        rm -f "$TARGET"
        info "🗑️  Removed $TARGET"
    else
        info "kubeadd is not installed in $BIN_DIR"
    fi
}

download() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        fail "curl or wget is required to download kubeadd"
    fi
}

shell_rc() {
    case "${SHELL:-}" in
        */zsh) echo "$HOME/.zshrc" ;;
        */bash) if [ "$(uname -s)" = Darwin ]; then echo "$HOME/.bash_profile"; else echo "$HOME/.bashrc"; fi ;;
        *) echo "$HOME/.profile" ;;
    esac
}

case "${1:-}" in
    "") ;;
    --uninstall) uninstall; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "Unknown option: $1" ;;
esac

# Requirements
command -v python3 >/dev/null 2>&1 \
    || fail "python3 is required (macOS: xcode-select --install or brew install python, Linux: your package manager)"
python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' \
    || fail "Python 3.8 or newer is required, found $(python3 --version 2>&1)"
if ! command -v kubectl >/dev/null 2>&1; then
    warn "kubectl was not found in PATH; kubeadd needs it (https://kubernetes.io/docs/tasks/tools/)"
fi

# Fetch kubeadd.py: from this checkout when run as a file inside the repo, otherwise from GitHub.
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
script_dir=$(dirname "$0")
if [ -z "${KUBEADD_VERSION:-}" ] && [ -f "$0" ] && [ -f "$script_dir/kubeadd.py" ]; then
    info "📦 Installing from $(cd "$script_dir" && pwd)"
    cp "$script_dir/kubeadd.py" "$tmp_dir/kubeadd"
else
    version="${KUBEADD_VERSION:-main}"
    info "📦 Downloading kubeadd ($version)"
    download "https://raw.githubusercontent.com/$REPO/$version/kubeadd.py" "$tmp_dir/kubeadd" \
        || fail "Download failed; check that '$version' exists in https://github.com/$REPO"
fi
installed_version=$(python3 "$tmp_dir/kubeadd" --version 2>/dev/null) \
    || fail "The downloaded file is not a working kubeadd"

# Install
mkdir -p "$BIN_DIR" 2>/dev/null && [ -w "$BIN_DIR" ] \
    || fail "Cannot write to $BIN_DIR; run with sudo or choose another PREFIX"
chmod 755 "$tmp_dir/kubeadd"
mv -f "$tmp_dir/kubeadd" "$TARGET"
info "✅ Installed $installed_version to $TARGET"

# Hints
case ":$PATH:" in
    *":$BIN_DIR:"*)
        found=$(command -v kubeadd 2>/dev/null || true)
        if [ -n "$found" ] && [ "$found" != "$TARGET" ]; then
            warn "'kubeadd' currently resolves to $found, which comes before $TARGET in PATH"
        fi
        ;;
    *)
        info "👉 $BIN_DIR is not in your PATH. Add it with:"
        case "${SHELL:-}" in
            */fish) info "   fish_add_path $BIN_DIR" ;;
            *) info "   echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> $(shell_rc) && . $(shell_rc)" ;;
        esac
        ;;
esac
for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [ -f "$rc" ] && grep -q '^[[:space:]]*alias kubeadd=' "$rc"; then
        warn "$rc defines an alias for kubeadd that overrides this install; remove it to use $TARGET"
    fi
done
info "🚀 Run 'kubeadd -h' to get started"

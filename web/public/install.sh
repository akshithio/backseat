#!/bin/sh
# Installs backseat: downloads the signed, notarized binary and adds the
# backseat plugin (MCP server + skill) to Claude Code. No Xcode needed.
#   curl -fsSL https://backseat.akshith.io/install.sh | sh
set -e

VERSION="${BACKSEAT_VERSION:-0.1.0}"
DIR="${BACKSEAT_HOME:-$HOME/.backseat}"
BIN="$DIR/bin/backseat"
URL="https://github.com/akshithio/backseat/releases/download/v$VERSION/backseat-$VERSION-macos.zip"

[ "$(uname)" = "Darwin" ] || { echo "backseat runs on macOS only." >&2; exit 1; }
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || { echo "backseat needs macOS 14 or later." >&2; exit 1; }

echo "downloading backseat $VERSION"
TMP=$(mktemp -d)
curl -fsSL "$URL" -o "$TMP/backseat.zip"
curl -fsSL "$URL.sha256" -o "$TMP/backseat.zip.sha256"
WANT=$(awk '{ print $1 }' "$TMP/backseat.zip.sha256")
GOT=$(shasum -a 256 "$TMP/backseat.zip" | awk '{ print $1 }')
[ "$WANT" = "$GOT" ] || { echo "checksum mismatch; not installing" >&2; exit 1; }
mkdir -p "$DIR/bin"
ditto -x -k "$TMP/backseat.zip" "$DIR/bin"
echo "$VERSION" > "$DIR/bin/VERSION"
rm -rf "$TMP"

if command -v claude >/dev/null 2>&1; then
  # Earlier installs registered the server and copied the skill by hand; the
  # plugin replaces both. Only undo registrations that point at this folder.
  if claude mcp get backseat 2>/dev/null | grep -q "$DIR"; then
    claude mcp remove -s user backseat >/dev/null 2>&1 || true
    rm -rf "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/backseat"
  fi
  claude plugin marketplace add akshithio/backseat >/dev/null
  claude plugin install backseat@backseat >/dev/null
  echo "added the backseat plugin (server + skill) to Claude Code; restart Claude Code to load it"
else
  echo "installed $BIN; add it to your MCP client as a stdio server"
fi
echo "the first time it runs, macOS asks you to allow Accessibility and Screen Recording for backseat"

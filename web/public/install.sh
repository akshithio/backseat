#!/bin/sh
# Installs backseat: builds the MCP server from source and adds it to Claude Code.
#   curl -fsSL https://backseat.akshith.io/install.sh | sh
set -e

DIR="${BACKSEAT_DIR:-$HOME/.backseat}"
REPO="${BACKSEAT_REPO:-https://github.com/akshithio/backseat}"

[ "$(uname)" = "Darwin" ] || { echo "backseat runs on macOS only." >&2; exit 1; }
command -v swift >/dev/null 2>&1 || {
  echo "backseat is built with Swift. Install the Command Line Tools first: xcode-select --install" >&2
  exit 1
}

if [ -d "$DIR/.git" ]; then
  echo "updating $DIR"
  git -C "$DIR" pull --ff-only --quiet
else
  echo "downloading backseat to $DIR"
  git clone --quiet --depth 1 "$REPO" "$DIR"
fi

echo "building (this takes a minute the first time)"
LOG="$(mktemp)"
if ! swift build -c release --package-path "$DIR" >"$LOG" 2>&1; then
  cat "$LOG" >&2
  echo "the build failed; the output is above" >&2
  exit 1
fi
rm -f "$LOG"
BIN="$DIR/.build/release/backseat"

if command -v claude >/dev/null 2>&1; then
  claude mcp remove -s user backseat >/dev/null 2>&1 || true
  claude mcp add -s user backseat -- "$BIN" >/dev/null
  echo "added backseat to Claude Code"
else
  echo "built $BIN; add it to your MCP client as a stdio server"
fi
echo "the first time it runs, macOS asks to allow Accessibility and Screen Recording"

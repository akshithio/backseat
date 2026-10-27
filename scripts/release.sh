#!/bin/zsh
# Builds, signs, notarizes and publishes a backseat release, then updates the
# Homebrew tap.
#   scripts/release.sh 0.1.0
# Needs a Developer ID Application certificate, a notarytool keychain profile
# (BACKSEAT_NOTARY_PROFILE, default macid-notary) and gh logged in.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
PROFILE="${BACKSEAT_NOTARY_PROFILE:-macid-notary}"
TAP="${BACKSEAT_TAP:-akshithio/homebrew-tap}"
die() { echo "release: $*" >&2; exit 1; }

IDENTITY=$(security find-identity -v -p codesigning | awk '/Developer ID Application/ { print $2; exit }')
[[ -n "$IDENTITY" ]] || die "no Developer ID Application certificate in the keychain"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || die "no notarytool profile '$PROFILE'. Run: xcrun notarytool store-credentials $PROFILE --apple-id <you> --team-id <TEAMID>"
gh auth status >/dev/null 2>&1 || die "gh isn't logged in: gh auth login"
[[ -z "$(git status --porcelain -- Sources Package.swift scripts)" ]] || die "uncommitted changes in Sources, Package.swift or scripts"

# The version lives in the server's handshake and in the embedded Info.plist.
grep -q "version: \"$VERSION\"" Sources/backseat/main.swift || die "Sources/backseat/main.swift isn't at $VERSION"
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" scripts/release/Info.plist | grep -qx "$VERSION" \
    || die "scripts/release/Info.plist isn't at $VERSION"

echo "building universal binary"
swift build -c release --arch arm64 --arch x86_64 >/dev/null
BIN=.build/apple/Products/Release/backseat
OUT=.build/dist
rm -rf "$OUT" && mkdir -p "$OUT"
cp "$BIN" "$OUT/backseat"

echo "signing"
codesign --force --timestamp --options runtime --identifier dev.backseat.backseat \
    --entitlements scripts/release/backseat.entitlements --sign "$IDENTITY" "$OUT/backseat"
codesign --verify --strict "$OUT/backseat"

ZIP="$OUT/backseat-$VERSION-macos.zip"
(cd "$OUT" && ditto -c -k backseat "$(basename "$ZIP")")
echo "notarizing (a few minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait | tee "$OUT/notary.log"
grep -q "status: Accepted" "$OUT/notary.log" || die "notarization wasn't accepted; see $OUT/notary.log"
SHA=$(shasum -a 256 "$ZIP" | awk '{ print $1 }')
echo "$SHA  $(basename "$ZIP")" > "$ZIP.sha256"

echo "publishing v$VERSION"
git tag -f "v$VERSION"
git push -f origin "v$VERSION"
gh release delete "v$VERSION" --yes >/dev/null 2>&1 || true
gh release create "v$VERSION" "$ZIP" "$ZIP.sha256" --title "backseat $VERSION" \
    --notes "Signed and notarized universal binary for macOS 14 or later. Install: \`brew install akshithio/tap/backseat\` (or see the README)."

echo "updating $TAP"
TAPDIR=$(mktemp -d)
gh repo view "$TAP" >/dev/null 2>&1 || gh repo create "$TAP" --public --description "Homebrew formulae for backseat" >/dev/null
gh repo clone "$TAP" "$TAPDIR" -- --quiet 2>/dev/null || git -C "$TAPDIR" init -q
mkdir -p "$TAPDIR/Formula"
cat > "$TAPDIR/Formula/backseat.rb" <<RUBY
class Backseat < Formula
  desc "Computer use for macOS that doesn't take over your screen (MCP server)"
  homepage "https://backseat.akshith.io"
  url "https://github.com/akshithio/backseat/releases/download/v$VERSION/backseat-$VERSION-macos.zip"
  sha256 "$SHA"
  version "$VERSION"
  license "MIT"

  depends_on macos: :sonoma

  def install
    bin.install "backseat"
  end

  def caveats
    <<~EOS
      Add it to Claude Code:
        claude mcp add -s user backseat -- #{opt_bin}/backseat
      The first time it runs, macOS asks you to allow Accessibility and Screen Recording for backseat.
    EOS
  end

  test do
    assert_predicate bin/"backseat", :executable?
  end
end
RUBY
git -C "$TAPDIR" add Formula/backseat.rb
git -C "$TAPDIR" commit -q -m "backseat $VERSION" || true
git -C "$TAPDIR" branch -M main
git -C "$TAPDIR" remote get-url origin >/dev/null 2>&1 || git -C "$TAPDIR" remote add origin "https://github.com/$TAP.git"
git -C "$TAPDIR" push -q -u origin main
echo "done: https://github.com/akshithio/backseat/releases/tag/v$VERSION"

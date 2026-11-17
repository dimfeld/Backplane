#!/bin/sh
# Install a personal_mac release artifact beside the standard app.
set -eu

fail() { echo "install-personal-mac: $*" >&2; exit 1; }
[ "$#" -eq 1 ] || fail "usage: $0 path/to/backplane-*-darwin-arm64-native.tar.gz"
[ "$(uname -s)-$(uname -m)" = Darwin-arm64 ] || fail "use this installer on an Apple Silicon Mac"
[ -f "$1" ] || fail "archive not found: $1"

prefix="$HOME/Library/Application Support/Backplane Fork"
apps="$HOME/Applications"
app="$apps/Backplane Fork.app"
mkdir -p "$prefix/builds" "$apps"

stage=$(mktemp -d "$prefix/.install.XXXXXX")
app_stage=
trap 'rm -rf "$stage"; if [ -n "$app_stage" ]; then rm -rf "$app_stage"; fi' EXIT
tar -xzf "$1" -C "$stage"
bundle="$stage/Backplane Fork.app"
for bin in backplane backplane-hub backplane-gpui; do
  [ -x "$stage/$bin" ] || fail "archive is missing $bin"
done
[ -x "$bundle/Contents/MacOS/Backplane" ] || fail "build the archive with the personal_mac option"
[ "$(plutil -extract CFBundleIdentifier raw -o - "$bundle/Contents/Info.plist")" = dev.dimfeld.backplane ] ||
  fail "the archive has the wrong app bundle ID"
codesign --verify --strict "$bundle"
commit=$(cat "$stage/COMMIT")
case "$commit" in
  ""|*[!0-9a-f]*) fail "invalid archive commit" ;;
esac

# Each install gets its own build directory so an open client can keep reading its assets.
build=$(mktemp -d "$prefix/builds/$commit.XXXXXX")
mv "$stage"/* "$build/"
app_stage=$(mktemp -d "$apps/.Backplane-Fork.XXXXXX")
cp -R "$build/Backplane Fork.app" "$app_stage/"
if [ -e "$app" ]; then mv "$app" "$app_stage/previous.app"; fi
if ! mv "$app_stage/Backplane Fork.app" "$app"; then
  if [ -e "$app_stage/previous.app" ]; then mv "$app_stage/previous.app" "$app"; fi
  fail "could not install the Finder app"
fi

cp "$build/backplane" "$stage/backplane"
mv -f "$stage/backplane" "$prefix/backplane"
printf '%s\n' "${build##*/}" > "$stage/CURRENT"
mv -f "$stage/CURRENT" "$prefix/CURRENT"
printf 'Installed %s\n' "$app"

#!/bin/sh
# Add the embedded Chromium runtime and the signed Finder launcher to a package.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
client_build=${1:?client release directory}
package=${2:?package directory}
version=${3:?version}
shift 3

framework=$(find "$client_build/build" -path '*cef-dll-sys*' -type d -name 'Chromium Embedded Framework.framework' -print -quit)
[ -n "$framework" ] || { echo "package-mac-runtime: Chromium framework missing from $client_build" >&2; exit 1; }
"$here/cef-runtime-files.sh" "$(dirname "$framework")" "$package" macos
"$here/cef-mac-helpers.sh" "$package" "$client_build/backplane-cef-helper"
"$here/mac-app.sh" "$package" "$version" "$@"

app=Backplane.app
[ "${1:-}" != --personal ] || app="Backplane Fork.app"
codesign --verify --strict "$package/$app"

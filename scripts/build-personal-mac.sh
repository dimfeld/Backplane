#!/usr/bin/env bash
# Build the personal Apple Silicon archive from this checkout.
set -euo pipefail

usage() {
  echo "Usage: $0 [output-directory]"
  echo "Build the personal Apple Silicon archive. The default output directory is dist/."
}
fail() { echo "build-personal-mac: $*" >&2; exit 1; }
if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
[[ $# -le 1 ]] || { usage >&2; exit 2; }
[[ $(uname -s)-$(uname -m) == Darwin-arm64 ]] || fail "use an Apple Silicon Mac"

root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$root/dist}
mkdir -p "$out"
out=$(cd "$out" && pwd)
# The other macOS build scripts use this lock on the build machine.
exec lockf -k /tmp/bp-mac-heavy.lockf bash -s -- "$root" "$out" <<'BUILD'
set -euo pipefail

root=$1
out=$2
cd "$root"
fail() { echo "build-personal-mac: $*" >&2; exit 1; }

for tool in cargo rustc bun cmake ninja python3 cargo-about; do
  command -v "$tool" >/dev/null || fail "$tool is required (see docs/install.md)"
done
xcrun --find clang >/dev/null || fail "install the Xcode Command Line Tools"
[[ $(rustc -vV) == *'host: aarch64-apple-darwin'* ]] || fail "use a native Apple Silicon Rust toolchain"
bun_version=$(tr -d '[:space:]' < deploy/bun-version)
[[ $(bun --version) == "$bun_version" ]] || fail "use Bun $bun_version"
[[ $(cargo-about --version) == 'cargo-about 0.9.3' ]] || fail "use cargo-about 0.9.3"

# Use the macOS lock above in place of cargo-q's Linux build-slot lock.
export BQ_HELD=1 BP_NO_BOAT=1
export MACOSX_DEPLOYMENT_TARGET=13.0
export BACKPLANE_COMMIT=$(git rev-parse --short HEAD)
unset BACKPLANE_TELEMETRY_URL BACKPLANE_TELEMETRY_KEY BACKPLANE_TELEMETRY_KID
jobs=${JOBS:-4}
export JOBS="$jobs" CMAKE_BUILD_PARALLEL_LEVEL="$jobs"
version=$(awk -F '"' '/^version = / {print $2; exit}' native/host/Cargo.toml)
archive="$out/backplane-v$version-$BACKPLANE_COMMIT-darwin-arm64-native.tar.gz"

# shellcheck source=scripts/lib-bptmp.sh
source scripts/lib-bptmp.sh
stage=$(mktemp -d "$BP_TMP/personal-mac.XXXXXX")
archive_tmp=
trap 'rm -rf "$stage"; if [[ -n "$archive_tmp" ]]; then rm -f "$archive_tmp"; fi' EXIT
package="$stage/package"
mkdir "$package"

build() (
  crate=$1
  shift
  cd "$root/native/$crate"
  export CARGO_TARGET_DIR="$PWD/target"
  "$root/scripts/cargo-q" build --locked --release --jobs "$jobs" "$@"
)
build host --bin backplane-hub --bin bp-sh
build gpui --features cef
build guard --bin backplane
build voice --bin backplane-voice

cp native/host/target/release/backplane-hub native/guard/target/release/backplane \
   native/gpui/target/release/backplane-gpui native/voice/target/release/backplane-voice "$package/"
cp native/voice/vad/silero_vad.onnx "$package/"
echo "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6  $package/silero_vad.onnx" | shasum -a 256 -c -
(cd tools/browser && bun install --frozen-lockfile && bun build.ts "$package/backplane-browser")
MACOSX_DEPLOYMENT_TARGET=12.0 STATIC=1 scripts/build-step2glb.sh "$package/backplane-step2glb"
scripts/package-mac-runtime.sh native/gpui/target/release "$package" "$version" --personal
cp -R assets "$package/assets"
scripts/build-kistack.sh "$package/kistack"
git rev-parse HEAD > "$package/COMMIT"
scripts/rust-licenses.sh darwin-arm64 "$stage/rust-licenses"
scripts/licenses.sh "$package" darwin-arm64 "$stage/rust-licenses"

archive_tmp=$(mktemp "$out/.backplane.XXXXXX")
tar -czf "$archive_tmp" -C "$package" .
mv -f "$archive_tmp" "$archive"
echo "$archive"
BUILD

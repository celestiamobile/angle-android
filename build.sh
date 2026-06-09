#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

PLATFORM="${1:-Android}"
ARCH="${2:-arm64}"

case "$ARCH" in
  arm64) ABI="arm64-v8a" ;;
  arm)   ABI="armeabi-v7a" ;;
  x64)   ABI="x86_64" ;;
  *) echo "Unknown ARCH: $ARCH"; exit 1 ;;
esac

ARGS_FILE="${PLATFORM}.${ARCH}.args.gn"
if [ ! -f "$ARGS_FILE" ]; then
  echo "Args file not found: $ARGS_FILE"
  exit 1
fi

echo "==> Fetching depot_tools"
if [ ! -d depot_tools ]; then
  git clone --depth=1 --no-tags --single-branch \
    https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export PATH="$PWD/depot_tools:$PATH"

# Let depot_tools self-bootstrap (creates python3_bin_reldir.txt etc.).
gclient --version >/dev/null 2>&1 || true

echo "==> Fetching ANGLE source"
if [ -z "${ANGLE_COMMIT:-}" ]; then
  ANGLE_COMMIT=$(git ls-remote https://chromium.googlesource.com/angle/angle HEAD | awk '{print $1}')
fi
echo "Using ANGLE commit: $ANGLE_COMMIT"

if [ ! -d angle ]; then
  mkdir angle
  (cd angle && git init -q && git remote add origin https://chromium.googlesource.com/angle/angle)
fi

pushd angle >/dev/null

git fetch --depth=1 origin "$ANGLE_COMMIT"
git checkout --force FETCH_HEAD

python3 scripts/bootstrap.py

# bootstrap.py writes .gclient inside angle/. Add target_os=['android'] so
# gclient sync pulls Android-specific deps (NDK, SDK, build deps).
if ! grep -q "target_os" .gclient; then
  echo "target_os = ['android']" >> .gclient
fi

# Trim unneeded third-party deps. Keep catapult: build/android/BUILD.gn
# references it even though we don't build perf tests.
sed -i.bak \
  -e "/'third_party\/dawn'\: /,+3d" \
  -e "/'third_party\/llvm\/src'\: /,+3d" \
  -e "/'third_party\/SwiftShader'\: /,+3d" \
  -e "/'third_party\/VK-GL-CTS\/src'\: /,+3d" \
  DEPS

gclient sync -f -D -R

popd >/dev/null

echo "==> Configuring & building ANGLE for $PLATFORM/$ARCH ($ABI)"
pushd angle >/dev/null

OUT_DIR="out/$PLATFORM/$ARCH"
mkdir -p "$OUT_DIR"
cp "../$ARGS_FILE" "$OUT_DIR/args.gn"

gn gen "$OUT_DIR"

# Optionally override the bundled NDK. If ANGLE_NDK_ROOT is set, append the
# overrides to args.gn and regen. android_ndk_major_version is inferred from
# the directory name (e.g. ".../ndk/27.2.12479018" → 27).
if [ -n "${ANGLE_NDK_ROOT:-}" ]; then
  echo "==> Overriding NDK: $ANGLE_NDK_ROOT"
  NDK_VER_DIR="$(basename "$ANGLE_NDK_ROOT")"
  NDK_MAJOR="${ANGLE_NDK_MAJOR_VERSION:-${NDK_VER_DIR%%.*}}"
  cat >> "$OUT_DIR/args.gn" <<EOF
android_ndk_root = "$ANGLE_NDK_ROOT"
android_ndk_version = "$NDK_VER_DIR"
android_ndk_major_version = $NDK_MAJOR
EOF
  gn gen "$OUT_DIR"
fi

autoninja --offline -C "$OUT_DIR" libEGL libGLESv2

popd >/dev/null

echo "==> Packaging artifact"
OUT_ROOT="angle-$ARCH"
rm -rf "$OUT_ROOT"
mkdir -p "$OUT_ROOT/lib/$ABI" "$OUT_ROOT/symbols/$ABI" "$OUT_ROOT/include"

echo "$ANGLE_COMMIT" > "$OUT_ROOT/commit.txt"

cp "angle/out/$PLATFORM/$ARCH/libEGL.so"    "$OUT_ROOT/lib/$ABI/"
cp "angle/out/$PLATFORM/$ARCH/libGLESv2.so" "$OUT_ROOT/lib/$ABI/"

# Keep unstripped binaries as symbol files for crash symbolication.
if [ -f "angle/out/$PLATFORM/$ARCH/lib.unstripped/libEGL.so" ]; then
  cp "angle/out/$PLATFORM/$ARCH/lib.unstripped/libEGL.so"    "$OUT_ROOT/symbols/$ABI/"
  cp "angle/out/$PLATFORM/$ARCH/lib.unstripped/libGLESv2.so" "$OUT_ROOT/symbols/$ABI/"
fi

cp -R angle/include/KHR   "$OUT_ROOT/include/"
cp -R angle/include/EGL   "$OUT_ROOT/include/"
cp -R angle/include/GLES  "$OUT_ROOT/include/"
cp -R angle/include/GLES2 "$OUT_ROOT/include/"
cp -R angle/include/GLES3 "$OUT_ROOT/include/"
find "$OUT_ROOT/include" \( -name '*.clang-format' -o -name '*.md' \) -delete

tar -czf "angle-$ARCH.tar.gz" "$OUT_ROOT"

echo "==> Done: angle-$ARCH.tar.gz"

#!/bin/bash
# Assembles per-ABI build outputs into:
#   - angle-android-jniLibs.zip  (drop into src/main/jniLibs/)
#   - angle-android.aar          (Gradle: implementation files('libs/angle-android.aar'))
#
# Usage:
#   package_aar.sh <staging_dir> <out_dir>
#
# <staging_dir> must contain, for each built ABI, a directory named
#   angle-<arch>/  with:
#     lib/<abi>/libEGL.so
#     lib/<abi>/libGLESv2.so
#     include/{KHR,EGL,GLES,GLES2,GLES3}
#     commit.txt
#
# (i.e. the layout produced by build.sh after extracting the per-ABI tar.gz)

set -euo pipefail

STAGING="${1:?staging dir required}"
OUT="${2:?out dir required}"

cd "$(dirname "$0")"
HERE="$PWD"

mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

###############################################################################
# 1. jniLibs zip
###############################################################################
JNI_ROOT="$WORK/jniLibs-pkg"
mkdir -p "$JNI_ROOT/jniLibs"

for d in "$STAGING"/angle-*/; do
  [ -d "$d/lib" ] || continue
  cp -R "$d/lib/." "$JNI_ROOT/jniLibs/"
done

# Headers next to jniLibs for convenience.
FIRST=$(ls -d "$STAGING"/angle-*/ | head -n 1)
cp -R "$FIRST/include" "$JNI_ROOT/include"
cp "$FIRST/commit.txt" "$JNI_ROOT/commit.txt" 2>/dev/null || true

(cd "$JNI_ROOT" && zip -r -q "$OUT/angle-android-jniLibs.zip" .)

###############################################################################
# 2. AAR
###############################################################################
AAR_ROOT="$WORK/aar"
mkdir -p "$AAR_ROOT/jni" "$AAR_ROOT/prefab/modules/libEGL/libs" "$AAR_ROOT/prefab/modules/libGLESv2/libs"

cp "$HERE/aar/AndroidManifest.xml" "$AAR_ROOT/AndroidManifest.xml"

# Empty classes.jar is required by AGP. An empty zip works (jar == zip).
if jar --version >/dev/null 2>&1; then
  mkdir -p "$WORK/empty-jar"
  ( cd "$WORK/empty-jar" && jar cf "$AAR_ROOT/classes.jar" . )
else
  # Empty ZIP: just an end-of-central-directory record.
  printf 'PK\005\006\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000' > "$AAR_ROOT/classes.jar"
fi

# jni/<abi>/lib*.so
for d in "$STAGING"/angle-*/; do
  [ -d "$d/lib" ] || continue
  for abidir in "$d"/lib/*/; do
    abi=$(basename "$abidir")
    mkdir -p "$AAR_ROOT/jni/$abi"
    cp "$abidir"libEGL.so    "$AAR_ROOT/jni/$abi/"
    cp "$abidir"libGLESv2.so "$AAR_ROOT/jni/$abi/"
  done
done

# Prefab layout (lets ndk-build / CMake consumers find headers & libs).
cp "$HERE/aar/prefab.json"           "$AAR_ROOT/prefab/prefab.json"
cp "$HERE/aar/module-libEGL.json"    "$AAR_ROOT/prefab/modules/libEGL/module.json"
cp "$HERE/aar/module-libGLESv2.json" "$AAR_ROOT/prefab/modules/libGLESv2/module.json"

# Headers: EGL/KHR -> libEGL module; GLES*/KHR -> libGLESv2 module.
mkdir -p "$AAR_ROOT/prefab/modules/libEGL/include" \
         "$AAR_ROOT/prefab/modules/libGLESv2/include"
cp -R "$FIRST/include/EGL"   "$AAR_ROOT/prefab/modules/libEGL/include/"
cp -R "$FIRST/include/KHR"   "$AAR_ROOT/prefab/modules/libEGL/include/"
cp -R "$FIRST/include/KHR"   "$AAR_ROOT/prefab/modules/libGLESv2/include/"
cp -R "$FIRST/include/GLES"  "$AAR_ROOT/prefab/modules/libGLESv2/include/"
cp -R "$FIRST/include/GLES2" "$AAR_ROOT/prefab/modules/libGLESv2/include/"
cp -R "$FIRST/include/GLES3" "$AAR_ROOT/prefab/modules/libGLESv2/include/"

# Per-ABI prefab payload.
for abidir in "$AAR_ROOT"/jni/*/; do
  abi=$(basename "$abidir")
  for mod in libEGL libGLESv2; do
    DEST="$AAR_ROOT/prefab/modules/$mod/libs/android.$abi"
    mkdir -p "$DEST"
    sed "s/%ABI%/$abi/" "$HERE/aar/abi.json.template" > "$DEST/abi.json"
    cp "$abidir/$mod.so" "$DEST/$mod.so"
  done
done

(cd "$AAR_ROOT" && zip -r -q "$OUT/angle-android.aar" .)

echo "Wrote:"
echo "  $OUT/angle-android-jniLibs.zip"
echo "  $OUT/angle-android.aar"

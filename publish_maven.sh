#!/bin/bash
# Builds a static Maven repository layout for hosting on GitHub Pages.
#
# Usage:
#   publish_maven.sh <version> <aar_path> <out_dir>
#
# Lays out under <out_dir>:
#   space/celestia/angle-android/<version>/angle-android-<version>.aar (+ .pom + .md5/.sha1)
#   space/celestia/angle-android/maven-metadata.xml (merged with existing remote)
#
# Consumers add:
#   maven { url = uri("https://celestiamobile.github.io/angle-android/") }
#   dependencies { implementation("space.celestia:angle-android:<version>@aar") }

set -euo pipefail

VERSION="${1:?version required (e.g. 1.0.0.1)}"
AAR="${2:?aar path required}"
OUT="${3:?out dir required}"

GROUP_PATH="space/celestia"
ARTIFACT="angle-android"
PAGES_URL="https://celestiamobile.github.io/angle-android"

DEST="$OUT/$GROUP_PATH/$ARTIFACT/$VERSION"
META_DIR="$OUT/$GROUP_PATH/$ARTIFACT"
mkdir -p "$DEST"

# .nojekyll so GitHub Pages serves files starting with _ verbatim and skips
# Jekyll processing (faster, no surprises).
touch "$OUT/.nojekyll"

# Friendly landing page.
cat > "$OUT/index.html" <<EOF
<!doctype html>
<meta charset="utf-8">
<title>angle-android Maven repository</title>
<h1>angle-android Maven repository</h1>
<p>Static Maven 2 repository serving prebuilt ANGLE for Android.</p>
<pre>
repositories {
    maven { url = uri("$PAGES_URL/") }
}
dependencies {
    implementation("space.celestia:angle-android:$VERSION@aar")
}
</pre>
<p>Source: <a href="https://github.com/celestiamobile/angle-android">celestiamobile/angle-android</a></p>
EOF

# 1. Artifact + POM
cp "$AAR" "$DEST/$ARTIFACT-$VERSION.aar"

cat > "$DEST/$ARTIFACT-$VERSION.pom" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>space.celestia</groupId>
  <artifactId>$ARTIFACT</artifactId>
  <version>$VERSION</version>
  <packaging>aar</packaging>
  <name>ANGLE for Android</name>
  <description>Prebuilt ANGLE (libEGL.so / libGLESv2.so) for Android</description>
  <url>https://github.com/celestiamobile/angle-android</url>
  <licenses>
    <license>
      <name>BSD-3-Clause</name>
      <url>https://chromium.googlesource.com/angle/angle/+/refs/heads/chromium/7871/LICENSE</url>
    </license>
  </licenses>
</project>
EOF

# Checksums for both files (Maven clients expect them).
write_sums() {
  local f="$1"
  if command -v md5sum >/dev/null 2>&1; then
    md5sum  "$f" | awk '{print $1}' > "$f.md5"
    sha1sum "$f" | awk '{print $1}' > "$f.sha1"
  else
    md5  -q "$f" > "$f.md5"
    shasum  "$f" | awk '{print $1}' > "$f.sha1"
  fi
}
write_sums "$DEST/$ARTIFACT-$VERSION.aar"
write_sums "$DEST/$ARTIFACT-$VERSION.pom"

# 2. maven-metadata.xml — merge with the currently-published version list so
# old releases stay resolvable.
TMP_VERSIONS="$(mktemp)"
trap 'rm -f "$TMP_VERSIONS"' EXIT

EXISTING_META="$(curl -fsSL "$PAGES_URL/$GROUP_PATH/$ARTIFACT/maven-metadata.xml" 2>/dev/null || true)"
if [ -n "$EXISTING_META" ]; then
  echo "$EXISTING_META" \
    | grep -oE '<version>[^<]+</version>' \
    | sed -e 's|<version>||' -e 's|</version>||' \
    > "$TMP_VERSIONS"
fi
echo "$VERSION" >> "$TMP_VERSIONS"
# De-dupe while preserving insertion order, then sort.
ALL_VERSIONS="$(awk '!seen[$0]++' "$TMP_VERSIONS" | sort -V)"
LATEST="$(echo "$ALL_VERSIONS" | tail -n 1)"
TIMESTAMP="$(date -u +%Y%m%d%H%M%S)"

{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<metadata>'
  echo '  <groupId>space.celestia</groupId>'
  echo "  <artifactId>$ARTIFACT</artifactId>"
  echo '  <versioning>'
  echo "    <latest>$LATEST</latest>"
  echo "    <release>$LATEST</release>"
  echo '    <versions>'
  while IFS= read -r v; do
    [ -z "$v" ] && continue
    echo "      <version>$v</version>"
  done <<< "$ALL_VERSIONS"
  echo '    </versions>'
  echo "    <lastUpdated>$TIMESTAMP</lastUpdated>"
  echo '  </versioning>'
  echo '</metadata>'
} > "$META_DIR/maven-metadata.xml"

write_sums "$META_DIR/maven-metadata.xml"

echo "Wrote Maven layout under: $OUT"
find "$OUT" -type f | sort

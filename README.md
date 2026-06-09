# angle-android

Builds [ANGLE](https://chromium.googlesource.com/angle/angle) for Android and
packages it for easy consumption from Gradle / NDK projects.

Companion to [`angle-apple`](https://github.com/celestiamobile/angle-apple) and
[`angle-windows`](https://github.com/celestiamobile/angle-windows).

## Build matrix

| ABI            | `target_cpu` | Args file                  |
|----------------|--------------|----------------------------|
| `arm64-v8a`    | `arm64`      | `Android.arm64.args.gn`    |
| `armeabi-v7a`  | `arm`        | `Android.arm.args.gn`      |
| `x86_64`       | `x64`        | `Android.x64.args.gn`      |

Backends enabled: **Vulkan** (primary) and **OpenGL ES** (fallback).
Minimum API level: **24** (Android 7.0).

## Artifacts

Each CI run produces:

* `Android.<arch>` — per-ABI `tar.gz` with stripped `.so`, unstripped symbols,
  and headers.
* `angle-android-jniLibs.zip` — drop-in `jniLibs/{arm64-v8a,armeabi-v7a,x86_64}`
  layout plus headers.
* `angle-android.aar` — Gradle-ready AAR with prefab metadata so CMake /
  `ndk-build` consumers see `libEGL` and `libGLESv2` as prefab modules.

## Using the AAR in a Gradle project

Published as a static Maven repo on GitHub Pages — no authentication needed:

```kotlin
// settings.gradle.kts or root build.gradle.kts
repositories {
    maven { url = uri("https://celestiamobile.github.io/angle-android/") }
}

// app/build.gradle.kts
android {
    buildFeatures {
        prefab = true
    }
}

dependencies {
    implementation("space.celestia:angle-android:<version>@aar")
}
```

`CMakeLists.txt`:

```cmake
find_package(angle REQUIRED CONFIG)
target_link_libraries(my_app angle::libEGL angle::libGLESv2)
```

## Using the jniLibs zip

Unzip into `src/main/` so it merges with the standard `jniLibs/` source set:

```
src/main/jniLibs/arm64-v8a/libEGL.so
src/main/jniLibs/arm64-v8a/libGLESv2.so
...
```

Add the headers from `include/` to your `CMakeLists.txt` include path manually.

## Local build

Requires Linux (Chromium's Android build chain is Linux-only):

```bash
./build.sh Android arm64
./build.sh Android arm
./build.sh Android x64
./package_aar.sh "$PWD/staging" "$PWD/dist"
```

(`staging/` must contain `angle-<arch>/` directories — extract each
`angle-<arch>.tar.gz` into it.)

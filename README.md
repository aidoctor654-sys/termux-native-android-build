# Termux Native Android Build

Build signed Android APKs from HTML / CSS / JS — straight from Termux, no Android Studio, no Gradle, no bubblewrap. A 29 KB WebView shell around a PWA, with CAMERA + INTERNET permissions and a debug keystore generated on first run.

This is the pipeline A52 (SM-A525F) and Hermes S21 (SM-G991B) developed to escape the limits of bubblewrap on GitHub Actions and ship an actual installable APK in seconds.

## Why this exists

- **PWABuilder Cloud** had a payload bug we couldn't reproduce
- **bubblewrap CLI** `init` is interactive by design (issue [#953](https://github.com/GoogleChromeLabs/bubblewrap/issues/953)) and dies in CI with `exit 130` waiting for `Domain:`
- **Android Studio** is 1.5 GB and won't run on Termux
- **Termux repo has `aapt2`, `apksigner`, `d8`, `java`** — you already have everything you need

## Pipeline (verified, 2026-07-17)

```
src/com/<pkg>/*.java
   ↓ javac --release 8
build/classes/*.class
   ↓ jar cvf
build/classes.jar
   ↓ d8 --min-api 26
build/classes.dex
                        ┐
AndroidManifest.xml  ──┐│
res/                 ──┼┤ aapt package -F build/base.apk
assets/www/          ──┘┘
                        ┘
build/base.apk
   ↓ aapt add
build/base.apk (+ classes.dex + assets)
   ↓ apksigner sign --ks ~/.apk-builder-debug.keystore
<project>/app-debug.apk
```

| Stage | Tool | Termux package |
|-------|------|----------------|
| Java compile | `javac --release 8` | `openjdk-17` (or 21 — `21.0.11` verified) |
| Java → DEX | `d8` | `android-sdk-build-tools` *or* extract from SDK zip |
| Resources | `aapt` | `aapt` |
| Package | `aapt add` | `aapt` |
| Sign | `apksigner` | `apksigner` |

## Prerequisites (Termux)

```bash
pkg update && pkg upgrade
pkg install openjdk-17 aapt apksigner
# d8 is NOT in Termux repo. Two options:
#   (a) pkg install android-sdk-build-tools   # when it lands
#   (b) download build-tools zip from dl.google.com and add to PATH
#       https://developer.android.com/studio/releases/build-tools
```

You also need `/system/framework/framework.jar` (already on-device).

## Project layout

```
termux-native-android-build/
├── build.sh                         # 7-step pipeline driver
└── aurascanner/                     # example project
    ├── AndroidManifest.xml          # package, permissions, activity
    ├── assets/www/index.html        # PWA payload (drop in your HTML/JS/CSS)
    ├── res/
    │   ├── layout/activity_main.xml # <WebView id="webview" />
    │   ├── mipmap-*/ic_launcher.png # 48/72/96/144/192 px
    │   └── values/
    │       ├── strings.xml          # app_name
    │       └── styles.xml           # fullscreen theme
    └── src/com/aurascanner/
        ├── MainActivity.java        # WebView + permission grant
        └── AssetLoader.java         # APK assets → filesDir
```

## Build

```bash
cd termux-native-android-build
./build.sh aurascanner
# → aurascanner/app-debug.apk
```

The first run generates `~/.apk-builder-debug.keystore` (RSA 2048, 10000 days, `storepass=android`). Re-runs reuse it.

Install on a connected device:

```bash
adb install -r aurascanner/app-debug.apk
adb shell am start -n com.aurascanner/.MainActivity
```

## Adapting to your own PWA

1. **Replace** `aurascanner/assets/www/index.html` (and friends) with your existing PWA's HTML/JS/CSS
2. **Edit** `aurascanner/AndroidManifest.xml`:
   - change `package="com.aurascanner"` to your domain reversed
   - adjust permissions (drop CAMERA if you don't need it)
3. **Rename** package in `src/com/aurascanner/` and update `package` declaration
4. **Replace** `res/mipmap-*/ic_launcher.png` with your actual icons
5. Build — same `./build.sh yourapp`

## How the WebView shell works

`MainActivity` (a) inflates `R.layout.activity_main` (a full-screen WebView), (b) enables JavaScript + DOM storage + media autoplay, (c) installs a `WebChromeClient` that grants `RESOURCE_VIDEO_CAPTURE` (so the Aura Scanner can use the camera), (d) copies `assets/www/` to private files dir on first run (so the service worker and `file://` URLs work), (e) loads `file://<filesDir>/www/index.html`.

`AssetLoader` is a 50-line recursive asset hydrator. WebView's `file://` scheme cannot serve from the read-only APK asset bundle when service workers / Cache API come into play — you have to copy first.

## Output size budget

| Component | Bytes |
|-----------|------:|
| `classes.dex` | ~2 KB |
| `resources.arsc` + manifest | ~2 KB |
| `assets/www/index.html` placeholder | ~1.5 KB |
| PNG launcher icons (5 sizes) | ~2 KB |
| ZIP overhead | ~2 KB |
| **Total** | **~10 KB** |

A real PWA (CSS, JS, fonts) lands at 25–80 KB. Compare: a stock Android Studio "Hello World" APK is 1.5–2 MB.

## Troubleshooting

**`aapt: command not found`** — Termux repo split. `pkg install aapt` (or use `aapt2` from `android-tools` and rewrite the build script's `aapt package` → `aapt2 link`).

**`d8: command not found`** — Not in Termux repo yet. Download `commandlinetools-linux-*.zip` from dl.google.com, `sdkmanager --install "build-tools;34.0.0"`, add `build-tools/34.0.0/d8` to `PATH`.

**`apksigner` complains about v1/v2 signature** — Add `--v1-signing-enabled true --v2-signing-enabled true` to the `apksigner sign` call. Modern Android wants both.

**WebView shows blank screen** — Check `adb logcat | grep -i chromium`. Usually it's a CORS / `file://` scheme issue; you may need a custom `WebViewClient.shouldInterceptRequest` to rewrite cross-origin file:// requests.

**CAMERA permission not granted** — `WebChromeClient.onPermissionRequest` only fires for HTML5 `getUserMedia`. Make sure the page calls `navigator.mediaDevices.getUserMedia({video: true})`, not the old `navigator.getUserMedia`.

## Limitations (when NOT to use this)

- ❌ TWA / Play Store with Digital Asset Links → use bubblewrap + assetlinks.json
- ❌ Native `.so` libraries → need NDK + full Gradle
- ❌ Multiple Activities / Services / Receivers → write a proper Android project
- ❌ Release-signed Play Store upload → replace debug keystore with release keystore + Play upload step

## Origin

Built 2026-07-17 on Samsung A52 + S21, Termux on Android 14. The bubblewrap CI for [aura-scanner](https://github.com/aidoctor654-sys/aura-scanner) was stuck on `bubblewrap init`'s interactive `Domain:` prompt. A52 shipped the 7-step pipeline. Hermes S21 generalized, packaged, adopted for the PWA, and published this repo.

## License

MIT. Use it, fork it, ship it.

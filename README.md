# AddKo — Android native Kodi integration

Version 0.2.1+25 brings the current native integration into this repository.
Android ARM64 uses Kodi 21.3, its CPython 3.11, InputStream Adaptive 21.5.25
and FFmpegDirect 21.3.8. Flutter draws the application interface over the
native activity. The launcher prepares the private runtime before starting
the native activity in the :kodi process.

## Startup fixes

Native paths are configured in the native process before loading libkodi.
An absent vendor launcher no longer causes a null dereference. The Flutter
host continues waiting for a slow native surface instead of abandoning
startup after 12 seconds. MPV Android libraries have been removed; desktop
MPV packages remain.

## Reproducible runtime

Run `python3 tools/android/fetch_kodi_runtime.py` before building. It downloads
pinned official packages, verifies SHA-256, stages assets and ARM64 libraries,
applies the versioned integration overlays, then audits every inventoried
file. Large binary payloads are not stored in Git. Sources and licenses:
`third_party/kodi_21_3/PROVENANCE.json`, `LICENSE.md`, and `LICENSES/`. Kodi
source is available at https://github.com/xbmc/xbmc/tree/21.3-Omega; InputStream
sources at https://github.com/xbmc/inputstream.adaptive and
https://github.com/xbmc/inputstream.ffmpegdirect (versions above).

## GitHub Actions

The workflow builds and audits an ARM64 release APK, uploads it as an artifact,
and attempts a startup smoke test on an API 30 Google APIs emulator with ARM
translation. The test requires a Flutter frame, ready native JSON-RPC, and
a stable native process for 15 seconds. Diagnostics are uploaded on failure.
An emulator lacking ARM64 translation fails explicitly rather than reporting
a successful startup. This does not verify playback, DRM, or every TV box.

The startup regression is not considered validated until that test passes.

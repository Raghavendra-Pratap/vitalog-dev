# Development

Flutter **3.47.5**. The app is `app/`. The pure-Dart core is `core/`. The package name inside Dart is `bodyline`. The name on the desktop is Vitalog.

```bash
cd app && flutter pub get && flutter test
cd app && flutter run -d macos
```

`flutter test` runs `app/test/`. The desktop ship-path check is `app/integration_test/ship_paths_test.dart`. It uses a temporary database and does not open the person’s real Vitalog record.

## Catalogue

The database the app loads is `app/assets/catalog/catalog.db`. It is part of the repository because the tests and the release build need it. `catalog/build_catalog.py` writes a thinner seed and is not a substitute for that asset.

## Desktop CI

`.github/workflows/desktop.yml` runs on `main`.

1. Secret scan
2. Tests
3. Mac disk image, Windows setup, Debian package
4. Publish those three files on the GitHub release for the version in `pubspec.yaml`

The Windows build defines `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` so it can compile on the current GitHub Windows image. The desktop app does not use JNI, and the Windows CMake file skips the JNI lookup.

## Do not commit

Sample lab PDFs and local extraction environments stay out of git. Do not commit keystores, `.env` files, or a recovery key.

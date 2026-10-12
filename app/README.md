# bodyline (Flutter)

Local-first family lab tracker.

## Run

```bash
# macOS desktop (primary desktop target)
flutter run -d macos

# Android
flutter run -d <device>

# Windows / Linux (scaffolded — SQLCipher plugin is macOS/Android/iOS today)
flutter run -d windows   # on a Windows machine
flutter run -d linux     # on a Linux machine
```

## Release (macOS)

```bash
flutter build macos --release
# App: build/macos/Build/Products/Release/Vitalog.app
```

Notarization / Developer ID signing is separate (Apple account).

## Notes

- Camera OCR: Android / iOS. Desktop: paste, photo file, or PDF text.
- Encrypted `user.db` via SQLCipher where the plugin supports the platform.

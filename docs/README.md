# Vitalog documentation

Vitalog is the product. `bodyline` is the repository name. This set describes the app as it ships in **0.2.6**.

| Document | What it answers |
|----------|-----------------|
| [Product](PRODUCT.md) | Who it is for, what it does, and what it refuses to do |
| [Using Vitalog](USING.md) | Profiles, labs, files, lock, backup, and wipe |
| [Architecture](ARCHITECTURE.md) | Where data lives, and which calls leave the device |
| [Privacy](PRIVACY.md) | The same promises as [vitalog.cc/privacy](https://vitalog.cc/privacy) |
| [Desktop](DESKTOP.md) | Unsigned installers and how an installed copy finds an update |
| [Development](DEVELOPMENT.md) | How to run the app and how a version is published |

The file `bodyline — Product & Engineering Handbook.md` in the repository root is the earlier engineering spec. Where it disagrees with these pages, these pages win. In particular, Vitalog does not sync health records through Google Drive or iCloud, and it does not send crash reports.

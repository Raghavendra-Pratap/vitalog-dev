# Architecture

One Flutter application, with a pure-Dart core for matching, units, and flags. Android, iOS, macOS, Windows, and Linux share that core. There is no Vitalog service that receives the health record.

## On the device

The record is an encrypted database on that device. Report photos and PDFs are encrypted files on that device, separate from the database. The catalogue shipped with the app is reference data, not the person’s results. A catalogue update replaces that reference file and does not rewrite saved rows.

The app-lock PIN is stored as a hash in the platform key store. On Mac, new encryption keys are kept in the login keychain.

## What may use the network

| Use | What leaves the device |
|-----|------------------------|
| Catalogue and medicine names | A request for the published list on vitalog.cc |
| Help | The message the person sends |
| Desktop update check | A request for the latest GitHub release of this app |
| Health Connect or Apple Health | Readings move between Vitalog and the health store on that phone |
| Same-Wi-Fi pairing | Devices the person pairs exchange the record on that network |

There is no always-on relay. Drive and iCloud backup of the record are not part of this version.

## Flags

If the report has a printed range, that range wins. A catalogue default is only a fallback. The flag text states the comparison with the range. It does not name a disease.

## Desktop update

The installed desktop app reads the latest release of the public repository `vitalog-pub`. If that version is newer than this copy, Settings opens the installer for this system: a Mac disk image, a Windows setup program, or a Debian package. The request does not include lab values. See [Desktop](DESKTOP.md).

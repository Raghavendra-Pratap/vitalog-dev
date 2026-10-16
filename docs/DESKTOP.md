# Desktop delivery

Unsigned installers are published on the public repository [vitalog-pub](https://github.com/Raghavendra-Pratap/vitalog-pub). The application source stays in this private repository. Version **0.2.6** was built before that split, so it is not attached to the public repository yet.

| System | File | Install |
|--------|------|---------|
| Mac | `Vitalog-0.2.6.dmg` | Open the disk image and drag Vitalog to Applications |
| Windows | `Vitalog-0.2.6-setup.exe` | Run the setup. It adds a Start menu entry |
| Debian / Ubuntu | `Vitalog-0.2.6.deb` | Install the package |

macOS will say the developer cannot be verified. Windows SmartScreen will ask before the setup runs. Signing is a later step. These installers do not remove those warnings.

The release is attached by the desktop workflow on `main` when the tests and the three builds pass. The workflow does not deploy the website.

## How an installed copy updates

Desktop Settings has **This copy**. It requests the latest GitHub release. The same version is not offered again. A newer release shows **Download**, which opens the installer for this computer. The button says the download is unsigned.

The version string in `app/pubspec.yaml` and `vitalogReleaseVersion` in `app/lib/updates/app_update.dart` must match. A unit test fails if they diverge. Publish the next version by changing both, then pushing `main`. The release tag is `v` plus that version, without the `+` build number.

Until a version newer than the installed copy is published, Check reports that no newer release exists.

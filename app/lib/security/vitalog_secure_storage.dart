import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Login Keychain on macOS. The data-protection keychain needs an Apple
/// team, which an ad-hoc Vitalog build does not have, and that path was
/// writing the database key into a plain file.
const vitalogSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  mOptions: MacOsOptions(
    synchronizable: false,
    useDataProtectionKeyChain: false,
    accessibility: KeychainAccessibility.first_unlock,
  ),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  ),
);

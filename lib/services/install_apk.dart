import 'package:flutter/services.dart';
import 'errors.dart';

class ApkInstaller {
  static const _channel = MethodChannel('scobysense/updater');

  static Future<void> install(String absolutePath) async {
    try {
      await _channel.invokeMethod<void>('installApk', {'path': absolutePath});
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'NEEDS_INSTALL_PERMISSION':
          throw UpdateFailure(
            'Allow installs from ScobySense in system settings, then retry.',
            e,
          );
        case 'SIGNATURE_MISMATCH':
          throw UpdateFailure(
            'Downloaded APK is signed with a different key — refusing to install.',
            e,
          );
        default:
          throw UpdateFailure(
            'Could not launch installer: ${e.message ?? e.code}',
            e,
          );
      }
    } on MissingPluginException catch (e) {
      throw UpdateFailure('Installer not wired on this platform.', e);
    }
  }
}

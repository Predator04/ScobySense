import 'package:flutter/services.dart';
import 'errors.dart';

class ApkInstaller {
  static const _channel = MethodChannel('scobysense/updater');

  static Future<void> install(String absolutePath) async {
    try {
      await _channel.invokeMethod<void>('installApk', {'path': absolutePath});
    } on PlatformException catch (e) {
      throw UpdateFailure(
          'Could not launch installer: ${e.message ?? e.code}', e);
    } on MissingPluginException catch (e) {
      throw UpdateFailure('Installer not wired on this platform.', e);
    }
  }
}

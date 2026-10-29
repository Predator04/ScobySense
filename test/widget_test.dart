import 'package:flutter_test/flutter_test.dart';
import 'package:scobysense/services/update_service.dart';

void main() {
  group('SemVer', () {
    test('parses "v0.1.0"', () {
      final v = SemVer.parse('v0.1.0');
      expect(v.major, 0);
      expect(v.minor, 1);
      expect(v.patch, 0);
    });

    test('parses "0.2.0+2"', () {
      final v = SemVer.parse('0.2.0+2');
      expect(v.toString(), '0.2.0');
    });

    test('compares correctly', () {
      expect(SemVer.parse('0.2.0').compareTo(SemVer.parse('0.1.9')) > 0, true);
      expect(SemVer.parse('v1.0.0').compareTo(SemVer.parse('0.9.9')) > 0, true);
      expect(SemVer.parse('0.1.0').compareTo(SemVer.parse('0.1.0')), 0);
    });
  });

  group('DownloadProgress formatters', () {
    test('bytes', () {
      expect(DownloadProgress.formatBytes(512), '512 B');
      expect(DownloadProgress.formatBytes(2048), '2.0 KB');
      expect(DownloadProgress.formatBytes(5 * 1024 * 1024), '5.0 MB');
    });

    test('speed', () {
      expect(DownloadProgress.formatSpeed(0), '--');
      expect(DownloadProgress.formatSpeed(2048), '2.0 KB/s');
      expect(DownloadProgress.formatSpeed(5 * 1024 * 1024), '5.0 MB/s');
    });

    test('eta', () {
      expect(DownloadProgress.formatEta(const Duration(seconds: 65)), '1:05');
      expect(DownloadProgress.formatEta(Duration.zero), '--');
    });
  });
}

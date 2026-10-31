import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scobysense/services/errors.dart';
import 'package:scobysense/services/update_service.dart';

void main() {
  group('SemVer', () {
    test('parses "v0.1.0"', () {
      final v = SemVer.parse('v0.1.0');
      expect(v.major, 0);
      expect(v.minor, 1);
      expect(v.patch, 0);
    });

    test('strips build metadata like "0.2.0+2"', () {
      expect(SemVer.parse('0.2.0+2').toString(), '0.2.0');
      expect(SemVer.parse('v0.7.2+35').toString(), '0.7.2');
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

  group('SHA-256 integrity', () {
    // Known-answer: sha256("abc") per NIST FIPS 180-4.
    const expectedAbcHex =
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

    test('crypto.sha256 of fixed bytes matches known hex digest', () {
      final digest = sha256.convert(utf8.encode('abc'));
      expect(digest.toString(), expectedAbcHex);
    });

    test('digest mismatch is detected (defensive check)', () {
      final digest = sha256.convert(utf8.encode('abc')).toString();
      // Flip one hex char → compare must fail.
      final tampered = 'a${expectedAbcHex.substring(1)}';
      expect(digest.toLowerCase() == tampered.toLowerCase(), false);
    });

    test('chunked conversion matches one-shot digest', () {
      // Mirrors the way UpdateService hashes streamed download chunks.
      final chunks = <List<int>>[
        utf8.encode('a'),
        utf8.encode('b'),
        utf8.encode('c'),
      ];
      Digest? captured;
      final out = ChunkedConversionSink<Digest>.withCallback((digests) {
        captured = digests.single;
      });
      final input = sha256.startChunkedConversion(out);
      for (final c in chunks) {
        input.add(c);
      }
      input.close();
      expect(captured, isNotNull);
      expect(captured!.toString(), expectedAbcHex);
    });
  });

  group('UpdateService.fetchExpectedSha256', () {
    ReleaseInfo release(String url) => ReleaseInfo(
          tag: 'v0.7.2',
          version: SemVer.parse('0.7.2'),
          apkUrl: 'https://example/app.apk',
          apkName: 'app.apk',
          apkSize: 1,
          sha256Url: url,
        );

    test('returns the lowercased 64-char hex for a plain-hex body', () async {
      final mock = MockClient((req) async =>
          http.Response('A' * 64, 200)); // 64 valid hex chars (uppercase)
      final svc = UpdateService(client: mock);
      final hex = await svc.fetchExpectedSha256(release('https://x/app.apk.sha256'));
      expect(hex, 'a' * 64);
    });

    test('accepts "<hex>  filename" format and ignores filename', () async {
      final mock = MockClient(
          (req) async => http.Response('${'f' * 64}  app.apk\n', 200));
      final svc = UpdateService(client: mock);
      final hex = await svc.fetchExpectedSha256(release('https://x/app.apk.sha256'));
      expect(hex, 'f' * 64);
    });

    test('returns null when payload is not a 64-char hex string', () async {
      final mock = MockClient((req) async => http.Response('nope\n', 200));
      final svc = UpdateService(client: mock);
      final hex = await svc.fetchExpectedSha256(release('https://x/app.apk.sha256'));
      expect(hex, isNull);
    });

    test('returns null when sha256Url is absent', () async {
      final svc = UpdateService(client: MockClient((_) async => http.Response('', 200)));
      final hex = await svc.fetchExpectedSha256(ReleaseInfo(
        tag: 'v0.7.2',
        version: SemVer.parse('0.7.2'),
        apkUrl: 'u',
        apkName: 'app.apk',
        apkSize: 1,
      ));
      expect(hex, isNull);
    });

    test('throws ServerFailure on HTTP error', () async {
      final mock = MockClient((req) async => http.Response('nope', 500));
      final svc = UpdateService(client: mock);
      await expectLater(
        svc.fetchExpectedSha256(release('https://x/app.apk.sha256')),
        throwsA(isA<ServerFailure>()),
      );
    });
  });
}

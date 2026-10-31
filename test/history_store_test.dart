import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:scobysense/services/history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TempSample.tryFromJson', () {
    test('returns null when ts is missing or non-numeric', () {
      expect(TempSample.tryFromJson({'f1Temp': 1.0}), isNull);
      expect(TempSample.tryFromJson({'ts': 'not a number'}), isNull);
    });

    test('parses numeric ts and typed temp/status fields', () {
      final s = TempSample.tryFromJson({
        'ts': 1700000000000,
        'f1Temp': 22.5,
        'f2Temp': null,
        'f1Status': 'on',
        'f2Status': null,
      })!;
      expect(s.ts, 1700000000000);
      expect(s.f1Temp, 22.5);
      expect(s.f2Temp, isNull);
      expect(s.f1Status, 'on');
      expect(s.f2Status, isNull);
    });
  });

  group('HistoryStore.load', () {
    test('corrupt stored JSON → returns []', () async {
      SharedPreferences.setMockInitialValues({'history:dev1': '{not json'});
      final out = await HistoryStore().load('dev1');
      expect(out, isEmpty);
    });

    test('skips entries that lack a valid ts', () async {
      SharedPreferences.setMockInitialValues({
        'history:dev1': jsonEncode([
          {'ts': 100, 'f1Temp': 1.0},
          {'f1Temp': 2.0}, // missing ts
          {'ts': 'oops', 'f1Temp': 3.0}, // bad ts
          {'ts': 200, 'f1Temp': 4.0},
        ]),
      });
      final out = await HistoryStore().load('dev1');
      expect(out.map((s) => s.ts).toList(), [100, 200]);
    });
  });

  group('HistoryStore.append', () {
    test('self-heals after corrupt storage (does not throw)', () async {
      SharedPreferences.setMockInitialValues({'history:dev1': '{broken'});
      final store = HistoryStore();
      await store.append('dev1', TempSample(ts: 42, f1Temp: 1.0));
      final out = await store.load('dev1');
      expect(out.length, 1);
      expect(out.single.ts, 42);
      expect(out.single.f1Temp, 1.0);
    });

    test('ring buffer trims to the cap (2000)', () async {
      final store = HistoryStore();
      // Seed 1999 entries directly to keep the test fast.
      final seed = List.generate(
        1999,
        (i) => {'ts': i, 'f1Temp': i.toDouble()},
      );
      SharedPreferences.setMockInitialValues({
        'history:dev1': jsonEncode(seed),
      });

      // Append two more; store should trim the oldest.
      await store.append('dev1', TempSample(ts: 1999, f1Temp: 1999));
      await store.append('dev1', TempSample(ts: 2000, f1Temp: 2000));

      final out = await store.load('dev1');
      expect(out.length, 2000);
      expect(out.first.ts, 1); // ts=0 dropped
      expect(out.last.ts, 2000);
    });
  });
}

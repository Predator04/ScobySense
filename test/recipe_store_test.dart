import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scobysense/services/errors.dart';
import 'package:scobysense/services/recipe_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Install a mock asset response so loadBundled() doesn't need the real asset
/// pipeline.  Also covers listCategories, which calls loadMerged -> loadBundled.
void _mockBundledRecipes(List<Map<String, dynamic>> recipes) {
  final payload = jsonEncode({'recipes': recipes});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) async {
    final key = utf8.decode(message!.buffer.asUint8List());
    if (key == 'assets/recipes.json') {
      final bytes = utf8.encode(payload);
      return ByteData.view(Uint8List.fromList(bytes).buffer);
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mockBundledRecipes([
      {'slug': 'ginger-bug', 'name': 'Ginger Bug', 'tag': 'base'},
      {'slug': 'basic-booch', 'name': 'Basic Booch', 'tag': 'kombucha'},
    ]);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('RecipeStore.loadCustom', () {
    test('corrupt JSON → returns [] AND raw backed up to .bak', () async {
      SharedPreferences.setMockInitialValues({
        'custom_recipes': '{not json',
      });
      final store = RecipeStore();
      final result = await store.loadCustom();
      expect(result, isEmpty);

      final p = await SharedPreferences.getInstance();
      expect(p.getString('custom_recipes.bak'), '{not json');
    });

    test('well-formed custom list is returned with custom:true flag', () async {
      SharedPreferences.setMockInitialValues({
        'custom_recipes':
            jsonEncode([{'slug': 'foo', 'name': 'Foo', 'tag': 'kombucha'}]),
      });
      final out = await RecipeStore().loadCustom();
      expect(out.single['slug'], 'foo');
      expect(out.single['custom'], true);
    });
  });

  group('RecipeStore category rename behavior', () {
    test('listCategories does NOT apply renames to custom recipe tags', () async {
      SharedPreferences.setMockInitialValues({
        // Custom recipe uses the new (displayed) tag already.
        'custom_recipes': jsonEncode([
          {'slug': 'c1', 'name': 'C1', 'tag': 'Soda'},
        ]),
        // Rename: Bundled "kombucha" → "Tea". Should NOT also map "Soda"→anything.
        'category_renames': jsonEncode({'kombucha': 'Tea'}),
      });
      final cats = await RecipeStore().listCategories();
      // "base" bundled tag, "Tea" (bundled kombucha → Tea rename), custom "Soda" untouched.
      expect(cats.toSet(), {'base', 'Tea', 'Soda'});
    });
  });

  group('RecipeStore.loadMerged', () {
    test('custom recipe with same slug overrides bundled copy', () async {
      SharedPreferences.setMockInitialValues({
        'custom_recipes': jsonEncode([
          {'slug': 'ginger-bug', 'name': 'My Ginger Bug', 'tag': 'base'},
        ]),
      });
      final merged = await RecipeStore().loadMerged();
      final matches = merged.where((r) => r['slug'] == 'ginger-bug').toList();
      expect(matches.length, 1);
      expect(matches.single['name'], 'My Ginger Bug');
      expect(matches.single['custom'], true);
    });
  });

  group('RecipeStore.upsertCustom', () {
    test('throws ServerFailure on empty/missing slug', () async {
      final store = RecipeStore();
      await expectLater(
        store.upsertCustom({'name': 'No Slug'}),
        throwsA(isA<ServerFailure>()),
      );
      await expectLater(
        store.upsertCustom({'slug': '', 'name': 'Blank Slug'}),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('inserts new slug and replaces existing on second call', () async {
      final store = RecipeStore();
      await store.upsertCustom({'slug': 'x', 'name': 'First'});
      await store.upsertCustom({'slug': 'x', 'name': 'Second'});
      final loaded = await store.loadCustom();
      expect(loaded.length, 1);
      expect(loaded.single['name'], 'Second');
    });
  });
}

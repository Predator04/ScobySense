import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'errors.dart';

/// Loads bundled + custom recipes and tracks which ones the user removed.
/// Custom recipes carry a `custom: true` flag so the UI can distinguish them.
class RecipeStore {
  static const _kCustom = 'custom_recipes';
  static const _kRemoved = 'removed_recipes';
  static const _kCategories = 'custom_categories';
  static const _kRenames = 'category_renames';

  Future<List<Map<String, dynamic>>> loadBundled() async {
    final raw = await rootBundle.loadString('assets/recipes.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return ((map['recipes'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
  }

  // When a stored JSON blob fails to decode, copy it to a .bak key so the next
  // write doesn't silently wipe user data. Users can inspect/recover from the
  // backup via adb/shared_preferences if needed.
  Future<void> _backup(SharedPreferences p, String key, String raw) async {
    try {
      await p.setString('$key.bak', raw);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> loadCustom() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kCustom);
    if (s == null || s.isEmpty) return const [];
    try {
      final list = jsonDecode(s) as List;
      return list
          .cast<Map<String, dynamic>>()
          .map((e) => {...e, 'custom': true})
          .toList();
    } catch (_) {
      await _backup(p, _kCustom, s);
      return const [];
    }
  }

  Future<Set<String>> loadRemoved() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kRemoved) ?? const <String>[];
    return list.toSet();
  }

  Future<List<Map<String, dynamic>>> loadMerged() async {
    final bundled = await loadBundled();
    final custom = await loadCustom();
    final removed = await loadRemoved();
    final customSlugs = <String>{
      for (final c in custom)
        if (c['slug'] != null && c['slug'].toString().isNotEmpty)
          c['slug'].toString()
    };
    final out = <Map<String, dynamic>>[];
    for (final r in bundled) {
      final slug = r['slug']?.toString();
      if (slug != null && removed.contains(slug)) continue;
      if (slug != null && customSlugs.contains(slug)) continue;
      out.add(r);
    }
    out.addAll(custom);
    return out;
  }

  Future<void> addCustom(Map<String, dynamic> recipe) async {
    final p = await SharedPreferences.getInstance();
    final current = await loadCustom();
    final cleaned = Map<String, dynamic>.from(recipe)..remove('custom');
    final next = [...current.map((e) => Map<String, dynamic>.from(e)..remove('custom')), cleaned];
    await p.setString(_kCustom, jsonEncode(next));
  }

  /// Insert-or-replace a custom recipe by slug. Used by edit flow so a
  /// bundled recipe edited by the user is saved under its original slug
  /// (and overrides the bundled copy on load). Throws [ServerFailure] if
  /// slug is missing — callers must handle so a bad save doesn't silently
  /// pop with a success result.
  Future<void> upsertCustom(Map<String, dynamic> recipe) async {
    final slug = recipe['slug']?.toString();
    if (slug == null || slug.isEmpty) {
      throw const ServerFailure('Recipe is missing a slug.');
    }
    final p = await SharedPreferences.getInstance();
    final current = await loadCustom();
    final list = current
        .map((e) => Map<String, dynamic>.from(e)..remove('custom'))
        .toList();
    final cleaned = Map<String, dynamic>.from(recipe)..remove('custom');
    final idx = list.indexWhere((e) => e['slug']?.toString() == slug);
    if (idx >= 0) {
      list[idx] = cleaned;
    } else {
      list.add(cleaned);
    }
    await p.setString(_kCustom, jsonEncode(list));
  }

  Future<void> deleteRecipe(Map<String, dynamic> recipe) async {
    final slug = recipe['slug']?.toString();
    if (slug == null || slug.isEmpty) return;
    final isCustom = recipe['custom'] == true;
    final p = await SharedPreferences.getInstance();
    if (isCustom) {
      final current = await loadCustom();
      final next = current
          .where((e) => e['slug']?.toString() != slug)
          .map((e) => Map<String, dynamic>.from(e)..remove('custom'))
          .toList();
      await p.setString(_kCustom, jsonEncode(next));
    } else {
      final removed = (p.getStringList(_kRemoved) ?? const <String>[]).toSet();
      removed.add(slug);
      await p.setStringList(_kRemoved, removed.toList());
    }
  }

  /// User-added categories (persisted separately from recipes so an empty
  /// category still shows up in the chip row).
  Future<List<String>> loadCustomCategories() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kCategories);
    if (s == null || s.isEmpty) return const [];
    try {
      return (jsonDecode(s) as List).map((e) => e.toString()).toList();
    } catch (_) {
      await _backup(p, _kCategories, s);
      return const [];
    }
  }

  /// Rename map {originalTag -> displayedTag}. Applied at render + filter
  /// time so bundled recipes also pick up renames without rewriting assets.
  Future<Map<String, String>> loadRenames() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kRenames);
    if (s == null || s.isEmpty) return const {};
    try {
      final map = jsonDecode(s) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      await _backup(p, _kRenames, s);
      return const {};
    }
  }

  /// Resolve a raw recipe tag through the rename map.
  String effectiveTag(String tag, Map<String, String> renames) {
    return renames[tag] ?? tag;
  }

  /// Full list of category labels the UI should show, with renames applied,
  /// deduped and sorted.
  Future<List<String>> listCategories() async {
    final merged = await loadMerged();
    final customCats = await loadCustomCategories();
    final renames = await loadRenames();
    final set = <String>{};
    for (final r in merged) {
      final t = r['tag']?.toString();
      if (t == null || t.isEmpty) continue;
      final isCustom = r['custom'] == true;
      // Only apply renames to bundled recipe tags. Custom recipe tags are
      // already stored under the display name (renameCategory rewrites them),
      // so re-mapping them merges a re-added old name into the new label and
      // makes it unselectable.
      set.add(isCustom ? t : effectiveTag(t, renames));
    }
    for (final c in customCats) {
      if (c.isNotEmpty) set.add(c);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final current = await loadCustomCategories();
    final renames = await loadRenames();
    final existing = <String>{
      for (final c in current) c,
    };
    for (final r in await loadMerged()) {
      final t = r['tag']?.toString();
      if (t == null || t.isEmpty) continue;
      final isCustom = r['custom'] == true;
      existing.add(isCustom ? t : effectiveTag(t, renames));
    }
    if (existing.contains(trimmed)) return;
    final next = [...current, trimmed];
    await p.setString(_kCategories, jsonEncode(next));
  }

  /// Rename a category label. Updates custom_categories, rewrites `tag` on
  /// all matching custom recipes, and records the rename in the rename map
  /// so bundled recipes with the old tag also pick up the new label.
  Future<void> renameCategory(String from, String to) async {
    final oldName = from.trim();
    final newName = to.trim();
    if (oldName.isEmpty || newName.isEmpty || oldName == newName) return;
    final p = await SharedPreferences.getInstance();

    // Rewrite custom recipe tags.
    final custom = await loadCustom();
    final rewritten = custom.map((e) {
      final m = Map<String, dynamic>.from(e)..remove('custom');
      if (m['tag']?.toString() == oldName) m['tag'] = newName;
      return m;
    }).toList();
    await p.setString(_kCustom, jsonEncode(rewritten));

    // Rewrite the custom_categories list.
    final cats = await loadCustomCategories();
    final nextCats = cats.map((c) => c == oldName ? newName : c).toList();
    await p.setString(_kCategories, jsonEncode(nextCats));

    // Update the rename map. Collapse chains: any existing X->oldName becomes X->newName.
    final renames = Map<String, String>.from(await loadRenames());
    for (final k in renames.keys.toList()) {
      if (renames[k] == oldName) renames[k] = newName;
    }
    // Bundled recipes still carry the original tag; record oldName->newName so
    // they display under the new label too.
    renames[oldName] = newName;
    // A self-mapping would be noise.
    renames.removeWhere((k, v) => k == v);
    await p.setString(_kRenames, jsonEncode(renames));
  }

  /// Generate a URL-safe slug from a title, appending a short timestamp
  /// suffix to keep custom slugs unique.
  static String slugify(String title) {
    final base = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final clean = base.isEmpty ? 'recipe' : base;
    final suffix =
        DateTime.now().millisecondsSinceEpoch.toRadixString(36).substring(4);
    return '$clean-$suffix';
  }
}

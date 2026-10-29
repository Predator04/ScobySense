import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads bundled + custom recipes and tracks which ones the user removed.
/// Custom recipes carry a `custom: true` flag so the UI can distinguish them.
class RecipeStore {
  static const _kCustom = 'custom_recipes';
  static const _kRemoved = 'removed_recipes';

  Future<List<Map<String, dynamic>>> loadBundled() async {
    final raw = await rootBundle.loadString('assets/recipes.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return ((map['recipes'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
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
  /// (and overrides the bundled copy on load).
  Future<void> upsertCustom(Map<String, dynamic> recipe) async {
    final slug = recipe['slug']?.toString();
    if (slug == null || slug.isEmpty) return;
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

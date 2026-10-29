import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  List<Map<String, dynamic>> _all = const [];
  String _query = '';
  String? _tag;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/recipes.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final items = ((map['recipes'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      setState(() {
        _all = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<String> get _tags {
    final set = <String>{};
    for (final r in _all) {
      final t = r['tag'] as String?;
      if (t != null) set.add(t);
    }
    return set.toList()..sort();
  }

  List<Map<String, dynamic>> get _filtered {
    return _all.where((r) {
      if (_tag != null && r['tag'] != _tag) return false;
      if (_query.isEmpty) return true;
      final hay = '${r['title']} ${r['summary'] ?? ''} ${r['slug']}'
          .toLowerCase();
      return hay.contains(_query.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      body: AppBackground(
        child: _loading
            ? const Center(
                child:
                    CircularProgressIndicator(color: AppTheme.accent))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: GlassCard(
                        child: Text(_error!,
                            style: const TextStyle(color: AppTheme.danger)),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search recipes',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      if (_tags.isNotEmpty)
                        SizedBox(
                          height: 48,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            children: [
                              _tagChip('all', _tag == null,
                                  () => setState(() => _tag = null)),
                              for (final t in _tags)
                                _tagChip(t, _tag == t,
                                    () => setState(() => _tag = t)),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final r = _filtered[i];
                            return _RecipeCard(data: r);
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _tagChip(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? AppTheme.accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? AppTheme.accent
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Text(label,
              style: TextStyle(
                color:
                    active ? AppTheme.accent : AppTheme.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RecipeCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final hasFullGuide =
        data['steps'] is List || data['ingredients'] is List;
    return GlassCard(
      onTap: () {
        if (hasFullGuide) {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => _RecipeDetail(data: data)),
          );
        } else {
          _openUrl(data['url'] as String?);
        }
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (data['title'] ?? data['slug'] ?? 'Recipe')
                            .toString(),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (data['tag'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent2.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(data['tag'] as String,
                            style: const TextStyle(
                                color: AppTheme.accent2, fontSize: 10)),
                      ),
                  ],
                ),
                if (data['summary'] != null) ...[
                  const SizedBox(height: 4),
                  Text(data['summary'] as String,
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 13)),
                ],
                if (hasFullGuide) ...[
                  const SizedBox(height: 6),
                  const Text('Open full guide →',
                      style: TextStyle(
                          color: AppTheme.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ] else ...[
                  const SizedBox(height: 6),
                  Text(data['url']?.toString() ?? '',
                      style: const TextStyle(
                          color: AppTheme.accent, fontSize: 12)),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppTheme.textDim),
        ],
      ),
    );
  }
}

Future<void> _openUrl(String? url) async {
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _RecipeDetail extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RecipeDetail({required this.data});

  @override
  Widget build(BuildContext context) {
    final soda = data['soda'] as Map<String, dynamic>?;
    return Scaffold(
      appBar: AppBar(title: Text(data['title']?.toString() ?? 'Recipe')),
      body: AppBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _RecipeBlock(data: data),
            if (soda != null) ...[
              const SizedBox(height: 12),
              _RecipeBlock(data: soda, isSub: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecipeBlock extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isSub;
  const _RecipeBlock({required this.data, this.isSub = false});

  @override
  Widget build(BuildContext context) {
    final steps = (data['steps'] as List?)?.cast<String>() ?? const [];
    final ingredients =
        (data['ingredients'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
    final subtitle = _subtitle();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSub) ...[
            Text(data['title']?.toString() ?? 'Recipe',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
          ],
          if (data['summary'] != null) ...[
            Text(data['summary'] as String,
                style: const TextStyle(color: AppTheme.textDim)),
            const SizedBox(height: 8),
          ],
          if (subtitle != null) ...[
            Text(subtitle,
                style: const TextStyle(
                    color: AppTheme.textDim,
                    fontStyle: FontStyle.italic,
                    fontSize: 13)),
            const SizedBox(height: 8),
          ],
          if (data['ferment_temp'] != null) ...[
            Row(
              children: [
                const Icon(Icons.thermostat,
                    size: 16, color: AppTheme.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Ferment ${data['ferment_temp']}',
                      style: const TextStyle(color: AppTheme.accent)),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (ingredients.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text('Ingredients',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final it in ingredients)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(it['name']?.toString() ?? '',
                          style: const TextStyle(color: AppTheme.text)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: Text(it['amount']?.toString() ?? '',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: AppTheme.textDim)),
                    ),
                  ],
                ),
              ),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Steps',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (int i = 0; i < steps.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i + 1}.',
                      style: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(steps[i])),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (data['prep_tips'] != null) ...[
            const SizedBox(height: 4),
            const Text('Tips',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(data['prep_tips'] as String,
                style: const TextStyle(color: AppTheme.textDim)),
          ],
          if (data['warning_signs'] != null) ...[
            const SizedBox(height: 12),
            const Text('Warnings',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(data['warning_signs'] as String,
                style: const TextStyle(color: AppTheme.accent2)),
          ],
          if (!isSub && data['url'] != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openUrl(data['url'] as String?),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Source'),
            ),
          ],
        ],
      ),
    );
  }

  String? _subtitle() {
    final makes = data['makes']?.toString();
    if (makes != null && makes.isNotEmpty) return 'Makes: $makes';
    if (data['per_bottle'] == true) return 'Per 1 bottle (F2 flavoring)';
    return null;
  }
}

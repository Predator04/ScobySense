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
      body: KombuBackground(
        child: _loading
            ? const Center(
                child:
                    CircularProgressIndicator(color: KombuTheme.accent))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: GlassCard(
                        child: Text(_error!,
                            style: const TextStyle(color: KombuTheme.danger)),
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
                ? KombuTheme.accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? KombuTheme.accent
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Text(label,
              style: TextStyle(
                color:
                    active ? KombuTheme.accent : KombuTheme.text,
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
    final hasFullGuide = data['steps'] is List;
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
                          color: KombuTheme.accent2.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(data['tag'] as String,
                            style: const TextStyle(
                                color: KombuTheme.accent2, fontSize: 10)),
                      ),
                  ],
                ),
                if (data['summary'] != null) ...[
                  const SizedBox(height: 4),
                  Text(data['summary'] as String,
                      style: const TextStyle(
                          color: KombuTheme.textDim, fontSize: 13)),
                ],
                if (hasFullGuide) ...[
                  const SizedBox(height: 6),
                  const Text('Open full guide →',
                      style: TextStyle(
                          color: KombuTheme.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ] else ...[
                  const SizedBox(height: 6),
                  Text(data['url']?.toString() ?? '',
                      style: const TextStyle(
                          color: KombuTheme.accent, fontSize: 12)),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: KombuTheme.textDim),
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
    final steps = (data['steps'] as List?)?.cast<String>() ?? const [];
    final soda = data['soda'] as Map<String, dynamic>?;
    return Scaffold(
      appBar: AppBar(title: Text(data['title']?.toString() ?? 'Recipe')),
      body: KombuBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data['summary'] != null) ...[
                    Text(data['summary'] as String,
                        style: const TextStyle(color: KombuTheme.textDim)),
                    const SizedBox(height: 12),
                  ],
                  if (data['ferment_temp_c'] != null)
                    Row(
                      children: [
                        const Icon(Icons.thermostat,
                            size: 16, color: KombuTheme.accent),
                        const SizedBox(width: 6),
                        Text('Ferment ${data['ferment_temp_c']}°C',
                            style:
                                const TextStyle(color: KombuTheme.accent)),
                      ],
                    ),
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
                                color: KombuTheme.accent,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(steps[i])),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (data['warning_signs'] != null) ...[
                    const SizedBox(height: 4),
                    const Text('Warnings',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(data['warning_signs'] as String,
                        style:
                            const TextStyle(color: KombuTheme.accent2)),
                  ],
                  if (data['url'] != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _openUrl(data['url'] as String?),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Source'),
                    ),
                  ],
                ],
              ),
            ),
            if (soda != null) ...[
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(soda['title']?.toString() ?? 'Soda',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    if (soda['makes'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(soda['makes'] as String,
                            style: const TextStyle(
                                color: KombuTheme.textDim)),
                      ),
                    const SizedBox(height: 12),
                    const Text('Ingredients',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    for (final e
                        in (soda['ingredients'] as Map<String, dynamic>? ?? {})
                            .entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text(e.key.replaceAll('_', ' '),
                                style: const TextStyle(
                                    color: KombuTheme.textDim)),
                            const Spacer(),
                            Text(e.value.toString()),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text('Steps',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    for (int i = 0;
                        i < ((soda['steps'] as List?)?.length ?? 0);
                        i++) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${i + 1}.',
                              style: const TextStyle(
                                  color: KombuTheme.accent,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                (soda['steps'] as List)[i].toString()),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

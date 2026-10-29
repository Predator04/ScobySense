import 'package:flutter/material.dart';
import '../services/recipe_store.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import 'add_recipe_screen.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  final _store = RecipeStore();
  List<Map<String, dynamic>> _all = const [];
  List<String> _categories = const [];
  Map<String, String> _renames = const {};
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
      final items = await _store.loadMerged();
      final renames = await _store.loadRenames();
      final cats = await _store.listCategories();
      setState(() {
        _all = items;
        _renames = renames;
        _categories = cats;
        if (_tag != null && !cats.contains(_tag)) _tag = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String? _tagOf(Map<String, dynamic> r) {
    final raw = r['tag']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return _store.effectiveTag(raw, _renames);
  }

  List<Map<String, dynamic>> get _filtered {
    return _all.where((r) {
      if (_tag != null && _tagOf(r) != _tag) return false;
      if (_query.isEmpty) return true;
      final hay = '${r['title']} ${r['summary'] ?? ''} ${r['slug']}'
          .toLowerCase();
      return hay.contains(_query.toLowerCase());
    }).toList();
  }

  Future<void> _openAdd() async {
    final added = await Navigator.push<bool?>(
      context,
      MaterialPageRoute(builder: (_) => const AddRecipeScreen()),
    );
    if (added == true) {
      await _load();
    }
  }

  Future<void> _openEdit(Map<String, dynamic> r) async {
    final saved = await Navigator.push<bool?>(
      context,
      MaterialPageRoute(builder: (_) => AddRecipeScreen(initial: r)),
    );
    if (saved == true) {
      await _load();
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> r) async {
    final isCustom = r['custom'] == true;
    final title = (r['title'] ?? r['slug'] ?? 'this recipe').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KombuTheme.bg2,
        title: const Text('Delete recipe?'),
        content: Text(
          isCustom
              ? 'Delete your custom recipe "$title"? This can\'t be undone.'
              : 'Hide the built-in recipe "$title" from your list? You can get it back by reinstalling or clearing app data.',
          style: const TextStyle(color: KombuTheme.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: KombuTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _store.deleteRecipe(r);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed "$title"')),
      );
    }
  }

  Future<void> _openManageCategories() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KombuTheme.bg2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ManageCategoriesSheet(store: _store),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _openAdd,
              backgroundColor: KombuTheme.accent,
              foregroundColor: const Color(0xFF04070A),
              icon: const Icon(Icons.add),
              label: const Text('Add recipe',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
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
                      SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            Expanded(
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                children: [
                                  _tagChip('all', _tag == null,
                                      () => setState(() => _tag = null)),
                                  for (final t in _categories)
                                    _tagChip(t, _tag == t,
                                        () => setState(() => _tag = t)),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: TextButton.icon(
                                onPressed: _openManageCategories,
                                icon: const Icon(Icons.edit_outlined,
                                    size: 16, color: KombuTheme.accent),
                                label: const Text('Manage',
                                    style: TextStyle(
                                        color: KombuTheme.accent,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding:
                              const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final r = _filtered[i];
                            return _RecipeCard(
                              data: r,
                              displayTag: _tagOf(r),
                              onEdit: () => _openEdit(r),
                              onDelete: () => _confirmDelete(r),
                            );
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

class _ManageCategoriesSheet extends StatefulWidget {
  final RecipeStore store;
  const _ManageCategoriesSheet({required this.store});

  @override
  State<_ManageCategoriesSheet> createState() => _ManageCategoriesSheetState();
}

class _ManageCategoriesSheetState extends State<_ManageCategoriesSheet> {
  final _addCtl = TextEditingController();
  List<String> _cats = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _addCtl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final cats = await widget.store.listCategories();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final name = _addCtl.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    await widget.store.addCategory(name);
    _addCtl.clear();
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _rename(String old) async {
    final ctl = TextEditingController(text: old);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KombuTheme.bg2,
        title: const Text('Rename category'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'New name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (result == null || result.isEmpty || result == old) return;
    setState(() => _busy = true);
    await widget.store.renameCategory(old, result);
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Manage categories',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: KombuTheme.textDim),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addCtl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'New category name',
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(color: KombuTheme.accent),
                  ),
                )
              else if (_cats.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No categories yet.',
                      style: TextStyle(color: KombuTheme.textDim)),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _cats.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      color: Color(0x22FFFFFF),
                    ),
                    itemBuilder: (_, i) {
                      final c = _cats[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(c,
                            style: const TextStyle(color: KombuTheme.text)),
                        trailing: IconButton(
                          tooltip: 'Rename',
                          icon: const Icon(Icons.edit_outlined,
                              color: KombuTheme.accent, size: 20),
                          onPressed: _busy ? null : () => _rename(c),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String? displayTag;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _RecipeCard({
    required this.data,
    required this.displayTag,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isCustom = data['custom'] == true;
    return GlassCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => _RecipeDetail(data: data)),
        );
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
                    if (isCustom)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: KombuTheme.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color:
                                  KombuTheme.accent.withValues(alpha: 0.4)),
                        ),
                        child: const Text('custom',
                            style: TextStyle(
                                color: KombuTheme.accent, fontSize: 10)),
                      ),
                    if (displayTag != null)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: KombuTheme.accent2.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(displayTag!,
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
                const SizedBox(height: 6),
                const Text('Open recipe →',
                    style: TextStyle(
                        color: KombuTheme.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit recipe',
            icon: const Icon(Icons.edit_outlined,
                color: KombuTheme.accent, size: 20),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Delete recipe',
            icon: const Icon(Icons.delete_outline,
                color: KombuTheme.danger, size: 20),
            onPressed: onDelete,
          ),
          const Icon(Icons.chevron_right, color: KombuTheme.textDim),
        ],
      ),
    );
  }
}

class _RecipeDetail extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RecipeDetail({required this.data});

  @override
  Widget build(BuildContext context) {
    final soda = data['soda'];
    final hasSoda = soda is Map<String, dynamic>;
    return Scaffold(
      appBar: AppBar(title: Text(data['title']?.toString() ?? 'Recipe')),
      body: KombuBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _RecipeBlock(data: data),
            if (hasSoda) ...[
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
                style: const TextStyle(color: KombuTheme.textDim)),
            const SizedBox(height: 8),
          ],
          if (subtitle != null) ...[
            Text(subtitle,
                style: const TextStyle(
                    color: KombuTheme.textDim,
                    fontStyle: FontStyle.italic,
                    fontSize: 13)),
            const SizedBox(height: 8),
          ],
          if (data['ferment_temp'] != null) ...[
            Row(
              children: [
                const Icon(Icons.thermostat,
                    size: 16, color: KombuTheme.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Ferment ${data['ferment_temp']}',
                      style: const TextStyle(color: KombuTheme.accent)),
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
                          style: const TextStyle(color: KombuTheme.text)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: Text(it['amount']?.toString() ?? '',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: KombuTheme.textDim)),
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
                          color: KombuTheme.accent,
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
                style: const TextStyle(color: KombuTheme.textDim)),
          ],
          if (data['warning_signs'] != null) ...[
            const SizedBox(height: 12),
            const Text('Warnings',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(data['warning_signs'] as String,
                style: const TextStyle(color: KombuTheme.accent2)),
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

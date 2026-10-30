import 'package:flutter/material.dart';
import '../services/errors.dart';
import '../services/recipe_store.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

class AddRecipeScreen extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const AddRecipeScreen({super.key, this.initial});

  @override
  State<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends State<AddRecipeScreen> {
  static const String _kNewCategorySentinel = '__new__';

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _type = TextEditingController();
  final _fermentTemp = TextEditingController();
  final _summary = TextEditingController();
  final _steps = TextEditingController();
  final _warnings = TextEditingController();
  final _newCategory = TextEditingController();
  final _store = RecipeStore();
  bool _saving = false;

  List<String> _categories = const [];
  // The dropdown value: null = "No category", a category name, or sentinel for a new one.
  String? _selectedCategory;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _title.text = (initial['title'] ?? '').toString();
      _type.text = (initial['type'] ?? '').toString();
      _fermentTemp.text = (initial['ferment_temp'] ?? '').toString();
      _summary.text = (initial['summary'] ?? '').toString();
      final rawSteps = initial['steps'];
      if (rawSteps is List) {
        _steps.text = rawSteps.map((s) => s.toString()).join('\n');
      }
      _warnings.text = (initial['warning_signs'] ?? '').toString();
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await _store.listCategories();
    final renames = await _store.loadRenames();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      final rawTag = widget.initial?['tag']?.toString();
      if (rawTag != null && rawTag.isNotEmpty) {
        final effective = _store.effectiveTag(rawTag, renames);
        _selectedCategory = cats.contains(effective) ? effective : null;
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _type.dispose();
    _fermentTemp.dispose();
    _summary.dispose();
    _steps.dispose();
    _warnings.dispose();
    _newCategory.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final steps = _steps.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final warnings = _warnings.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final base = _isEditing
          ? (Map<String, dynamic>.from(widget.initial!)..remove('custom'))
          : <String, dynamic>{'soda': false};

      base['slug'] = _isEditing
          ? widget.initial!['slug']
          : RecipeStore.slugify(_title.text.trim());
      base['title'] = _title.text.trim();

      void setOrClear(String key, String value) {
        if (value.isEmpty) {
          base.remove(key);
        } else {
          base[key] = value;
        }
      }

      setOrClear('type', _type.text.trim());
      setOrClear('ferment_temp', _fermentTemp.text.trim());
      setOrClear('summary', _summary.text.trim());

      // Resolve category.
      String? tag;
      if (_selectedCategory == _kNewCategorySentinel) {
        final n = _newCategory.text.trim();
        if (n.isNotEmpty) {
          await _store.addCategory(n);
          tag = n;
        }
      } else if (_selectedCategory != null) {
        tag = _selectedCategory;
      }
      if (tag == null || tag.isEmpty) {
        base.remove('tag');
      } else {
        base['tag'] = tag;
      }

      if (steps.isEmpty) {
        base.remove('steps');
      } else {
        base['steps'] = steps;
      }
      if (warnings.isEmpty) {
        base.remove('warning_signs');
      } else {
        base['warning_signs'] = warnings.join('\n');
      }

      await _store.upsertCustom(base);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on AppFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.danger,
          content: Text('Couldn\'t save recipe: ${e.message}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.danger,
          content: Text('Couldn\'t save recipe: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit recipe' : 'Add recipe')),
      body: AppBackground(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Title *'),
                      TextFormField(
                        controller: _title,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                            hintText: 'e.g. Blueberry Sage Fizz'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      _label('Category'),
                      DropdownButtonFormField<String?>(
                        value: _selectedCategory,
                        isExpanded: true,
                        dropdownColor: AppTheme.bg2,
                        decoration: const InputDecoration(
                          hintText: 'No category',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No category'),
                          ),
                          for (final c in _categories)
                            DropdownMenuItem<String?>(
                              value: c,
                              child: Text(c),
                            ),
                          const DropdownMenuItem<String?>(
                            value: _kNewCategorySentinel,
                            child: Text('+ New category…',
                                style: TextStyle(color: AppTheme.accent)),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedCategory = v),
                      ),
                      if (_selectedCategory == _kNewCategorySentinel) ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _newCategory,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            hintText: 'New category name',
                          ),
                          validator: (v) {
                            if (_selectedCategory != _kNewCategorySentinel) {
                              return null;
                            }
                            if (v == null || v.trim().isEmpty) {
                              return 'Enter a name';
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 14),
                      _label('Type'),
                      TextFormField(
                        controller: _type,
                        decoration: const InputDecoration(
                            hintText: 'e.g. kombucha, soda, culture'),
                      ),
                      const SizedBox(height: 14),
                      _label('Ferment temperature'),
                      TextFormField(
                        controller: _fermentTemp,
                        decoration: const InputDecoration(
                            hintText: '24-28°C / 75-82°F'),
                      ),
                      const SizedBox(height: 14),
                      _label('Summary'),
                      TextFormField(
                        controller: _summary,
                        maxLines: 3,
                        minLines: 2,
                        decoration: const InputDecoration(
                            hintText: 'Short description'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Steps (one per line)'),
                      TextFormField(
                        controller: _steps,
                        maxLines: 10,
                        minLines: 4,
                        decoration: const InputDecoration(
                            hintText:
                                'Boil water with sugar\nCool to room temp\nAdd starter + SCOBY'),
                      ),
                      const SizedBox(height: 14),
                      _label('Warning signs (one per line)'),
                      TextFormField(
                        controller: _warnings,
                        maxLines: 4,
                        minLines: 2,
                        decoration: const InputDecoration(
                            hintText:
                                'Fuzzy mold = discard\nRotten smell = discard'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save, size: 18),
                  label: Text(_saving
                      ? 'Saving…'
                      : (_isEditing ? 'Save changes' : 'Save recipe')),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: const TextStyle(
                color: AppTheme.textDim,
                fontSize: 12,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600)),
      );
}

import 'package:quick_actions/quick_actions.dart';

typedef ShortcutHandler = void Function(String type);

class ShortcutsService {
  ShortcutsService._();
  static final ShortcutsService instance = ShortcutsService._();

  final _qa = const QuickActions();
  bool _initialized = false;

  Future<void> initialize(ShortcutHandler onShortcut) async {
    if (_initialized) return;
    _initialized = true;
    try {
      _qa.initialize((type) {
        onShortcut(type);
      });
      await _qa.setShortcutItems(const <ShortcutItem>[
        ShortcutItem(type: 'live', localizedTitle: 'Live brew'),
        ShortcutItem(type: 'recipes', localizedTitle: 'Recipes'),
        ShortcutItem(type: 'demo', localizedTitle: 'Demo mode'),
      ]);
    } catch (_) {
      // quick_actions throws on platforms that don't support shortcuts
      // (iOS < 9, some Android launchers). Non-fatal.
    }
  }
}

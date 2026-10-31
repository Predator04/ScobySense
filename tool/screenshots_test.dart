// Generates README screenshots by headless-rendering the real screens.
// Run: flutter test --update-goldens test/screenshots_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scobysense/screens/login_screen.dart';
import 'package:scobysense/screens/devices_screen.dart';
import 'package:scobysense/screens/device_screen.dart';
import 'package:scobysense/screens/recipes_screen.dart';
import 'package:scobysense/services/auth_service.dart';
import 'package:scobysense/services/demo_data.dart';
import 'package:scobysense/services/demo_mode.dart';
import 'package:scobysense/services/update_service.dart';
import 'package:scobysense/theme.dart';

String get _fontDir {
  // Walk up from the dart binary until we find the SDK's material_fonts.
  var dir = File(Platform.resolvedExecutable).parent;
  for (int i = 0; i < 12; i++) {
    final candidate = '${dir.path}/bin/cache/artifacts/material_fonts';
    if (Directory(candidate).existsSync()) return candidate;
    dir = dir.parent;
  }
  return '';
}

Future<void> _loadFont(String family, String file) async {
  final bytes = File('$_fontDir/$file').readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

Future<void> _loadFonts() async {
  await _loadFont('Roboto', 'Roboto-Regular.ttf');
  await _loadFont('Roboto', 'Roboto-Medium.ttf');
  await _loadFont('Roboto', 'Roboto-Bold.ttf');
  await _loadFont('Roboto', 'Roboto-Light.ttf');
}

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});

    // Stub plugins that don't exist in the test harness.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('home_widget'), (call) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? <String>['wifi'] : null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
        (call) async => null);

    await _loadFonts();
  });

  testWidgets('screenshots', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2340));
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final updater = UpdateService(
      client: MockClient((req) async => http.Response('[]', 200)),
    );

    // 1. Login
    await _pumpScreen(
        tester, LoginScreen(auth: AuthService(), updater: updater));
    await expectLater(
      find.byType(LoginScreen),
      matchesGoldenFile('goldens/login.png'),
    );

    // 2. Devices (demo)
    DemoMode.active = true;
    await _pumpScreen(
        tester, DevicesScreen(auth: AuthService(), updater: updater));
    await tester.pump(const Duration(seconds: 2));
    await expectLater(
      find.byType(DevicesScreen),
      matchesGoldenFile('goldens/devices.png'),
    );

    // 3. Device / brew screen (demo)
    await _pumpScreen(
      tester,
      DeviceScreen(
        auth: AuthService(),
        updater: updater,
        initial: DemoData.device(),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await expectLater(
      find.byType(DeviceScreen),
      matchesGoldenFile('goldens/device.png'),
    );

    // 4. Recipes
    await _pumpScreen(tester, const RecipesScreen());
    await tester.pump(const Duration(seconds: 2));
    await expectLater(
      find.byType(RecipesScreen),
      matchesGoldenFile('goldens/recipes.png'),
    );
  });
}

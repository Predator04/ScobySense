import 'package:flutter/foundation.dart';
import 'update_service.dart';

class UpdateState {
  static final ValueNotifier<ReleaseInfo?> available =
      ValueNotifier<ReleaseInfo?>(null);
  static final ValueNotifier<String> version = ValueNotifier<String>('');
}

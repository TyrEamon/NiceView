import 'package:flutter_test/flutter_test.dart';
import 'package:nice_view/services/quota_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearServerLockout removes persisted lockout', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = QuotaController(QuotaService(preferences));
    addTearDown(controller.dispose);

    await controller.startServerLockout();
    expect(controller.state.isServerLocked, isTrue);

    await controller.clearServerLockout();

    expect(controller.state.isServerLocked, isFalse);
    final restored = QuotaService(preferences).load();
    expect(restored.isServerLocked, isFalse);
  });
}

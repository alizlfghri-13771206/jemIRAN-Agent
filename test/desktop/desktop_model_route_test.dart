import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/routing/desktop_model_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AgentStorage.setAccountScope('route-test-user');
  });

  test(
    'priority is explicit, stable and persisted only for desktop routing',
    () async {
      final first = DesktopModelRouteNotifier();
      await first.reconcile(['a', 'b', 'c']);
      expect(first.state.priority, ['a']);

      first.toggle('b');
      first.toggle('c');
      first.move('c', -1);
      first.setPrimary('b');
      expect(first.state.priority, ['b', 'a', 'c']);
      await first.flush();
      first.dispose();

      final restored = DesktopModelRouteNotifier();
      await restored.ready;
      expect(restored.state.priority, ['b', 'a', 'c']);
      restored.dispose();
    },
  );

  test('the only selected model cannot be removed', () async {
    final route = DesktopModelRouteNotifier();
    await route.reconcile(['only']);
    route.toggle('only');
    expect(route.state.priority, ['only']);
    route.dispose();
  });

  test(
    'an unavailable or stale model cannot become the primary route',
    () async {
      final route = DesktopModelRouteNotifier();
      await route.reconcile(['safe']);
      route.setPrimary('removed-model');
      route.toggle('removed-model');
      expect(route.state.priority, ['safe']);
      route.dispose();
    },
  );

  test('a re-created provider replaces the stale key in the route', () async {
    final route = DesktopModelRouteNotifier();
    await route.reconcile(['byok:old']);
    expect(route.state.priority, ['byok:old']);

    await route.reconcile(['byok:new'], allowEmpty: true);
    expect(route.state.priority, ['byok:new']);
    route.dispose();
  });

  test('deleting the last provider empties the route', () async {
    final route = DesktopModelRouteNotifier();
    await route.reconcile(['byok:only']);

    await route.reconcile([], allowEmpty: true);
    expect(route.state.priority, isEmpty);
    expect(route.state.primary, isNull);
    route.dispose();
  });

  test('an empty catalog at startup keeps the saved route', () async {
    final route = DesktopModelRouteNotifier();
    await route.reconcile(['byok:a', 'byok:b']);
    route.toggle('byok:b');

    await route.reconcile([]);
    expect(route.state.priority, ['byok:a', 'byok:b']);
    route.dispose();
  });
}

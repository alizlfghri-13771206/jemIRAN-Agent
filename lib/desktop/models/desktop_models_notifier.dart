import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/legacy.dart';
import 'package:jemiran/desktop/agent/byok/byok_provider.dart';
import 'package:jemiran/riverpod/models_provider.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/model_config.dart';

bool modelRunnable(Map<String, dynamic> model) =>
    model['enabled'] != false && model['key'] is String;

extension DesktopModelsStateX on ModelsState {
  String? get firstUsableModelKey {
    for (final model in models) {
      if (modelRunnable(model)) return model['key'] as String;
    }
    return null;
  }

  List<Map<String, dynamic>> get usableModels =>
      models.where(modelRunnable).toList(growable: false);

  List<({String company, List<Map<String, dynamic>> models})>
  get agentModelsByCompany {
    final byCompany = <String, List<Map<String, dynamic>>>{};
    for (final model in usableModels) {
      final raw = (model['company'] as String?)?.trim();
      byCompany
          .putIfAbsent(raw == null || raw.isEmpty ? 'سایر' : raw, () => [])
          .add(model);
    }
    for (final list in byCompany.values) {
      list.sort(
        (a, b) => (a['label']?.toString() ?? '').compareTo(
          b['label']?.toString() ?? '',
        ),
      );
    }
    final companies = byCompany.keys.toList()..sort();
    return [
      for (final company in companies)
        (company: company, models: byCompany[company]!),
    ];
  }
}

final desktopModelsProvider =
    StateNotifierProvider<DesktopModelsNotifier, ModelsState>(
      (ref) => DesktopModelsNotifier(),
    );

class DesktopModelsNotifier extends ModelsNotifier {
  bool _loaded = false;
  Future<void>? _inFlight;

  @override
  Future<void> loadIfNeeded() {
    if (_loaded) return Future.value();
    return _fetchOnce();
  }

  @override
  Future<void> refresh() => _fetchOnce();

  Future<void> _fetchOnce() =>
      _inFlight ??= _fetch().whenComplete(() => _inFlight = null);

  Future<void> _fetch() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      ByokStore.load();
      _publish();
      _loaded = true;
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  void refreshByokModels() {
    if (!_loaded && ByokStore.usable.isEmpty) return;
    _publish(keepStatus: true);
  }

  void _publish({bool keepStatus = false}) {
    final models = [
      for (final provider in ByokStore.usable) ByokStore.modelEntry(provider),
    ];
    ModelConfig.ingest(models);
    state = ModelsState(
      models: models,
      isLoading: keepStatus && state.isLoading,
      error: keepStatus ? state.error : null,
    );
  }

  @visibleForTesting
  void setErrorForTesting(String message) {
    state = state.copyWith(isLoading: false, error: message);
  }

  List<String> get usableModelKeys => state.models
      .where(modelRunnable)
      .map((model) => model['key'] as String?)
      .whereType<String>()
      .toList(growable: false);

  void reset() {
    _loaded = false;
    _inFlight = null;
    state = const ModelsState();
  }
}

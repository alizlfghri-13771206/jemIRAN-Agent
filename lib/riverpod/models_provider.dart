import 'package:flutter_riverpod/legacy.dart';

class ModelsState {
  final List<Map<String, dynamic>> models;
  final bool isLoading;
  final String? error;

  const ModelsState({
    this.models = const [],
    this.isLoading = false,
    this.error,
  });

  ModelsState copyWith({
    List<Map<String, dynamic>>? models,
    bool? isLoading,
    String? error,
  }) {
    return ModelsState(
      models: models ?? this.models,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ModelsNotifier extends StateNotifier<ModelsState> {
  ModelsNotifier() : super(const ModelsState());

  bool _loaded = false;
  Future<void>? _inFlight;

  Future<void> loadIfNeeded() {
    if (_loaded) return Future.value();
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    state = state.copyWith(isLoading: false, error: null);
    _loaded = true;
  }
}

final modelsProvider = StateNotifierProvider<ModelsNotifier, ModelsState>(
  (ref) => ModelsNotifier(),
);

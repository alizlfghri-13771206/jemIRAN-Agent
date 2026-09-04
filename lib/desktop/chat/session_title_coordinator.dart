class SessionTitleCoordinator {
  final Set<int> _settledOrInFlight = {};

  void markKnown(int sessionId) => _settledOrInFlight.add(sessionId);

  bool isKnown(int sessionId) => _settledOrInFlight.contains(sessionId);

  Future<bool> generate({
    required int sessionId,
    required Future<void> Function() request,
    required void Function() onChanged,
  }) async {
    if (!_settledOrInFlight.add(sessionId)) return false;
    try {
      await request();
      onChanged();
      return true;
    } catch (_) {
      _settledOrInFlight.remove(sessionId);
      return false;
    }
  }
}

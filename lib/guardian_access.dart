/// Client-side session state only. Every privileged API must independently
/// validate the server-issued authorization; this is not an authorization boundary.
class GuardianAccess {
  GuardianAccess({required this.now});
  final DateTime Function() now;
  static const idleLimit = Duration(minutes: 5);
  DateTime? _serverExpiry;
  DateTime? _lastActivity;

  bool get unlocked {
    final expiry = _serverExpiry;
    final last = _lastActivity;
    final current = now();
    return expiry != null && last != null &&
        !current.isBefore(last) && current.isBefore(expiry) &&
        current.difference(last) < idleLimit;
  }

  void begin(DateTime serverExpiry) {
    lock();
    final current = now();
    if (!serverExpiry.isAfter(current)) return;
    _serverExpiry = serverExpiry;
    _lastActivity = current;
  }

  void activity() {
    if (!unlocked) {
      lock();
      return;
    }
    _lastActivity = now();
  }

  void lock() {
    _serverExpiry = null;
    _lastActivity = null;
  }
}

import 'package:flutter_test/flutter_test.dart';
import '../lib/guardian_access.dart';

void main() {
  test('guardian session expires and cannot be revived by activity', () {
    var now = DateTime.utc(2026, 11, 25);
    final access = GuardianAccess(now: () => now);
    expect(access.unlocked, false);
    access.begin(now.add(const Duration(minutes: 15)));
    expect(access.unlocked, true);
    now = now.add(const Duration(minutes: 4));
    access.activity();
    now = now.add(const Duration(minutes: 5));
    expect(access.unlocked, false);
    access.activity();
    expect(access.unlocked, false);
  });
  test('server expiry overrides activity and explicit lock clears access', () {
    var now = DateTime.utc(2026, 11, 25);
    final access = GuardianAccess(now: () => now);
    access.begin(now.add(const Duration(minutes: 2)));
    now = now.add(const Duration(minutes: 1));
    access.activity();
    now = now.add(const Duration(minutes: 1));
    expect(access.unlocked, false);
    access.begin(now.add(const Duration(minutes: 10)));
    expect(access.unlocked, true);
    access.lock();
    expect(access.unlocked, false);
    access.begin(now);
    expect(access.unlocked, false);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'guardian_access.dart';
import 'guardian_pin.dart';
import 'guardian_setup.dart';

class GuardianScope extends InheritedWidget {
  const GuardianScope({
    super.key,
    required this.client,
    required this.close,
    required super.child,
  });
  final SupabaseClient client;
  final VoidCallback close;
  static GuardianScope? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GuardianScope>();
  @override
  bool updateShouldNotify(GuardianScope oldWidget) =>
      client != oldWidget.client;
}

class GuardianPortal extends StatefulWidget {
  const GuardianPortal({
    super.key,
    required this.account,
    required this.url,
    required this.publishableKey,
    required this.home,
    required this.scopedClient,
  });
  final SupabaseClient account;
  final String url, publishableKey;
  final WidgetBuilder home;
  final SupabaseClient Function(String token) scopedClient;

  @override
  State<GuardianPortal> createState() => _GuardianPortalState();
}

class _GuardianPortalState extends State<GuardianPortal>
    with WidgetsBindingObserver {
  final access = GuardianAccess(now: DateTime.now);
  final adultNavigator = GlobalKey<NavigatorState>();
  var entryNavigator = GlobalKey<NavigatorState>();
  Timer? timer;
  SupabaseClient? elevated;
  bool? hasPin;
  bool busy = false, pinOpen = false;
  bool foreground = true;
  String? error;
  DateTime? lastTouch;
  bool touching = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    checkPin();
  }

  Future<void> checkPin() async {
    try {
      final value = await widget.account.rpc('guardian_has_pin');
      if (mounted)
        setState(() {
          hasPin = value as bool;
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Не вдалося перевірити батьківський доступ. Перевірте інтернет.',
        );
    }
  }

  Future<void> configure(BuildContext entry) async {
    if (busy || hasPin == null) return;
    setState(() => busy = true);
    final saved = await Navigator.of(entry).push<bool>(
      MaterialPageRoute(
        builder: (_) => GuardianSetup(
          account: widget.account,
          url: widget.url,
          publishableKey: widget.publishableKey,
          recovery: hasPin!,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      busy = false;
      if (saved == true) hasPin = true;
    });
    if (saved == true && entry.mounted && foreground) await unlock(entry);
  }

  Future<void> unlock(BuildContext entry) async {
    if (busy || !foreground) return;
    setState(() {
      busy = true;
      pinOpen = true;
      error = null;
    });
    final epoch = generation;
    SupabaseClient? verified;
    DateTime? expiry;
    final account = widget.account;
    final makeClient = widget.scopedClient;
    final accepted = await requestGuardianPin(entry, (pin) async {
      final result = await account.rpc(
        'unlock_guardian',
        params: {'entered_pin': pin},
      );
      if (result is! Map) return false;
      final deadline = DateTime.tryParse(result['expires_at'].toString());
      final token = result['token'];
      if (deadline == null ||
          !deadline.isAfter(DateTime.now()) ||
          token is! String ||
          token.isEmpty) return false;
      final scoped = makeClient(token);
      if (!mounted || !foreground || epoch != generation) {
        unawaited(revoke(scoped));
        return false;
      }
      verified = scoped;
      expiry = deadline;
      return true;
    });
    if (!mounted ||
        epoch != generation ||
        !foreground ||
        !accepted ||
        verified == null) {
      if (verified != null) unawaited(revoke(verified!));
      if (mounted && epoch == generation) {
        setState(() {
          busy = false;
          pinOpen = false;
        });
      }
      return;
    }
    pinOpen = false;
    access.begin(expiry!);
    setState(() {
      elevated = verified;
      busy = false;
      lastTouch = DateTime.now();
    });
    scheduleLock();
  }

  void scheduleLock() {
    timer?.cancel();
    final deadline = access.remaining;
    if (deadline <= Duration.zero) {
      lock();
      return;
    }
    timer = Timer(deadline, lock);
  }

  void activity() {
    final client = elevated;
    if (client == null || !foreground) return;
    if (!access.unlocked) {
      lock();
      return;
    }
    access.activity();
    scheduleLock();
    final now = DateTime.now();
    if (touching ||
        (lastTouch != null &&
            now.difference(lastTouch!) < const Duration(seconds: 5))) return;
    lastTouch = now;
    touching = true;
    unawaited(renew(client));
  }

  Future<void> renew(SupabaseClient client) async {
    try {
      final ok = await client.rpc('touch_guardian');
      if (mounted && elevated == client && ok != true) lock();
    } catch (_) {
      if (mounted && elevated == client) lock();
    } finally {
      if (elevated == client) touching = false;
    }
  }

  Future<void> revoke(SupabaseClient client) async {
    try {
      await client.rpc('lock_guardian').timeout(const Duration(seconds: 4));
    } catch (_) {
      /* The server also expires the scoped token independently. */
    } finally {
      await client.dispose();
    }
  }

  void release() {
    generation++;
    timer?.cancel();
    final previous = elevated;
    elevated = null;
    touching = false;
    access.lock();
    if (previous != null) unawaited(revoke(previous));
  }

  void lock() {
    release();
    if (mounted) setState(() => busy = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (foreground == resumed) return;
    foreground = resumed;
    if (resumed) return;
    // Keep the email recovery form while the adult switches to their inbox.
    // A PIN dialog or the entire unlocked route stack must be discarded.
    if (elevated != null || pinOpen) {
      if (pinOpen) {
        entryNavigator = GlobalKey<NavigatorState>();
        pinOpen = false;
      }
      lock();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    release();
    super.dispose();
  }

  void exitPortal() {
    lock();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final client = elevated;
    final navigator = client == null ? entryNavigator : adultNavigator;
    final stack = NavigatorPopHandler<Object?>(
      onPopWithResult: (result) => navigator.currentState?.pop(result),
      child: Navigator(
        key: navigator,
        pages: [
          MaterialPage<void>(
            child: Builder(builder: client == null ? entryScreen : widget.home),
          ),
        ],
        onDidRemovePage: (_) {},
      ),
    );
    if (client == null) return stack;
    return GuardianScope(
      client: client,
      close: exitPortal,
      child: Listener(
        onPointerDown: (_) => activity(),
        onPointerSignal: (_) => activity(),
        child: Focus(
          onKeyEvent: (_, __) {
            activity();
            return KeyEventResult.ignored;
          },
          child: stack,
        ),
      ),
    );
  }

  Widget entryScreen(BuildContext entry) {
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(onPressed: exitPortal),
          title: const Text('Кабінет батьків')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.family_restroom, size: 54),
                const SizedBox(height: 16),
                Text(
                  hasPin == false
                      ? 'Створіть батьківський PIN'
                      : 'Вхід для дорослого',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'PIN захищає публікацію іграшок, повідомлення та домовленості. Кабінет блокується після п’яти хвилин бездіяльності.',
                ),
                const SizedBox(height: 16),
                if (hasPin == null && error == null)
                  const Center(child: CircularProgressIndicator()),
                if (error != null) ...[
                  Text(error!),
                  TextButton(
                    onPressed: checkPin,
                    child: const Text('Повторити'),
                  ),
                ],
                if (hasPin != null)
                  FilledButton(
                    onPressed: busy
                        ? null
                        : hasPin!
                            ? () => unlock(entry)
                            : () => configure(entry),
                    child: Text(hasPin! ? 'Увести PIN' : 'Налаштувати PIN'),
                  ),
                if (hasPin == true)
                  TextButton(
                    onPressed: busy ? null : () => configure(entry),
                    child: const Text('Відновити PIN через пошту'),
                  ),
                TextButton(
                  onPressed: exitPortal,
                  child: const Text('До містечка'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          await widget.account.auth.signOut();
                        },
                  child: const Text('Змінити акаунт'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

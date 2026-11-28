import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GuardianSetup extends StatefulWidget {
  const GuardianSetup({
    super.key,
    required this.account,
    required this.url,
    required this.publishableKey,
    required this.recovery,
  });
  final SupabaseClient account;
  final String url, publishableKey;
  final bool recovery;

  @override
  State<GuardianSetup> createState() => _GuardianSetupState();
}

class _GuardianSetupState extends State<GuardianSetup> {
  final proof = TextEditingController(),
      pin = TextEditingController(),
      repeat = TextEditingController();
  late final temporary = SupabaseClient(
    widget.url,
    widget.publishableKey,
    authOptions: const AuthClientOptions(
      authFlowType: AuthFlowType.implicit,
      autoRefreshToken: false,
    ),
  );
  bool busy = false;
  String? challenge, message;
  bool emailVerified = false;
  String get email => widget.account.auth.currentUser?.email ?? '';

  Future<void> sendCode() async {
    if (busy) return;
    setState(() {
      busy = true;
      emailVerified = false;
      proof.clear();
      message = null;
    });
    try {
      challenge = await widget.account.rpc('begin_guardian_setup') as String;
      await temporary.auth.signInWithOtp(email: email, shouldCreateUser: false);
      if (mounted)
        setState(
          () => message =
              'Лист надіслано на $email. Уведіть код або скопіюйте посилання входу з листа, не відкриваючи його.',
        );
    } catch (_) {
      challenge = null;
      if (mounted)
        setState(
          () => message =
              'Не вдалося надіслати лист. Перевірте інтернет і повторіть спробу.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy) return;
    if (!RegExp(r'^[0-9]{4}$').hasMatch(pin.text) ||
        pin.text != repeat.text ||
        (!emailVerified && proof.text.trim().isEmpty)) {
      setState(
        () => message =
            'Уведіть підтвердження доступу та двічі той самий чотиризначний PIN.',
      );
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (widget.recovery) {
        if (challenge == null) throw const FormatException();
        if (!emailVerified) {
          await verifyEmail();
          if (!mounted) return;
          verifyAccount();
          setState(() => emailVerified = true);
          proof.clear();
        }
      } else {
        challenge = await widget.account.rpc('begin_guardian_setup') as String;
        if (!mounted) return;
        await temporary.auth.signInWithPassword(
          email: email,
          password: proof.text,
        );
      }
      if (!mounted) return;
      verifyAccount();
      await temporary.rpc(
        'finish_guardian_setup',
        params: {'challenge': challenge, 'new_pin': pin.text},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted)
        setState(
          () => message = emailVerified
              ? 'Не вдалося зберегти PIN. Повторіть спробу. Якщо минуло понад 10 хвилин, замовте новий лист.'
              : widget.recovery
              ? 'Не вдалося підтвердити код або посилання. За потреби замовте новий лист.'
              : 'Не вдалося створити PIN. Перевірте пароль від акаунта й повторіть.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void verifyAccount() {
    final authenticated = temporary.auth.currentUser?.id;
    if (authenticated == null ||
        authenticated != widget.account.auth.currentUser?.id) {
      throw const FormatException();
    }
  }

  Future<void> verifyEmail() async {
    final submitted = proof.text.trim();
    if (RegExp(r'^[0-9]{6,10}$').hasMatch(submitted)) {
      await temporary.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: submitted,
      );
      return;
    }
    final link = Uri.tryParse(submitted);
    final host = Uri.parse(widget.url);
    final token =
        link?.queryParameters['token_hash'] ?? link?.queryParameters['token'];
    final type = link?.queryParameters['type'];
    if (link == null ||
        link.scheme != 'https' ||
        link.host != host.host ||
        link.port != host.port ||
        link.userInfo.isNotEmpty ||
        link.path != '/auth/v1/verify' ||
        (type != null && type != 'magiclink' && type != 'email') ||
        token == null ||
        token.isEmpty) {
      throw const FormatException();
    }
    await temporary.auth.verifyOTP(type: OtpType.email, tokenHash: token);
  }

  Future<void> clearTemporary(SupabaseClient client) async {
    try {
      if (client.auth.currentSession != null)
        await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
    } finally {
      await client.dispose();
    }
  }

  @override
  void dispose() {
    clearTemporary(temporary);
    proof.dispose();
    pin.dispose();
    repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.recovery ? 'Відновлення PIN' : 'Створення PIN'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          widget.recovery
              ? 'Підтвердьте доступ до пошти $email.'
              : 'Уведіть пароль дорослого від акаунта $email.',
        ),
        if (widget.recovery)
          TextButton(
            onPressed: busy ? null : sendCode,
            child: Text(
              challenge == null ? 'Надіслати лист' : 'Надіслати ще раз',
            ),
          ),
        if (emailVerified)
          const Text('Пошту підтверджено.')
        else
          TextField(
            controller: proof,
            enabled: !busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: widget.recovery
                  ? 'Код або посилання з листа'
                  : 'Пароль акаунта',
            ),
          ),
        for (final field in [pin, repeat])
          TextField(
            controller: field,
            enabled: !busy,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: field == pin ? 'Новий PIN із 4 цифр' : 'Повторіть PIN',
            ),
          ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(message!),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy || (widget.recovery && challenge == null)
              ? null
              : save,
          child: Text(busy ? 'Зачекайте…' : 'Зберегти PIN'),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The verifier must authorize on the server. Never persist the PIN locally.
Future<bool> requestGuardianPin(BuildContext context,
    Future<bool> Function(String pin) verify) async =>
    await showDialog<bool>(context: context, barrierDismissible: false,
      builder: (_) => _GuardianPinDialog(verify: verify)) ?? false;

class _GuardianPinDialog extends StatefulWidget {
  const _GuardianPinDialog({required this.verify});
  final Future<bool> Function(String) verify;
  @override
  State<_GuardianPinDialog> createState() => _GuardianPinDialogState();
}

class _GuardianPinDialogState extends State<_GuardianPinDialog> {
  final pin = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() { pin.dispose(); super.dispose(); }
  Future<void> submit() async {
    if (busy || !RegExp(r'^[0-9]{6}$').hasMatch(pin.text)) return;
    setState(() { busy = true; error = null; });
    try {
      final accepted = await widget.verify(pin.text);
      if (!mounted) return;
      pin.clear();
      if (accepted) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => error = 'Доступ не підтверджено. Спробуйте пізніше.');
    } catch (_) {
      if (!mounted) return;
      pin.clear();
      setState(() => error = 'Не вдалося перевірити доступ.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy,
    child: AlertDialog(title: const Text('Батьківський доступ'),
      content: TextField(controller: pin, obscureText: true,
        enabled: !busy, keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6)],
        decoration: InputDecoration(labelText: 'PIN-код із 6 цифр', errorText: error),
        onChanged: (_) => setState(() => error = null),
        onSubmitted: (_) => submit()),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('До містечка')),
        FilledButton(onPressed: busy || pin.text.length != 6 ? null : submit,
          child: Text(busy ? 'Перевірка…' : 'Увійти')),
      ]));
}

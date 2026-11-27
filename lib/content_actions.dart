import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum DeletableContent { message, listing, conversation }

class ContentDeleteButton extends StatefulWidget {
  const ContentDeleteButton(
      {super.key,
      required this.kind,
      required this.onDelete,
      this.compact = false});

  final DeletableContent kind;
  final Future<void> Function() onDelete;
  final bool compact;

  @override
  State<ContentDeleteButton> createState() => _ContentDeleteButtonState();
}

class _ContentDeleteButtonState extends State<ContentDeleteButton> {
  bool busy = false;
  bool get listing => widget.kind == DeletableContent.listing;
  String get label => switch (widget.kind) {
    DeletableContent.listing => 'Видалити оголошення',
    DeletableContent.message => 'Видалити повідомлення',
    DeletableContent.conversation => 'Видалити чат у мене',
  };

  void feedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> remove() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final confirmed = await showDialog<bool>(useRootNavigator: false,
          context: context,
          builder: (ctx) => AlertDialog(
                title: Text('$label?'),
                content: Text(widget.kind == DeletableContent.conversation
                    ? 'Уся переписка зникне з вашого списку й історії повідомлень. Переписка співрозмовника та угоди залишаться. Нове повідомлення знову відкриє чат.'
                    : listing
                    ? 'Оголошення зникне з каталогу, пошуку та вашої крамнички. Листування й історія угод залишаться. Якщо є активна домовленість, спочатку завершіть або скасуйте її.'
                    : 'Повідомлення буде видалено з розмови для обох родин. Відновити його не вдасться.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Скасувати')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Видалити')),
                ],
              ));
      if (confirmed != true || !mounted) return;
      await widget.onDelete();
      feedback(widget.kind == DeletableContent.conversation ? 'Чат видалено у вас.' : listing ? 'Оголошення видалено.' : 'Повідомлення видалено.');
    } catch (error) {
      var message =
          'Не вдалося видалити. Перевірте з’єднання й спробуйте ще раз.';
      if (error is PostgrestException) {
        if (error.code == '55000') {
          message =
              'Спочатку завершіть або скасуйте активну домовленість у вкладці «Угоди».';
        } else if (error.code == '42501') {
          message =
              'Запис недоступний або у вас немає права його видаляти. Оновіть сторінку.';
        }
      }
      feedback(message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.compact
      ? IconButton(
          tooltip: label,
          onPressed: busy ? null : remove,
          icon: Icon(busy ? Icons.hourglass_top : Icons.delete_outline),
          iconSize: 18)
      : Tooltip(message: label, child: TextButton.icon(
          onPressed: busy ? null : remove,
          icon: Icon(busy ? Icons.hourglass_top : Icons.delete_outline),
          label: Text(busy ? 'Зачекайте…' : label)));
}

class ConversationMessageBubble extends StatelessWidget {
  const ConversationMessageBubble(
      {super.key,
      required this.body,
      required this.createdAt,
      required this.mine,
      this.onDelete});

  final String body, createdAt;
  final bool mine;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(createdAt)?.toLocal().toString();
    return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: mine ? const Color(0xFFE8E5FF) : Colors.white,
                borderRadius: BorderRadius.circular(16)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(body),
              const SizedBox(height: 4),
              Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(date == null ? '' : date.substring(0, 16),
                        style: const TextStyle(
                            fontSize: 10, color: Colors.black54)),
                    if (mine && onDelete != null)
                      ContentDeleteButton(
                          kind: DeletableContent.message,
                          compact: false,
                          onDelete: onDelete!),
                  ]),
            ])));
  }
}

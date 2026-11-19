import 'dart:async';
import 'package:flutter/material.dart';

/// A short, untimed game. Leaving a round never reports it as completed.
class PetMemoryGame extends StatefulWidget {
  const PetMemoryGame({super.key, required this.petName, required this.canEarnReward, this.petKind = 'dog'});
  final String petName, petKind;
  final bool canEarnReward;

  @override
  State<PetMemoryGame> createState() => _PetMemoryGameState();
}

class _PetMemoryGameState extends State<PetMemoryGame> {
  final cards = <int>[0, 0, 1, 1, 2, 2]..shuffle();
  final matched = <int>{};
  int? first, second;
  int moves = 0;
  Timer? hideCards;
  static const faces = [
    ('Зірочка', Icons.star_rounded, Color(0xFFE4AE44)),
    ('Сердечко', Icons.favorite_rounded, Color(0xFFDB819B)),
    ('Іграшка', Icons.toys_rounded, Color(0xFF629FBD)),
  ];

  @override
  void dispose() { hideCards?.cancel(); super.dispose(); }

  void reveal(int index) {
    if (second != null || first == index || matched.contains(index)) return;
    setState(() {
      if (first == null) { first = index; return; }
      second = index;
      moves++;
      if (cards[first!] == cards[index]) {
        matched.addAll([first!, index]);
        first = null; second = null;
      } else {
        hideCards = Timer(const Duration(milliseconds: 850), () {
          if (mounted) setState(() { first = null; second = null; });
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final won = matched.length == cards.length;
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6EE),
      appBar: AppBar(title: const Text('Знайди пару')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Center(child: ClipOval(child: Image.asset('assets/pets/${widget.petKind}.webp',
            width: 96, height: 96, fit: BoxFit.contain, excludeFromSemantics: true))),
          const SizedBox(height: 12),
          Text('Граємо разом: ${widget.petName}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Відкривай картки й знайди три пари. Поспішати не потрібно!'),
          const SizedBox(height: 8),
          Text(widget.canEarnReward ? 'Перше завершення сьогодні · +1 ⭐' : 'Грай для задоволення — без обмеження спроб.'),
          const SizedBox(height: 16),
          Text('Знайдено пар: ${matched.length ~/ 2} із 3 · ходів: $moves',
            semanticsLabel: 'Знайдено пар: ${matched.length ~/ 2} із 3, ходів: $moves'),
          const SizedBox(height: 16),
          GridView.count(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10,
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), children: [
            for (var i = 0; i < cards.length; i++) card(i),
          ]),
          if (won) ...[
            const SizedBox(height: 20),
            const Text('Усі пари знайдено! Чудова гра ♡', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(key: const ValueKey('memory-finish'),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check_circle_outline), label: const Text('Готово')),
          ],
        ]),
      ))),
    );
  }

  Widget card(int index) {
    final visible = matched.contains(index) || first == index || second == index;
    final face = faces[cards[index]];
    final label = 'Картка ${index + 1}: ${visible ? face.$1 : 'перевернути'}';
    return Semantics(key: ValueKey('memory-label-$index'), label: label,
      button: true, enabled: !matched.contains(index) && second == null,
      excludeSemantics: true,
      child: OutlinedButton(key: ValueKey('memory-card-$index'),
        onPressed: matched.contains(index) || second != null ? null : () => reveal(index),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(8),
          backgroundColor: visible ? Colors.white : const Color(0xFFDDEFE7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        child: FittedBox(child: Icon(visible ? face.$2 : Icons.pets_rounded,
          size: 42, color: visible ? face.$3 : const Color(0xFF6DAE9B))),
      ),
    );
  }
}

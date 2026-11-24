import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// These buildings are destinations, not fictional listings or other families.
class TownVillage extends StatelessWidget {
  const TownVillage({super.key, required this.openToys, required this.openShop,
    required this.openPet, required this.openGames, required this.theme,
    required this.front, required this.balloons, required this.flowers,
    required this.awning, required this.petName});
  final VoidCallback openToys, openShop, openPet;
  final VoidCallback? openGames;
  final String theme, front, petName;
  final bool balloons, flowers, awning;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Text('Натисни на будиночок і вирушай у пригоду!'),
    const SizedBox(height: 12),
    VillageMap(openToys: openToys, openShop: openShop, openPet: openPet,
      openGames: openGames, theme: theme, front: front, balloons: balloons,
      flowers: flowers, awning: awning),
    const SizedBox(height: 12),
    PetKindnessQuest(petName: petName, openPet: openPet),
    const SizedBox(height: 16),
    Text('Куди підемо?', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    for (final place in [
      ('toys', 'Іграшковий ярмарок', 'Знайди іграшку для дарування, обміну чи купівлі', Icons.toys_rounded, openToys),
      ('shop', 'Моя крамничка', 'Обери кольори, вітрину та прикраси', Icons.storefront_rounded, openShop),
      ('pet', 'Будиночок друга', '$petName чекає на турботу й новий одяг', Icons.pets_rounded, openPet),
      ('games', 'Ігрова галявина', 'Знайди три пари карток разом із другом', Icons.extension_rounded, openGames),
    ]) Card(margin: const EdgeInsets.only(bottom: 10), clipBehavior: Clip.antiAlias,
      child: ListTile(key: ValueKey('village-link-${place.$1}'),
        leading: Icon(place.$4, color: const Color(0xFF568B7B)),
        title: Text(place.$2), subtitle: Text(place.$3),
        trailing: const Icon(Icons.chevron_right_rounded),
        enabled: place.$5 != null, onTap: place.$5)),
  ]);
}

class VillageMap extends StatefulWidget {
  const VillageMap({super.key, required this.openToys, required this.openShop,
    required this.openPet, required this.openGames, required this.theme,
    required this.front, required this.balloons, required this.flowers, required this.awning});
  final VoidCallback openToys, openShop, openPet;
  final VoidCallback? openGames;
  final String theme, front;
  final bool balloons, flowers, awning;
  @override
  State<VillageMap> createState() => _VillageMapState();
}

class _VillageMapState extends State<VillageMap> with TickerProviderStateMixin {
  late final motion = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  late final walk = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  Offset traveler = const Offset(200, 280);
  Offset start = const Offset(200, 280);
  Offset destination = const Offset(200, 280);
  VoidCallback? arrival;
  final Set<int> discovered = <int>{};
  static const _secretsKey = 'toytown.village.discovered.v1';
  bool _secretsReady = false;

  Future<void> loadSecrets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_secretsKey) ?? const <String>[];
      if (!mounted) return;
      setState(() {
        discovered.addAll(stored.map(int.tryParse).whereType<int>()
          .where((value) => value >= 0 && value < treasures.length));
        _secretsReady = true;
      });
    } catch (_) {
      if (mounted) setState(() => _secretsReady = true);
    }
  }

  Future<void> saveSecrets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sorted = discovered.toList()..sort();
      await prefs.setStringList(_secretsKey,
        sorted.map((value) => value.toString()).toList());
    } catch (_) {
      // The adventure remains playable even if device storage is unavailable.
    }
  }

  static const treasures = <({Offset position, String title, String message})>[
    (position: Offset(40, 251), title: 'Метелик дружби',
      message: 'Метелик прилетів привітатися! Ти знайшов перший секрет містечка.'),
    (position: Offset(361, 251), title: 'Чарівна квітка',
      message: 'Квітка розквітла! У ToyTown навіть маленькі відкриття — це пригода.'),
    (position: Offset(200, 464), title: 'Зоряний камінчик',
      message: 'Ти відкрив останній секрет! Усі три скарби містечка знайдено.'),
  ];
  bool get walking => walk.isAnimating;

  void discover(int index) {
    if (walking || !_secretsReady) return;
    final firstDiscovery = discovered.add(index);
    if (firstDiscovery) { setState(() {}); saveSecrets(); }
    final treasure = treasures[index];
    final completedNow = firstDiscovery && discovered.length == treasures.length;
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text(completedNow ? '🏅 Дослідник ToyTown!' : treasure.title),
      content: Text(completedNow
        ? 'Ти знайшов усі три секрети містечка! Вітаємо з відзнакою «Дослідник ToyTown». Вона залишиться з тобою після повторного відкриття гри.\n\nЗнайдено секретів: 3 із 3.'
        : '${treasure.message}\n\nЗнайдено секретів: ${discovered.length} із ${treasures.length}.'),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx),
        child: const Text('Продовжити пригоду'))],
    ));
  }

  void visit(Offset target, VoidCallback? action) {
    if (action == null || walking) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      action();
      return;
    }
    start = traveler;
    destination = target;
    arrival = action;
    walk.forward(from: 0);
  }

  void onWalkStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() => traveler = destination);
    final callback = arrival;
    arrival = null;
    callback?.call();
  }
  @override
  void initState() {
    super.initState();
    walk.addStatusListener(onWalkStatus);
    loadSecrets();
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) { motion.stop(); }
    else if (!motion.isAnimating) { motion.repeat(); }
  }
  @override
  void dispose() { walk.removeStatusListener(onWalkStatus); walk.dispose(); motion.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AspectRatio(aspectRatio: 400 / 480,
    child: LayoutBuilder(builder: (context, constraints) {
      final scale = constraints.maxWidth / 400;
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
      return ClipRRect(borderRadius: BorderRadius.circular(32), child: Stack(children: [
        Positioned.fill(child: ExcludeSemantics(child: CustomPaint(painter: _VillagePainter(
          motion: motion, theme: widget.theme, front: widget.front,
          balloons: widget.balloons, flowers: widget.flowers, awning: widget.awning)))),
        AnimatedBuilder(animation: walk, builder: (context, child) {
          final position = Offset.lerp(start, destination, Curves.easeInOut.transform(walk.value))!;
          final point = walk.isAnimating ? position : traveler;
          return Positioned(
            left: (point.dx - 22) * scale,
            top: (point.dy - 49 - (walk.isAnimating ? math.sin(walk.value * math.pi * 8).abs() * 4 : 0)) * scale,
            width: 44 * scale, height: 52 * scale,
            child: IgnorePointer(child: Semantics(
              label: 'Пухнастий мандрівник іде до будиночка',
              child: CustomPaint(
                key: const ValueKey('village-traveler'),
                painter: _TravelerPainter(
                  walking: walk.isAnimating,
                  step: walk.value,
                  facingRight: destination.dx >= start.dx,
                ),
              ),
            )),
          );
        }),
        if (discovered.length == treasures.length)
          Positioned(
            left: 103 * scale, top: 38 * scale,
            width: 194 * scale, height: 28 * scale,
            child: IgnorePointer(child: DecoratedBox(
              decoration: BoxDecoration(color: const Color(0xFFFFF1C2),
                borderRadius: BorderRadius.circular(18)),
              child: Center(child: Text('🏅 Дослідник ToyTown',
                key: const ValueKey('village-explorer-badge'),
                style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.bold,
                  color: const Color(0xFF77531C)))),
            )),
          ),
        Positioned(
          left: 116 * scale, top: 6 * scale,
          width: 170 * scale, height: 32 * scale,
          child: IgnorePointer(child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(18)),
            child: Center(child: Text('✨ Секрети: ${discovered.length}/3',
              key: const ValueKey('village-secret-progress'),
              style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w700,
                color: const Color(0xFF65518A)))),
          )),
        ),
        for (var i = 0; i < treasures.length; i++)
          Positioned(
            left: (treasures[i].position.dx - 17) * scale,
            top: (treasures[i].position.dy - 17) * scale,
            width: 34 * scale, height: 34 * scale,
            child: Semantics(button: true, label: treasures[i].title,
              child: Material(color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('village-secret-$i'),
                  onTap: () => discover(i),
                  borderRadius: BorderRadius.circular(18),
                  child: Center(child: Icon(
                    discovered.contains(i) ? Icons.check_circle_rounded
                      : (i == 0 ? Icons.flutter_dash_rounded
                        : i == 1 ? Icons.local_florist_rounded : Icons.star_rounded),
                    size: 23 * scale,
                    color: discovered.contains(i) ? const Color(0xFF458B77)
                      : const Color(0xFFE1A452),
                  )),
                ),
              )),
          ),
        Positioned.fromRect(
          rect: Rect.fromLTWH(163 * scale, 230 * scale, 74 * scale, 57 * scale),
          child: Semantics(
            button: true,
            label: 'Фонтан бажань у центрі містечка',
            child: Material(color: Colors.transparent,
              child: InkWell(
                key: const ValueKey('village-fountain'),
                borderRadius: BorderRadius.circular(30),
                onTap: () => showDialog<void>(context: context, builder: (dialogContext) =>
                  AlertDialog(
                    title: const Text('⛲ Фонтан бажань'),
                    content: const Text('Ти знайшов чарівний фонтан! У ToyTown на тебе чекають ігри, турбота про улюбленця та власна крамничка. Обери свою наступну пригоду.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Повернутися')),
                      FilledButton(
                        onPressed: widget.openGames == null ? null : () {
                          Navigator.pop(dialogContext);
                          widget.openGames!();
                        },
                        child: const Text('До ігор'),
                      ),
                    ],
                  )),
              ),
            ),
          ),
        ),
        for (final place in [
          ('toys', 'Іграшки', 'Іграшковий ярмарок', const Rect.fromLTWH(15, 65, 175, 175), widget.openToys),
          ('shop', 'Крамничка', 'Моя крамничка', const Rect.fromLTWH(210, 65, 175, 175), widget.openShop),
          ('pet', 'Улюбленець', 'Будиночок друга', const Rect.fromLTWH(15, 270, 175, 180), widget.openPet),
          ('games', 'Ігри', 'Ігрова галявина', const Rect.fromLTWH(210, 270, 175, 180), widget.openGames),
        ]) Positioned.fromRect(rect: Rect.fromLTWH(place.$4.left * scale, place.$4.top * scale,
          place.$4.width * scale, place.$4.height * scale),
          child: Semantics(button: true, label: place.$3, enabled: place.$5 != null,
            child: Material(color: Colors.transparent, child: InkWell(
              key: ValueKey('village-door-${place.$1}'),
              onTap: place.$5 == null ? null : () => visit(
                Offset(place.$4.center.dx, place.$4.bottom - 28), place.$5),
              borderRadius: BorderRadius.circular(22),
              child: Align(alignment: Alignment.bottomCenter,
                child: Padding(padding: EdgeInsets.only(bottom: 4 * scale),
                  child: ExcludeSemantics(child: largeText
                    ? Icon(Icons.arrow_circle_right_rounded, color: place.$5 == null ? Colors.grey : const Color(0xFF427569))
                    : Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(12)),
                      child: Text(place.$2, textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF426D63))))))),
            )))),
      ]));
    }),
  );
}

class _VillagePainter extends CustomPainter {
  _VillagePainter({required this.motion, required this.theme, required this.front,
    required this.balloons, required this.flowers, required this.awning}) : super(repaint: motion);
  final Animation<double> motion;
  final String theme, front;
  final bool balloons, flowers, awning;

  @override
  void paint(Canvas c, Size size) {
    c.scale(size.width / 400, size.height / 480);
    final p = Paint();
    c.drawRect(const Rect.fromLTWH(0, 0, 400, 480), p..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFFD9F2F7), Color(0xFFF5FAE9)]).createShader(const Rect.fromLTWH(0, 0, 400, 480)));
    p.shader = null;
    c.drawCircle(const Offset(339, 36), 22, p..color = const Color(0xFFFFD77E));
    final drift = math.sin(motion.value * math.pi * 2) * 3;
    for (final pos in [Offset(51 + drift, 33), Offset(230 - drift, 23)]) {
      c.drawOval(Rect.fromCenter(center: pos, width: 63, height: 18), p..color = Colors.white);
      c.drawCircle(pos + const Offset(-6, -5), 13, p);
      c.drawCircle(pos + const Offset(10, -4), 10, p);
    }
    c.drawOval(const Rect.fromLTWH(-100, 145, 580, 440), p..color = const Color(0xFFCEE6C7));
    c.drawOval(const Rect.fromLTWH(10, 190, 490, 330), p..color = const Color(0xFFBFE0BE));
    final paths = Path()..moveTo(95, 174)..quadraticBezierTo(200, 280, 302, 174)
      ..moveTo(95, 369)..quadraticBezierTo(200, 249, 302, 369)
      ..moveTo(200, 253)..lineTo(200, 480);
    c.drawPath(paths, p..color = const Color(0xFFF7E9CB)..strokeWidth = 29..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
    p.style = PaintingStyle.fill;
    // A central fountain and garden connect the four real app destinations.
    c.drawOval(const Rect.fromLTWH(162, 239, 76, 33), p..color = const Color(0xFFA3C2B2));
    c.drawOval(const Rect.fromLTWH(167, 241, 66, 23), p..color = const Color(0xFF91D2DF));
    c.drawCircle(const Offset(200, 245), 9, p..color = const Color(0xFFE7F8F8));
    final wave = math.sin(motion.value * math.pi * 2);
    for (var i = -1; i <= 1; i++) {
      c.drawCircle(Offset(200.0 + i * 10, 225 + wave * 3 - (i == 0 ? 8 : 0)), 3, p..color = const Color(0xFF78C1D7));
    }
    for (final pos in const [Offset(24, 253), Offset(371, 255), Offset(41, 445), Offset(355, 447)]) tree(c, pos);
    building(c, const Offset(101, 151), const Color(0xFFEA9E91), 0);
    final ownColor = theme == 'lavender' ? const Color(0xFFA899CD) : theme == 'sunset' ? const Color(0xFFE6AB76) : const Color(0xFF79BAAB);
    building(c, const Offset(299, 151), ownColor, 1);
    building(c, const Offset(101, 354), const Color(0xFF91B8D4), 2);
    building(c, const Offset(299, 354), const Color(0xFFD2B2D5), 3);
    for (final pos in const [Offset(146, 449), Offset(254, 444), Offset(154, 57), Offset(25, 87)]) {
      c.drawCircle(pos, 4, p..color = const Color(0xFFF1B4BB));
      c.drawCircle(pos + const Offset(5, 0), 3, p);
      c.drawCircle(pos + const Offset(2, 4), 3, p);
      c.drawCircle(pos + const Offset(2, 1), 2, p..color = const Color(0xFFFFE797));
    }
  }

  void tree(Canvas c, Offset pos) {
    final p = Paint()..color = const Color(0xFFB28E70);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: pos, width: 7, height: 31), const Radius.circular(3)), p);
    p.color = const Color(0xFF83BC94);
    c.drawCircle(pos + const Offset(0, -21), 15, p);
    c.drawCircle(pos + const Offset(-11, -13), 12, p);
    c.drawCircle(pos + const Offset(11, -13), 12, p);
  }

  void building(Canvas c, Offset center, Color roof, int kind) {
    c.save(); c.translate(center.dx - 60, center.dy - 60);
    final p = Paint();
    c.drawOval(const Rect.fromLTWH(-6, 108, 132, 15), p..color = const Color(0xFF598D73).withValues(alpha: .13));
    final walls = RRect.fromRectAndRadius(const Rect.fromLTWH(4, 31, 112, 79), const Radius.circular(9));
    c.drawShadow(Path()..addRRect(walls), const Color(0xFF6D8674), 4, false);
    c.drawRRect(walls, p..color = const Color(0xFFFFF7E3));
    final top = Path()..moveTo(-5, 35)..lineTo(16, 8)..quadraticBezierTo(60, -3, 104, 8)..lineTo(125, 35)..close();
    c.drawPath(top, p..color = roof);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(13, 52, 53, 40), const Radius.circular(7)), p..color = const Color(0xFFD4EEF0));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(77, 49, 26, 61), const Radius.circular(6)), p..color = roof);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(81, 56, 18, 27), const Radius.circular(4)), p..color = const Color(0xFFE6F7F0));
    c.drawCircle(const Offset(98, 92), 2, p..color = const Color(0xFFFFDF8A));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(31, 15, 58, 16), const Radius.circular(6)), p..color = Colors.white);
    if (kind == 0) {
      for (var i = 0; i < 3; i++) c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(19 + i * 14.0, 72.0 - (i % 2) * 9, 11, 13), const Radius.circular(2)), p..color = [const Color(0xFFEB9C91), const Color(0xFFFFCF74), const Color(0xFFA5B2D7)][i]);
      star(c, const Offset(60, 23), 6, roof);
    } else if (kind == 1) {
      for (var i = 0; i < 6; i++) c.drawRect(Rect.fromLTWH(6 + i * 18.0, 36, 18, 9), p..color = i.isEven ? (awning ? const Color(0xFFEF9E90) : roof) : const Color(0xFFFFF8E7));
      if (front == 'stars') { star(c, const Offset(60, 23), 6, const Color(0xFFE4B24C)); star(c, const Offset(39, 71), 10, const Color(0xFFE4B24C)); }
      else if (front == 'clouds') { c.drawOval(const Rect.fromLTWH(24, 65, 30, 12), p..color = Colors.white); c.drawCircle(const Offset(36, 65), 8, p); }
      else { c.drawRect(const Rect.fromLTWH(24, 72, 13, 13), p..color = roof); c.drawCircle(const Offset(48, 77), 7, p..color = const Color(0xFFFFCF74)); }
      if (flowers) for (final x in [3.0, 110.0]) {
        c.drawRect(Rect.fromLTWH(x, 101, 9, 10), p..color = const Color(0xFFCE8B70));
        c.drawCircle(Offset(x + 4, 97), 6, p..color = const Color(0xFFEC9BAC));
      }
      if (balloons) for (var i = 0; i < 2; i++) {
        final x = i == 0 ? -8.0 : 128.0;
        c.drawLine(Offset(x, 59), Offset(x + (i == 0 ? 10 : -10), 104), p..color = const Color(0xFF86AFA1)..strokeWidth = 1);
        c.drawOval(Rect.fromCenter(center: Offset(x, 48), width: 16, height: 22), p..color = i == 0 ? const Color(0xFFF2A0AA) : const Color(0xFFFFD681));
      }
    } else if (kind == 2) {
      c.drawOval(const Rect.fromLTWH(29, 74, 22, 16), p..color = roof);
      for (final pos in const [Offset(29, 67), Offset(39, 62), Offset(50, 67)]) c.drawCircle(pos, 5, p);
      c.drawCircle(const Offset(60, 23), 5, p);
    } else {
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(24, 61, 23, 29), const Radius.circular(4)), p..color = const Color(0xFFEFCB78));
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(35, 65, 23, 29), const Radius.circular(4)), p..color = const Color(0xFFE2B3C6));
      star(c, const Offset(46, 79), 6, Colors.white);
      star(c, const Offset(60, 23), 6, roof);
    }
    c.restore();
  }

  void star(Canvas c, Offset pos, double radius, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? radius : radius * .45;
      final x = pos.dx + math.cos(angle) * r, y = pos.dy + math.sin(angle) * r;
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close(); c.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _VillagePainter old) => old.theme != theme || old.front != front ||
    old.balloons != balloons || old.flowers != flowers || old.awning != awning || old.motion != motion;
}

/// A small original illustrated animal companion, drawn without extra assets.
class _TravelerPainter extends CustomPainter {
  const _TravelerPainter({required this.walking, required this.step, required this.facingRight});
  final bool walking, facingRight;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 44, size.height / 52);
    if (!facingRight) {
      canvas.translate(44, 0);
      canvas.scale(-1, 1);
    }
    final fur = Paint()..color = const Color(0xFFF1B78B);
    final ear = Paint()..color = const Color(0xFFE58F9D);
    final outline = Paint()..color = const Color(0xFF715B67);
    final bounce = walking ? math.sin(step * math.pi * 8) * 2 : 0.0;
    canvas.drawOval(const Rect.fromLTWH(8, 44, 28, 5), Paint()..color = const Color(0xFF618B74).withValues(alpha: .20));
    canvas.translate(0, -bounce);
    canvas.drawOval(const Rect.fromLTWH(10, 23, 24, 23), fur);
    final stride = walking ? math.sin(step * math.pi * 8) * 3 : 0.0;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(12 + stride, 40, 8, 9), const Radius.circular(4)), fur);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(24 - stride, 40, 8, 9), const Radius.circular(4)), fur);
    canvas.drawOval(const Rect.fromLTWH(5, 4, 13, 24), fur);
    canvas.drawOval(const Rect.fromLTWH(26, 4, 13, 24), fur);
    canvas.drawOval(const Rect.fromLTWH(9, 8, 6, 15), ear);
    canvas.drawOval(const Rect.fromLTWH(30, 8, 6, 15), ear);
    canvas.drawCircle(const Offset(22, 25), 17, fur);
    canvas.drawOval(const Rect.fromLTWH(14, 27, 16, 11), Paint()..color = const Color(0xFFFFE5CF));
    canvas.drawCircle(const Offset(16, 23), 2, outline);
    canvas.drawCircle(const Offset(28, 23), 2, outline);
    canvas.drawCircle(const Offset(22, 29), 2.5, outline);
    final scarf = Path()..moveTo(9, 37)..quadraticBezierTo(22, 42, 35, 37)
      ..lineTo(34, 41)..quadraticBezierTo(22, 46, 10, 41)..close();
    canvas.drawPath(scarf, Paint()..color = const Color(0xFF8875CB));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TravelerPainter oldDelegate) =>
      oldDelegate.walking != walking || oldDelegate.step != step ||
      oldDelegate.facingRight != facingRight;
}

/// A gentle, one-time companion quest. This is a cosmetic achievement:
/// it does not mint marketplace stars or modify the protected wallet.
class PetKindnessQuest extends StatefulWidget {
  const PetKindnessQuest({super.key, required this.petName, required this.openPet});
  final String petName;
  final VoidCallback openPet;

  @override
  State<PetKindnessQuest> createState() => _PetKindnessQuestState();
}

class _PetKindnessQuestState extends State<PetKindnessQuest> {
  static const _questKey = 'toytown.quest.kindness.v1';
  bool _ready = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _completed = prefs.getBool(_questKey) ?? false;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _complete() async {
    if (!_ready || _completed) return;
    setState(() => _completed = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_questKey, true);
    } catch (_) {
      // The quest can still be enjoyed when local storage is unavailable.
    }
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('💛 Добрий друг ToyTown'),
      content: Text('Ти подбав про ${widget.petName}! Тепер у твоїй колекції є відзнака доброти.'),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx),
        child: const Text('Чудово!'))],
    ));
  }

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey('village-kindness-quest'),
    color: const Color(0xFFFFF3DE),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_completed ? Icons.workspace_premium_rounded : Icons.favorite_rounded,
            color: const Color(0xFFB76D69)),
          const SizedBox(width: 8),
          Expanded(child: Text(_completed ? '🏅 Добрий друг ToyTown'
            : 'Завдання: подбай про друга',
            style: const TextStyle(fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 4),
        Text(_completed
          ? '${widget.petName} відчуває твою турботу. Відзнаку збережено!'
          : 'Подаруй ${widget.petName} трохи уваги та отримай відзнаку доброти.'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          if (!_completed)
            FilledButton.icon(
              key: const ValueKey('village-kindness-complete'),
              onPressed: _ready ? _complete : null,
              icon: const Icon(Icons.favorite_outline_rounded),
              label: const Text('Погладити друга')),
          OutlinedButton(
            onPressed: widget.openPet,
            child: const Text('До улюбленця')),
        ]),
      ]),
    ),
  );
}

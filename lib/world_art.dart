import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Raster fur sprites with lightweight transforms; no video/network dependency.
class PetScene extends StatefulWidget {
  const PetScene({super.key, required this.kind, required this.name, required this.grown,
    required this.hat, required this.bow, required this.outfit});
  final String kind, name, outfit;
  final bool grown, hat, bow;
  @override
  State<PetScene> createState() => _PetSceneState();
}
class _PetSceneState extends State<PetScene> with TickerProviderStateMixin {
  late final idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final delight = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) { idle.stop(); delight.stop(); }
    else if (!idle.isAnimating) { idle.repeat(reverse: true); }
  }
  @override
  void dispose() { idle.dispose(); delight.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${widget.name}, ${widget.kind == 'cat' ? 'котик' : widget.kind == 'bunny' ? 'зайчик' : 'песик'}. Натисніть, щоб погладити.',
    button: true,
    child: GestureDetector(onTap: () { if (!MediaQuery.disableAnimationsOf(context)) delight.forward(from: 0); },
      child: Container(height: 320, clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF8EAD9),Color(0xFFE4F5EE)])),
        child: AnimatedBuilder(animation: Listenable.merge([idle,delight]), builder: (context, _) {
          final reduced = MediaQuery.disableAnimationsOf(context);
          final breathe = reduced ? 0.0 : math.sin(idle.value * math.pi);
          final jump = reduced ? 0.0 : math.sin(delight.value * math.pi);
          return Stack(alignment: Alignment.center, children: [
            Positioned(top: 20, left: 24, child: Icon(Icons.wb_sunny_rounded, size: 42, color: const Color(0xFFF4C56B).withValues(alpha: .6))),
            Positioned(bottom: 0, left: 0, right: 0, height: 70, child: Container(decoration: const BoxDecoration(color: Color(0xFFCAE5D1), borderRadius: BorderRadius.vertical(top: Radius.elliptical(300,50))))),
            Positioned(bottom: 14, child: Container(width: 170-jump*15, height: 24, decoration: BoxDecoration(color: const Color(0xFF597F6C).withValues(alpha: .12), borderRadius: BorderRadius.circular(100)))),
            Transform.translate(offset: Offset(0, 4-breathe*4-jump*18), child: Transform.rotate(angle: jump*.04,
              child: Transform.scale(scale: (widget.grown ? 1.0 : .94)+breathe*.008,
                child: SizedBox(
                  width: math.min(290.0, math.max(0.0, MediaQuery.sizeOf(context).width - 56)),
                  height: math.min(290.0, math.max(0.0, MediaQuery.sizeOf(context).width - 56)),
                  child: Stack(children: [
                  Positioned.fill(child: Image.asset('assets/pets/${widget.kind}.webp', fit: BoxFit.contain, excludeFromSemantics: true)),
                  Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _PetClothes(kind: widget.kind, hat: widget.hat, bow: widget.bow, outfit: widget.outfit)))),
                ]))))),
            if (jump > .05) Positioned(top: 32-jump*15, right: 54, child: Opacity(opacity: jump.clamp(0.0,1.0).toDouble(), child: const Icon(Icons.favorite_rounded,color:Color(0xFFE98599),size:32))),
            const Positioned(bottom: 7, right: 14, child: Text('Погладь мене ♡',style:TextStyle(fontSize:12,color:Color(0xFF456555)))),
          ]);
        }),
      ),
    ),
  );
}
class _PetClothes extends CustomPainter {
  _PetClothes({required this.kind,required this.hat,required this.bow,required this.outfit});
  final String kind,outfit;
  final bool hat,bow;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width/300,size.height/300);
    final neck = kind=='bunny' ? 190.0 : kind=='cat' ? 149.0 : 139.0;
    if(outfit!='none') {
      final color=outfit=='mint'?const Color(0xFF65BDA9):const Color(0xFFEE8F82);
      final shirt=Path()..moveTo(120,neck+3)..quadraticBezierTo(150,neck+20,180,neck+3)
        ..lineTo(199,neck+25)..lineTo(186,neck+42)..lineTo(178,neck+34)
        ..lineTo(181,259)..quadraticBezierTo(150,271,119,259)..lineTo(122,neck+34)
        ..lineTo(114,neck+42)..lineTo(101,neck+25)..close();
      final rect=Rect.fromLTRB(102,neck,199,267);
      canvas.drawShadow(shirt,Colors.black26,2,false);
      canvas.drawPath(shirt,Paint()..shader=LinearGradient(colors:[color,Color.lerp(color,Colors.white,.3)!,color]).createShader(rect));
      canvas.drawPath(shirt,Paint()..color=Color.lerp(color,Colors.black,.15)!..style=PaintingStyle.stroke..strokeWidth=1.2);
      canvas.drawArc(Rect.fromLTWH(121,neck-3,58,23),0,math.pi,false,Paint()..color=Colors.white70..style=PaintingStyle.stroke..strokeWidth=3);
      _star(canvas,Offset(150,(neck+260)/2),10,const Color(0xFFFFE4A1));
    }
    if(bow) {
      final y=neck+5;
      final left=Path()..moveTo(148,y)..quadraticBezierTo(118,y-19,120,y+2)..quadraticBezierTo(118,y+23,148,y+6)..close();
      final right=Path()..moveTo(152,y)..quadraticBezierTo(182,y-19,180,y+2)..quadraticBezierTo(182,y+23,152,y+6)..close();
      canvas.drawShadow(left,Colors.black26,2,false);canvas.drawShadow(right,Colors.black26,2,false);
      final paint=Paint()..color=const Color(0xFFBE6B99);canvas.drawPath(left,paint);canvas.drawPath(right,paint);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center:Offset(150,y+3),width:13,height:17),const Radius.circular(4)),Paint()..color=const Color(0xFFEDB5CE));
    }
    if(hat) {
      final y=kind=='bunny'?91.0:kind=='cat'?32.0:18.0;
      final crown=Path()..moveTo(120,y+24)..lineTo(124,y-5)..quadraticBezierTo(150,y-18,176,y-5)..lineTo(180,y+24)..close();
      canvas.drawShadow(crown,Colors.black26,3,false);
      canvas.drawPath(crown,Paint()..shader=const LinearGradient(colors:[Color(0xFFE9B968),Color(0xFFFFE1A0),Color(0xFFE9B968)]).createShader(Rect.fromLTWH(120,y-10,60,40)));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(107,y+19,86,14),const Radius.circular(9)),Paint()..color=const Color(0xFFF2CE89));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(121,y+11,58,8),const Radius.circular(3)),Paint()..color=const Color(0xFF6CB7A4));
    }
  }
  @override
  bool shouldRepaint(covariant _PetClothes old)=>old.kind!=kind||old.hat!=hat||old.bow!=bow||old.outfit!=outfit;
}
void _star(Canvas c,Offset center,double r,Color color) {
 final path=Path();for(var i=0;i<10;i++){final a=-math.pi/2+i*math.pi/5;final v=i.isEven?r:r*.45;final p=center+Offset(math.cos(a)*v,math.sin(a)*v);if(i==0){path.moveTo(p.dx,p.dy);}else{path.lineTo(p.dx,p.dy);}}path.close();c.drawPath(path,Paint()..color=color);
}

class ShopScene extends StatefulWidget {
 const ShopScene({super.key,required this.balloons,required this.flowers,required this.awning,this.onTap});
 final bool balloons,flowers,awning;
 final VoidCallback? onTap;
 @override
 State<ShopScene> createState()=>_ShopSceneState();
}
class _ShopSceneState extends State<ShopScene> with SingleTickerProviderStateMixin {
 late final motion=AnimationController(vsync:this,duration:const Duration(seconds:4));
 @override
 void didChangeDependencies(){super.didChangeDependencies();if(MediaQuery.disableAnimationsOf(context)){motion.stop();}else if(!motion.isAnimating){motion.repeat();}}
 @override
 void dispose(){motion.dispose();super.dispose();}
 @override
 Widget build(BuildContext context)=>Semantics(label:'Світла іграшкова крамничка${widget.balloons?', з кульками':''}${widget.flowers?', з квітами':''}${widget.awning?', з барвистим навісом':''}',button:widget.onTap!=null,
 child:GestureDetector(onTap:widget.onTap,child:AspectRatio(aspectRatio:1.25,child:ClipRRect(borderRadius:BorderRadius.circular(30),
 child:AnimatedBuilder(animation:motion,builder:(context,_)=>CustomPaint(painter:_ShopPainter(balloons:widget.balloons,flowers:widget.flowers,awning:widget.awning,t:MediaQuery.disableAnimationsOf(context)?0:motion.value)))))));
}
class _ShopPainter extends CustomPainter {
 _ShopPainter({required this.balloons,required this.flowers,required this.awning,required this.t});
 final bool balloons,flowers,awning;final double t;
 @override
 void paint(Canvas c,Size s){
 c.scale(s.width/400,s.height/320);
 final p=Paint();
 c.drawRect(const Rect.fromLTWH(0,0,400,320),p..shader=const LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xFFD8F3FB),Color(0xFFFFF8E6)]).createShader(const Rect.fromLTWH(0,0,400,320)));p.shader=null;
 c.drawCircle(const Offset(340,49),25,p..color=const Color(0xFFFFDA7D));
 for(final pos in const [Offset(38,50),Offset(259,27)]) {c.drawOval(Rect.fromCenter(center:pos,width:60,height:20),p..color=Colors.white.withValues(alpha:.8));c.drawCircle(pos+const Offset(0,-7),14,p);}
 c.drawOval(const Rect.fromLTWH(-55,239,520,160),p..color=const Color(0xFFBEE3C6));
 c.drawOval(const Rect.fromLTWH(73,278,260,24),p..color=const Color(0xFF518879).withValues(alpha:.12));
 final house=RRect.fromRectAndRadius(const Rect.fromLTWH(92,107,216,173),const Radius.circular(14));
 c.drawShadow(Path()..addRRect(house),const Color(0xFF6B8779),8,false);c.drawRRect(house,p..color=const Color(0xFFFFF6DF));
 c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(92,252,216,28),const Radius.circular(8)),p..color=const Color(0xFFF0DAB0));
 final roof=Path()..moveTo(77,111)..lineTo(107,78)..quadraticBezierTo(200,62,293,78)..lineTo(323,111)..close();
 c.drawPath(roof,p..color=const Color(0xFF79BAAB));
 c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(145,87,110,29),const Radius.circular(10)),p..color=const Color(0xFFFFFCF1));
 final title=TextPainter(text:const TextSpan(text:'ToyTown',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800,color:Color(0xFF42796E))),textDirection:TextDirection.ltr)..layout();title.paint(c,Offset(200-title.width/2,91));
 // Display window with small toy blocks, and a sunlit doorway.
 c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(110,155,99,82),const Radius.circular(10)),p..color=const Color(0xFFCAE9EE));
 c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(116,161,87,70),const Radius.circular(6)),p..color=const Color(0xFFE8F6F4));
 c.drawLine(const Offset(159,159),const Offset(159,234),p..color=const Color(0xFF92C7BC)..strokeWidth=4);
 c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(227,151,60,124),const Radius.circular(13)),p..color=const Color(0xFF79BCAF));
 c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(235,160,44,69),const Radius.circular(9)),p..color=const Color(0xFFD9F0EA));
 c.drawCircle(const Offset(275,239),3,p..color=const Color(0xFFFFDE8A));
 for(var i=0;i<3;i++){c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(123.0+i*23,211.0-i%2*14,19,18),const Radius.circular(3)),p..color=[const Color(0xFFEA9C91),const Color(0xFFFFD16F),const Color(0xFF9EC2D8)][i]);}
 // A striped canopy makes an actual visible change when purchased.
 for(var i=0;i<8;i++){final x=99+i*25.0;final color=awning?(i.isEven?const Color(0xFFEF9E90):const Color(0xFFFFF5DC)):(i.isEven?const Color(0xFF88C7B7):const Color(0xFFE6F2E8));c.drawRect(Rect.fromLTWH(x,121,25,23),p..color=color);c.drawArc(Rect.fromLTWH(x,134,25,19),0,math.pi,true,p);}
 if(flowers){for(final x in [106.0,299.0]){c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x-12,262,24,20),const Radius.circular(4)),p..color=const Color(0xFFCE8B70));for(var j=0;j<3;j++){final xx=x-9+j*9;c.drawLine(Offset(xx,265),Offset(xx,246.0-j%2*6),p..color=const Color(0xFF5B9D78)..strokeWidth=2);for(var k=0;k<5;k++){final a=k*2*math.pi/5;c.drawCircle(Offset(xx+math.cos(a)*4,246.0-j%2*6+math.sin(a)*4),3.6,p..color=j.isEven?const Color(0xFFED9BAE):const Color(0xFFFFD27A));}c.drawCircle(Offset(xx,246.0-j%2*6),2,p..color=const Color(0xFFFFF3C8));}}}
 if(balloons){for(var i=0;i<4;i++){final x=i<2?48.0+i*23:327.0+(i-2)*23;final sway=math.sin(t*math.pi*2+i)*4;final y=128.0+(i%2)*19;c.drawLine(Offset(x+sway,y+20),Offset(i<2?83:317,259),p..color=const Color(0xFF9AB4B4)..strokeWidth=1);c.drawOval(Rect.fromCenter(center:Offset(x+sway,y),width:29,height:39),p..color=[const Color(0xFFEF9C9E),const Color(0xFFFFD882),const Color(0xFFA5C6F0),const Color(0xFFC3B2DD)][i]);c.drawOval(Rect.fromLTWH(x+sway-7,y-13,5,9),p..color=Colors.white54);}}
 c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(216,277,83,7),const Radius.circular(3)),p..color=const Color(0xFFF6E7CC));
 }
 @override
 bool shouldRepaint(covariant _ShopPainter old)=>old.balloons!=balloons||old.flowers!=flowers||old.awning!=awning||old.t!=t;
}

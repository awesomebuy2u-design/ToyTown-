import 'dart:convert';
import 'dart:async';
import 'world_art.dart';
import 'daily_pet_tasks.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ToyTownWorld extends StatefulWidget {
  const ToyTownWorld({super.key, required this.openListings, required this.openParent, this.client});
  final SupabaseClient? client;
  final VoidCallback openListings;
  final VoidCallback openParent;

  @override
  State<ToyTownWorld> createState() => _ToyTownWorldState();
}

class _ToyTownWorldState extends State<ToyTownWorld> with WidgetsBindingObserver {
  static const int decorationPrice = 5;
  static const progressKey = 'toytown.world.progress';
  static const ownerKey = 'toytown.world.legacyFamily';
  final storage = SharedPreferencesAsync();
  StreamSubscription<AuthState>? authSubscription;
  bool ready = false, saving = false, canCare = true, cloudStored = false;
  String? error, familyId, accountId;
  Map<String, dynamic>? legacyProgress;
  int generation = 0;
  int tab = 0, stars = 0, careCount = 0;
  int? lastCareDay;
  bool decorated = false, flowers = false, awning = false;
  String petKind = 'dog', petName = 'Дружок', petOutfit = 'none';
  bool petHat = false, petBow = false;
  Map<String, bool> dailyTasks = {};
  String shopTheme = 'mint', lastActivity = 'stroke';
  int reaction = 0;

  bool get online => widget.client?.auth.currentUser != null;

  int get today {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(1970)).inDays;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    accountId = widget.client?.auth.currentUser?.id;
    authSubscription = widget.client?.auth.onAuthStateChange.listen((state) {
      final next = state.session?.user.id;
      if (next != accountId) {
        accountId = next;
        loadProgress();
      }
    }, onError: (Object _) {
      if (mounted) setState(() => error = 'Перевірте з’єднання та оновіть прогрес.');
    });
    loadProgress();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    authSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !saving) loadProgress();
  }

  void applyProgress(Map<String, dynamic> data) {
    if (data['dailyTasks'] is Map) {
      dailyTasks = Map<String, bool>.from(data['dailyTasks'] as Map);
    }
    if (data['shopTheme'] is String) shopTheme = data['shopTheme'] as String;
    stars = (data['stars'] as num?)?.toInt() ?? 0;
    careCount = (data['careCount'] as num?)?.toInt() ?? 0;
    lastCareDay = (data['lastCareDay'] as num?)?.toInt();
    decorated = data['decorated'] == true;
    flowers = data['flowers'] == true; awning = data['awning'] == true;
    petKind = data['petKind'] as String? ?? 'dog';
    petName = data['petName'] as String? ?? 'Дружок';
    petHat = data['petHat'] == true; petBow = data['petBow'] == true;
    petOutfit = data['petOutfit'] as String? ?? 'none';
    familyId = data['familyId'] as String?;
    cloudStored = data['stored'] == true;
    canCare = online ? data['canCare'] == true : (lastCareDay ?? -1) < today;
  }

  bool current(int ticket, String? user) => mounted && ticket == generation && user == widget.client?.auth.currentUser?.id;

  Future<String> guestKey() async => await storage.getString(ownerKey) == null ? progressKey : '$progressKey.guest';

  Future<void> loadProgress() async {
    final ticket = ++generation;
    final user = widget.client?.auth.currentUser?.id;
    setState(() {
      ready = false; saving = false; error = null; legacyProgress = null;
      stars = 0; careCount = 0; lastCareDay = null; decorated = false;
      familyId = null; cloudStored = false;
      dailyTasks = {}; shopTheme = 'mint'; lastActivity = 'stroke'; reaction = 0;
      flowers = false; awning = false; petKind = 'dog'; petName = 'Дружок'; petHat = false; petBow = false; petOutfit = 'none';
    });
    try {
      Map<String, dynamic> data;
      Map<String, dynamic>? local;
      if (user != null) {
        data = Map<String, dynamic>.from(await widget.client!.rpc('daily_family_world'));
        final owner = await storage.getString(ownerKey);
        if (data['stored'] != true && (owner == null || owner == data['familyId'])) {
          final raw = await storage.getString(progressKey);
          if (raw != null) {
            final parsed = Map<String, dynamic>.from(jsonDecode(raw) as Map);
            if (((parsed['careCount'] as num?)?.toInt() ?? 0) > 0) local = parsed;
          }
        }
      } else {
        final raw = await storage.getString(await guestKey());
        data = raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
      if (!current(ticket, user)) return;
      setState(() { applyProgress(data); legacyProgress = local; ready = true; });
    } catch (_) {
      if (current(ticket, user)) setState(() => error = user == null
        ? 'Не вдалося завантажити локальний прогрес.'
        : 'Не вдалося завантажити прогрес родини. Перевірте інтернет і створіть родину в кабінеті батьків.');
    }
  }

  Future<void> act(String action) async {
    if (!ready || saving) return;
    final user = widget.client?.auth.currentUser?.id;
    final ticket = generation;
    final target = familyId;
    setState(() { saving = true; error = null; });
    try {
      Map<String, dynamic> data;
      if (user != null) {
        if (target == null) throw StateError('Family required');
        data = Map<String, dynamic>.from(await widget.client!.rpc('family_world_action', params: {
          'action': action, 'target_family': target,
        }));
      } else {
        data = <String, dynamic>{
          'stars': action == 'care' ? stars + 3 : stars - decorationPrice,
          'careCount': action == 'care' ? careCount + 1 : careCount,
          'lastCareDay': action == 'care' ? today : lastCareDay,
          'decorated': action == 'decorate' || decorated,
        };
        final key = await guestKey();
        if (!current(ticket, user)) return;
        await storage.setString(key, jsonEncode(data));
      }
      if (!current(ticket, user)) return;
      setState(() { applyProgress(data); legacyProgress = null; });
    } catch (_) {
      if (current(ticket, user)) setState(() => error = 'Дію не підтверджено. Оновіть прогрес перед повторною спробою.');
    } finally {
      if (current(ticket, user)) setState(() => saving = false);
    }
  }

  Future<void> importProgress() async {
    final user = widget.client?.auth.currentUser?.id;
    final target = familyId;
    final local = legacyProgress;
    final ticket = generation;
    if (user == null || target == null || local == null || saving || !ready) return;
    setState(() => saving = true);
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Перенести прогрес у цю родину?'),
        content: const Text('Локальний улюбленець, зірочки та прикраса будуть прив’язані до родини поточного акаунта. Перенесення на цьому пристрої доступне лише для однієї родини.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Назад')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Перенести'))],
      ));
      if (confirmed != true || !current(ticket, user)) return;
      final owner = await storage.getString(ownerKey);
      if (owner != null && owner != target) throw StateError('Already assigned');
      await storage.setString(ownerKey, target);
      if (!current(ticket, user)) return;
      final data = Map<String, dynamic>.from(await widget.client!.rpc('family_world_action', params: {
        'action': 'import', 'target_family': target, 'legacy': local,
      }));
      if (current(ticket, user)) setState(() { applyProgress(data); legacyProgress = null; error = null; });
    } catch (_) {
      if (current(ticket, user)) setState(() => error = 'Не вдалося перенести прогрес. Локальні дані збережені — спробуйте ще раз.');
    } finally {
      if (current(ticket, user)) setState(() => saving = false);
    }
  }

  Future<void> care() async {
    if (!canCare) return;
    await act('care');
  }

  Future<void> decorate() async {
    if (decorated || stars < decorationPrice) return;
    await act('decorate');
  }

  Future<void> customize(String choice, String value) async {
    if (!ready || saving || !online || legacyProgress != null || familyId == null) return;
    final ticket = generation;
    final user = widget.client!.auth.currentUser!.id;
    final target = familyId!;
    setState(() { saving = true; error = null; });
    try {
      final data = Map<String, dynamic>.from(await widget.client!.rpc('customize_family_world', params: {
        'target_family': target, 'choice': choice, 'value': value,
      }));
      if (current(ticket, user)) setState(() => applyProgress(data));
    } catch (_) {
      if (current(ticket, user)) setState(() => error = 'Не вдалося зберегти зміну. Оновіть прогрес і перевірте з’єднання та кількість зірочок.');
    } finally {
      if (current(ticket, user)) setState(() => saving = false);
    }
  }

  Future<void> dressPet(String slot, String item) async {
    if (!ready || saving || !online || legacyProgress != null || familyId == null) return;
    final ticket = generation;
    final user = widget.client!.auth.currentUser!.id;
    final target = familyId!;
    setState(() { saving = true; error = null; });
    try {
      final data = Map<String,dynamic>.from(await widget.client!.rpc('dress_family_pet',params:{'target_family':target,'slot':slot,'item':item}));
      if(current(ticket,user))setState(()=>applyProgress(data));
    } catch (_) {
      if(current(ticket,user))setState(()=>error='Не вдалося зберегти одяг. Перевірте з’єднання й оновіть прогрес.');
    } finally {
      if(current(ticket,user))setState(()=>saving=false);
    }
  }

  Future<void> dailyAction(String action) async {
    if (!ready || saving || !online || legacyProgress != null || familyId == null) return;
    final ticket = generation;
    final user = widget.client!.auth.currentUser!.id;
    final target = familyId!;
    setState(() { saving = true; error = null; });
    try {
      final data = Map<String, dynamic>.from(await widget.client!.rpc('daily_family_world', params: {
        'target_family': target, 'action': action,
      }));
      if (!current(ticket, user)) return;
      setState(() {
        applyProgress(data);
        if (data['rewarded'] == true) { lastActivity = action; reaction++; }
      });
      if (['feed', 'play', 'brush'].contains(action)) {
        final message = data['rewarded'] == true
          ? '${action == 'feed' ? 'Друг смачно поїв' : action == 'play' ? 'Весела гра завершена' : 'Друг тепер причепурений'} · +1 ⭐'
          : 'Це завдання вже виконано сьогодні ♡';
        ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (current(ticket, user)) setState(() => error = 'Не вдалося зберегти дію. Перевірте інтернет та оновіть прогрес.');
    } finally {
      if (current(ticket, user)) setState(() => saving = false);
    }
  }

  Widget dailyAdventures() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    DailyPetTasks(completed: dailyTasks,
      enabled: ready && !saving && online && familyId != null && legacyProgress == null,
      onAction: dailyAction),
    if (!online) TextButton(onPressed: widget.openParent,
      child: const Text('Увійти, щоб виконувати завдання та отримувати зірочки')),
  ]);

  Widget shopThemes() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 16),
    Text('Кольори крамнички', style: Theme.of(context).textTheme.titleLarge),
    const Text('Три безкоштовні оформлення'),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final theme in const [('mint', 'М’ятна'), ('lavender', 'Лавандова'), ('sunset', 'Сонячна')])
        ChoiceChip(label: Text(theme.$2), selected: shopTheme == theme.$1,
          onSelected: ready && !saving && online && legacyProgress == null && familyId != null
            ? (_) => dailyAction('theme_${theme.$1}') : null),
    ]),
    if (!online) const Text('Увійдіть у родину, щоб обрати й зберегти оформлення.'),
  ]);

  Widget wardrobe() {
    final enabled=ready&&!saving&&online&&legacyProgress==null;
    return Container(margin:const EdgeInsets.symmetric(vertical:16),padding:const EdgeInsets.all(16),
      decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(24)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Гардероб друга',style:Theme.of(context).textTheme.titleLarge),
        const Text('Стартова колекція · безкоштовно',style:TextStyle(color:Color(0xFF578577))),
        const SizedBox(height:12),
        Wrap(spacing:8,runSpacing:8,children:[
          for(final option in const [('none','Без одягу'),('mint','М’ятний одяг'),('coral','Кораловий одяг')])
            ChoiceChip(label:Text(option.$2),selected:petOutfit==option.$1,onSelected:enabled?(_)=>dressPet('outfit',option.$1):null),
          FilterChip(label:const Text('Панамка'),selected:petHat,onSelected:enabled?(v)=>dressPet('hat',v?'on':'off'):null),
          FilterChip(label:const Text('Бантик'),selected:petBow,onSelected:enabled?(v)=>dressPet('bow',v?'on':'off'):null),
        ]),
        if(!online)const Padding(padding:EdgeInsets.only(top:8),child:Text('Увійдіть у родину, щоб зберігати гардероб.')),
      ]));
  }

  Future<void> renamePet() async {
    final ticket = generation;
    final user = widget.client?.auth.currentUser?.id;
    final name = await showDialog<String>(context: context, builder: (_) => _PetNameDialog(initialName: petName));
    if (name != null && current(ticket, user)) await customize('name', name);
  }

  Future<void> buyDecoration(String id, String label, int price) async {
    final ticket = generation;
    final user = widget.client?.auth.currentUser?.id;
    final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Додати $label?'), content: Text('Вартість: $price ⭐. Прикраса залишиться у крамничці.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Назад')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Придбати'))],
    ));
    if (approved == true && current(ticket, user)) await customize('decoration', id);
  }

  Widget decorButton(String id, String label, int price, bool owned) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: FilledButton.tonal(
      onPressed: !ready || saving || !online || legacyProgress != null || owned || stars < price ? null : () => buyDecoration(id, label, price),
      child: Text(owned ? '$label · Придбано ✓' : '$label · $price ⭐'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6EE),
      appBar: AppBar(backgroundColor:const Color(0xFFFBF6EE),title: Text('ToyTown · ⭐ $stars'), actions: [IconButton(tooltip: 'Оновити прогрес', onPressed: saving ? null : loadProgress, icon: const Icon(Icons.refresh))]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(online ? (ready ? (cloudStored ? 'Прогрес родини збережено в акаунті' : 'Родину підключено. Новий прогрес зберігатиметься в акаунті.') : 'Завантаження прогресу родини…') : 'Гостьовий прогрес зберігається лише на цьому пристрої.'),
            if (!online) TextButton(onPressed: widget.openParent, child: const Text('Увійти для збереження в акаунті')),
            if (legacyProgress != null) ...[
              const Text('На пристрої є старий прогрес. Перенесіть його перед першим доглядом у цій родині.'),
              FilledButton.tonal(onPressed: saving ? null : importProgress, child: const Text('Перенести локальний прогрес у родину')),
            ],
            if (saving) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            if (!ready && error != null)
              TextButton(onPressed: loadProgress, child: const Text('Повторити')),
            ...(tab == 0 ? [
            Text('Містечко іграшок', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            ShopScene(balloons:decorated,flowers:flowers,awning:awning,theme:shopTheme,onTap:widget.openListings),
            const SizedBox(height:12),
            FilledButton.tonal(onPressed: widget.openListings, child: const Text('🧸 Знайти іграшки')),
            FilledButton.tonal(onPressed: () => setState(() => tab = 1), child: const Text('🐾 Відвідати улюбленця')),
            TextButton(onPressed: widget.openParent, child: const Text('Кабінет батьків')),
          ] : tab == 1 ? [
            Text('Мій улюбленець', style: Theme.of(context).textTheme.headlineMedium),
            PetScene(key:ValueKey(petKind),kind:petKind,name:petName,grown:careCount>=3,hat:petHat,bow:petBow,outfit:petOutfit,activity:lastActivity,reaction:reaction),
            const SizedBox(height:12),
            Text(petName, style: Theme.of(context).textTheme.headlineSmall),
            if (!online) const Text('Увійдіть у родину, щоб обрати друга й дати йому ім’я.'),
            Wrap(spacing: 8, children: [
              for (final option in const [('dog', '🐶 Песик'), ('cat', '🐱 Котик'), ('bunny', '🐰 Зайчик')])
                ChoiceChip(label: Text(option.$2), selected: petKind == option.$1,
                  onSelected: !ready || saving || !online || legacyProgress != null ? null : (_) => customize('pet', option.$1)),
            ]),
            TextButton.icon(onPressed: !ready || saving || !online || legacyProgress != null ? null : renamePet,
              icon: const Icon(Icons.edit_outlined), label: const Text('Змінити ім’я')),
            dailyAdventures(),
            wardrobe(),
            Text(careCount >= 3 ? 'Улюбленець підріс!' : 'Догляд до дорослішання: $careCount із 3 днів'),
            FilledButton(
              onPressed: !ready || saving || !canCare || legacyProgress != null ? null : care,
              child: Text(!canCare ? 'Наступний догляд завтра' : 'Подбати про улюбленця · +3 ⭐'),
            ),
          ] : [
            Text('Моя крамничка', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height:12),
            ShopScene(balloons:decorated,flowers:flowers,awning:awning,theme:shopTheme,onTap:widget.openListings),
            const SizedBox(height:12),
            shopThemes(),
            const SizedBox(height: 12),
            const Text('Твоя крамничка — місце нових знайомств та іграшок. Додай їй власний настрій!',style:TextStyle(color:Color(0xFF587E73))),
            if (online) ...[
              const SizedBox(height: 12),
              const Text('Прикраси для крамнички'),
              decorButton('balloons', '🎈 Кульки', 5, decorated),
              decorButton('flowers', '🌷 Квіти', 8, flowers),
              decorButton('awning', '🎪 Барвистий навіс', 12, awning),
            ] else ...[
              FilledButton(onPressed: !ready || saving || decorated || stars < decorationPrice ? null : decorate,
                child: Text(decorated ? 'Крамничку прикрашено' : 'Додати кульки · 5 ⭐')),
              const Text('Увійдіть у родину, щоб відкрити більше прикрас.'),
            ],
          ]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) => setState(() => tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Містечко'),
          NavigationDestination(icon: Icon(Icons.pets), label: 'Улюбленець'),
          NavigationDestination(icon: Icon(Icons.storefront), label: 'Крамничка'),
        ],
      ),
    );
  }
}

class _PetNameDialog extends StatefulWidget {
  const _PetNameDialog({required this.initialName});
  final String initialName;
  @override
  State<_PetNameDialog> createState() => _PetNameDialogState();
}
class _PetNameDialogState extends State<_PetNameDialog> {
  late final controller = TextEditingController(text: widget.initialName);
  final form = GlobalKey<FormState>();
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ім’я улюбленця'),
    content: Form(key: form, child: TextFormField(controller: controller, maxLength: 24,
      decoration: const InputDecoration(labelText: 'Як звати друга?'),
      validator: (v) => v == null || v.trim().isEmpty || RegExp(r'[\x00-\x1F\x7F]').hasMatch(v) ? 'Введіть ім’я без перенесень рядка' : null)),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Назад')),
      FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, controller.text.trim()); }, child: const Text('Зберегти'))],
  );
}

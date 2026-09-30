import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/demo_api.dart';
import 'data/ink_api.dart';
import 'data/supabase_api.dart';
import 'screens/board_screen.dart';
import 'screens/rules_screen.dart';
import 'state/ink_store.dart';
import 'state/pen_shop.dart';
import 'theme/term_palette.dart';
import 'widget_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  InkApi api;
  PenShop? shop;
  if (hasServer) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    api = SupabaseInkApi(Supabase.instance.client);
    // 펜네임 결제: App Store · Google Play (서버 claim-pen 이 두 곳의 서명을 확인한다).
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android)) {
      shop = IapPenShop();
    }
  } else {
    // 서버 주소가 없으면 기기 안에서만 도는 데모.
    api = DemoInkApi(seed: true);
    shop = DemoPenShop();
  }

  final store = InkStore(api: api, shop: shop, widgets: await WidgetSync.create());
  store.systemBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
  await store.loadPrefs();
  unawaited(store.start());
  unawaited(store.initPen());
  runApp(InkExeApp(store: store));
}

class InkExeApp extends StatefulWidget {
  const InkExeApp({super.key, required this.store});

  final InkStore store;

  @override
  State<InkExeApp> createState() => _InkExeAppState();
}

class _InkExeAppState extends State<InkExeApp> with WidgetsBindingObserver {
  InkStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    store.systemBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }

  /// 앱으로 돌아오면 바로 새로 불러온다 (그 사이 자리가 찼을 수 있다).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) store.refresh(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store.brightness,
      builder: (context, _) {
        final p = store.palette;
        return MaterialApp(
          title: 'ink.exe',
          debugShowCheckedModeBanner: false,
          theme: _theme(p),
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: (p.isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light).copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: p.bar,
              systemNavigationBarIconBrightness: p.isLight ? Brightness.dark : Brightness.light,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          home: store.agreed ? BoardScreen(store: store) : RulesScreen(store: store),
        );
      },
    );
  }

  ThemeData _theme(TermPalette p) => ThemeData(
        useMaterial3: true,
        brightness: p.isLight ? Brightness.light : Brightness.dark,
        scaffoldBackgroundColor: p.bg,
        fontFamily: monoFamily,
        fontFamilyFallback: monoFallback,
        colorScheme: p.isLight
            ? ColorScheme.light(surface: p.bg, primary: p.cmd, secondary: p.cmd, error: p.warn)
            : ColorScheme.dark(surface: p.bg, primary: p.cmd, secondary: p.cmd, error: p.warn),
        splashFactory: NoSplash.splashFactory,
        highlightColor: p.fg.withAlpha(30),
        hoverColor: p.fg.withAlpha(16),
        focusColor: p.cmd.withAlpha(48),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: p.cmd,
          selectionColor: p.cmd.withAlpha(90),
          selectionHandleColor: p.cmd,
        ),
      );
}

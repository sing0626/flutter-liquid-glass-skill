import 'package:flutter/material.dart';

import 'glass_nav_bar.dart';

/// A COMPLETE, RUNNABLE demo app — the exact wiring the shipping app uses.
///
/// Paste `glass_surface.dart`, `glass_nav_bar.dart` and this file into a
/// fresh Flutter app's `lib/` (fix the two relative imports to
/// `glass_surface.dart` / `glass_nav_bar.dart`) and run. If your integration
/// of the bar looks or behaves differently from this demo, the difference is
/// in YOUR wiring, not the bar — see pitfalls.md #12/#13.
///
/// The three things agents most often get wrong, all visible here:
/// 1. `extendBody: true` — without it content never scrolls behind the glass
/// 2. the `MediaQuery` bottom padding (+76) — without it the last list items
///    and snackbars hide under the bar
/// 3. pages as `IndexedStack(index:)` — the bar resolves taps/drags instantly,
///    so pages must switch instantly too; a slow PageRoute/AnimatedSwitcher
///    cross-fade looks desynced from a settled bubble (pitfalls.md #13)
void main() => runApp(const GlassBarDemoApp());

class GlassBarDemoApp extends StatelessWidget {
  const GlassBarDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: const GlassBarDemoHome(),
    );
  }
}

class GlassBarDemoHome extends StatefulWidget {
  const GlassBarDemoHome({super.key});

  @override
  State<GlassBarDemoHome> createState() => _GlassBarDemoHomeState();
}

class _GlassBarDemoHomeState extends State<GlassBarDemoHome> {
  var _currentIndex = 0;
  final _backdropKey = GlobalKey();

  // Positional records: (outlined icon, filled icon, label).
  static const _tabs = [
    (Icons.dashboard_outlined, Icons.dashboard, '儀表板'),
    (Icons.article_outlined, Icons.article, '日誌'),
    (Icons.key_outlined, Icons.key, '令牌'),
    (Icons.tune_outlined, Icons.tune, '設定'),
  ];

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      // 1. Content must scroll UNDER the floating bar or the glass has
      //    nothing behind it.
      extendBody: true,
      // 3. IndexedStack: instant page switch, keeps each page's scroll and
      //    state. The bar is the source of truth for WHICH page.
      body: MediaQuery(
        // 2. Lift FABs/snackbars and give lists the extra inset so the last
        //    item scrolls clear of the bar (76 = bar height + margins).
        data: mq.copyWith(
          padding: mq.padding.copyWith(
            bottom: mq.padding.bottom + 76,
          ),
        ),
        child: RepaintBoundary(
          key: _backdropKey,
          child: IndexedStack(
            index: _currentIndex,
            children: const [
              _DemoPage(title: '儀表板', color: Colors.indigo),
              _DemoPage(title: '日誌', color: Colors.teal),
              _DemoPage(title: '令牌', color: Colors.deepPurple),
              _DemoPage(title: '設定', color: Colors.blueGrey),
            ],
          ),
        ),
      ),
      bottomNavigationBar: GlassNavBar(
        backdropKey: _backdropKey,
        currentIndex: _currentIndex,
        onChanged: (index) => setState(() => _currentIndex = index),
        tabs: _tabs,
      ),
    );
  }
}

/// Scrollable filler page: enough content to scroll under the bar.
class _DemoPage extends StatelessWidget {
  const _DemoPage({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: 30,
      itemBuilder: (context, i) => Card(
        color: color.withValues(alpha: 0.25),
        child: ListTile(
          title: Text('$title card $i'),
          subtitle: const Text('Scroll me under the glass bar'),
        ),
      ),
    );
  }
}

/// FAB location that clears the floating glass bar (pitfalls.md #5).
class AboveGlassBarFabLocation extends FloatingActionButtonLocation {
  const AboveGlassBarFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final base = FloatingActionButtonLocation.endFloat.getOffset(geometry);
    return Offset(base.dx, base.dy - 76);
  }
}

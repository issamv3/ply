import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static const _seed = Color(0xFF7C4DFF);

  static const _transitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: _SlideFadeTransition(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.fuchsia: _SlideFadeTransition(),
    },
  );

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.light,
        pageTransitionsTheme: _transitions,
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
        pageTransitionsTheme: _transitions,
      );
}

class _SlideFadeTransition extends PageTransitionsBuilder {
  const _SlideFadeTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final slide = Tween<Offset>(
      begin: const Offset(0.0, 0.06),
      end: Offset.zero,
    ).animate(curved);

    final secondarySlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.0, -0.04),
    ).animate(CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeInCubic,
    ));

    return SlideTransition(
      position: secondarySlide,
      child: SlideTransition(
        position: slide,
        child: FadeTransition(
          opacity: curved,
          child: child,
        ),
      ),
    );
  }
}

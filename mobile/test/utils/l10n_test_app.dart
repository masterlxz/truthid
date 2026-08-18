import 'package:flutter/material.dart';
import 'package:truthid_mobile/l10n/generated/app_localizations.dart';

/// Wraps [child] in a [MaterialApp] configured with the app's
/// localization delegates and supported locales, so widgets under test
/// that call `context.l10n` (i.e. `AppLocalizations.of(context)`) resolve
/// correctly instead of throwing a "No AppLocalizations found" error.
Widget wrapForTest(
  Widget child, {
  ThemeData? theme,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: theme,
    navigatorObservers: navigatorObservers,
    home: child,
  );
}

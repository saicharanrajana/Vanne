// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get restartMayFixIt => 'Restarting the app should fix it.';

  @override
  String get startupErrorTitle => 'Could not start';

  @override
  String get startupErrorMessage =>
      'Your saved wallpapers are safe. Try again, or restart the app if this keeps happening.';

  @override
  String get tryAgain => 'Try again';
}

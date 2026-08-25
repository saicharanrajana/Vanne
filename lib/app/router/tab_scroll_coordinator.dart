import 'package:flutter/widgets.dart';

import '../theme/app_motion.dart';

/// App-lifetime scroll controllers for the four primary destinations.
///
/// The bottom navigation bar uses these so tapping the destination the user
/// is already on scrolls that page back to top — the native reselection
/// gesture. Controllers outlive individual screens because the shell keeps
/// every tab alive in an IndexedStack.
final class TabScrollCoordinator {
  final ScrollController _discover = ScrollController();
  final ScrollController _collections = ScrollController();
  final ScrollController _favorites = ScrollController();
  final ScrollController _settings = ScrollController();

  ScrollController get discover => _discover;
  ScrollController get collections => _collections;
  ScrollController get favorites => _favorites;
  ScrollController get settings => _settings;

  /// Animates tab [index]'s viewport back to the top when it has been
  /// scrolled. No-op when nothing is attached or already at rest.
  void scrollToTop(int index) {
    final controller = switch (index) {
      0 => _discover,
      1 => _collections,
      2 => _favorites,
      3 => _settings,
      _ => null,
    };
    if (controller == null || !controller.hasClients) return;
    if (controller.offset <= 0) return;
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: AppMotion.arrivalCurve,
    );
  }

  void dispose() {
    _discover.dispose();
    _collections.dispose();
    _favorites.dispose();
    _settings.dispose();
  }
}

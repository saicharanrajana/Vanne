import 'package:material_ui/material_ui.dart';

/// Lets the shell toolbar run the Discover feed's filter action.
///
/// The toolbar is an ancestor of the tab stack, while the filter it acts on
/// belongs to the Discover screen (which owns that feed's controller). The
/// screen publishes its "open filters" callback in this binding while it is
/// mounted, and the toolbar renders the action exactly while a callback is
/// bound — so no other destination can ever show a control it cannot honour,
/// and no screen has to reach through a global for another screen's state.
final class ShellFilterAction
    extends InheritedNotifier<ValueNotifier<VoidCallback?>> {
  const ShellFilterAction({
    required this.binding,
    required super.child,
    super.key,
  }) : super(notifier: binding);

  /// The published action, or null while no page offers one.
  final ValueNotifier<VoidCallback?> binding;

  /// The nearest shell's binding, without subscribing to it.
  ///
  /// Callers write to the binding (mount/unmount) instead of rebuilding on it,
  /// so this deliberately does not establish a dependency.
  static ValueNotifier<VoidCallback?>? maybeBindingOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellFilterAction>()?.binding;

  @override
  bool updateShouldNotify(ShellFilterAction oldWidget) =>
      binding != oldWidget.binding;
}

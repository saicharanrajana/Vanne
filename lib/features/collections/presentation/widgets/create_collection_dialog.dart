import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/dependencies.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_shapes.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../application/collections_controller.dart';

/// Modern dialog for creating a collection.
///
/// A collection is a shortcut to a Wallhaven search — the title is
/// stored as `name` and `query = name.toLowerCase()`. Replaces the former
/// spring bottom sheet with a centered `Dialog` matching
/// `SetWallpaperDialog` language (tonal surface, expressive shape, staggered
/// entrance).
Future<void> showCreateCollectionDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _CreateCollectionDialog(),
  );
}

/// Deprecated alias — use [showCreateCollectionDialog].
Future<void> showCreateCollectionSheet(BuildContext context) =>
    showCreateCollectionDialog(context);

final class _CreateCollectionDialog extends StatefulWidget {
  const _CreateCollectionDialog();

  @override
  State<_CreateCollectionDialog> createState() =>
      _CreateCollectionDialogState();
}

final class _CreateCollectionDialogState extends State<_CreateCollectionDialog> {
  final _nameCtrl = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name required');
      return;
    }
    setState(() => _saving = true);
    final controller = locator<CollectionsController>();
    final err = await controller.create(name: name, query: name.toLowerCase());
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Dialog(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.extraLargeIncreased),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EntranceTile(
              delay: 0,
              reduceMotion: reduceMotion,
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      BootstrapIcons.collection_fill,
                      size: 22,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'New collection',
                    style: textTheme.titleLarge?.copyWith(
                      color: scheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'A collection is a shortcut to a search — we’ll use the '
                    'title as the search term.',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _EntranceTile(
              delay: 40,
              reduceMotion: reduceMotion,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    maxLength: 30,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'Title',
                      hintText: 'e.g. Dark Minimal',
                      prefixIcon: Icon(
                        BootstrapIcons.collection_fill,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppShapes.large),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _error!,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _EntranceTile(
              delay: 80,
              reduceMotion: reduceMotion,
              child: Row(
                children: [
                  Expanded(
                    child: M3EButton(
                      style: M3EButtonStyle.outlined,
                      size: M3EButtonSize.md,
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: M3EButton.icon(
                      style: M3EButtonStyle.filled,
                      size: M3EButtonSize.md,
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: M3ECircularWavyProgressIndicator(
                                size: 16,
                                color: scheme.onPrimary,
                              ),
                            )
                          : const Icon(BootstrapIcons.plus_lg, size: 15),
                      label: Text(_saving ? 'Creating…' : 'Create'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _EntranceTile extends StatelessWidget {
  final int delay;
  final bool reduceMotion;
  final Widget child;

  const _EntranceTile({
    required this.delay,
    required this.reduceMotion,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) return child;

    final totalMs = AppMotion.transition.inMilliseconds + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Interval(delay / totalMs, 1, curve: AppMotion.arrivalCurve),
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

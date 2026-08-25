import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/buttons/enums/m3e_button_enums.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/dependencies.dart';
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
  return M3EDialog.show<void>(
    context,
    dialog: const _CreateCollectionDialog(),
    barrierDismissible: true,
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

final class _CreateCollectionDialogState
    extends State<_CreateCollectionDialog> {
  final _nameCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocus.dispose();
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
    return M3EDialog(
      title: 'New collection',
      icon: const Icon(PhosphorIconsFill.stack),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'A collection is a shortcut to a search. We’ll use the title '
            'as the search term.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          M3ETextField(
            controller: _nameCtrl,
            focusNode: _nameFocus,
            supportingText: 'For example, Abstract',
            errorText: _error,
            variant: M3ETextFieldVariant.outlined,
            leading: Icon(
              PhosphorIconsFill.stack,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            inputFormatters: [LengthLimitingTextInputFormatter(30)],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      ),
      actions: [
        M3EButton.outlined(
          size: M3EButtonSize.md,
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        M3EButton.icon(
          style: M3EButtonStyle.filled,
          size: M3EButtonSize.md,
          onPressed: _saving ? null : _save,
          icon: _saving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: M3EProgressIndicator.circularWavy(
                    size: 16,
                    color: scheme.onPrimary,
                  ),
                )
              : const Icon(PhosphorIconsFill.plus, size: 15),
          label: Text(_saving ? 'Creating…' : 'Create'),
        ),
      ],
    );
  }
}

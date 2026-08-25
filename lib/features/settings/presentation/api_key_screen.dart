import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/buttons/enums/m3e_button_enums.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../../../app/dependencies.dart';
import '../../../shared/widgets/bottom_padding.dart';
import '../../../../shared/widgets/app_snack.dart';
import '../application/settings_controller.dart';

/// Dedicated Wallhaven API key screen.
///
/// Explains why the key is optional and what it enables; stores it only in
/// platform secure storage. After saving, the full key is never displayed
/// again — only its presence.
final class ApiKeyScreen extends StatefulWidget {
  final VoidCallback onBack;

  const ApiKeyScreen({super.key, required this.onBack});

  @override
  State<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

final class _ApiKeyScreenState extends State<ApiKeyScreen> {
  late final SettingsController settings = locator<SettingsController>();
  final _keyField = TextEditingController();
  final _keyFocus = FocusNode();
  bool _obscured = true;
  bool _saving = false;
  bool _removing = false;

  /// True while the user is entering a replacement for an existing key.
  bool _replacing = false;

  bool get _busy => _saving || _removing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !settings.hasApiKey.value) _keyFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    // Drop the plaintext from memory as soon as the screen leaves.
    _keyField.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final key = _keyField.text.trim();
    if (key.isEmpty) return;
    setState(() => _saving = true);
    try {
      await settings.saveApiKey(key);
      if (!mounted) return;
      _keyField.clear();
      _replacing = false;
      FocusManager.instance.primaryFocus?.unfocus();
      AppSnack.showRoot('API key saved securely.');
    } catch (_) {
      if (mounted) {
        AppSnack.show(context, 'Couldn’t save the API key.', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    if (_busy || !mounted) return;
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await M3EDialog.show<bool>(
      context,
      dialog: Builder(
        builder: (dialogContext) => M3EDialog(
          title: 'Remove API key?',
          content: const Text(
            'NSFW access will be disabled until another key is configured.',
          ),
          actions: [
            M3EButton.text(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            M3EButton.filled(
              decoration: M3EButtonDecoration(
                backgroundColor: WidgetStatePropertyAll(scheme.error),
                foregroundColor: WidgetStatePropertyAll(scheme.onError),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing = true);
    try {
      await settings.removeApiKey();
      // Signal-driven rebuild may have replaced this screen's subtree by the
      // time the future resolves — never touch `context` past this point.
      AppSnack.showRoot('API key removed.');
      _keyField.clear();
      _replacing = false;
    } catch (_) {
      AppSnack.showRoot('Couldn’t remove the API key.', error: true);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  void _replace() {
    setState(() => _replacing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: M3EAppBar.top(
        leading: M3EIconButton(
          onPressed: widget.onBack,
          tooltip: 'Back',
          icon: const Icon(PhosphorIconsBold.arrowLeft),
        ),
        title: const Text('Wallhaven API key'),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          BottomPadding.of(context, minimum: 20),
        ),
        children: [
          // Row(
          //   crossAxisAlignment: CrossAxisAlignment.start,
          //   children: [
          //     Icon(
          //       PhosphorIconsFill.info,
          //       size: 22,
          //       color: theme.colorScheme.primary,
          //     ),
          //     const SizedBox(width: 10),
          //     Expanded(
          //       child: Text(
          //         'A key is optional. Normal browsing works without one. '
          //         'Adding your own key unlocks NSFW content and personal '
          //         'account features.',
          //         style: theme.textTheme.bodyMedium?.copyWith(
          //           color: theme.colorScheme.onSurfaceVariant,
          //         ),
          //       ),
          //     ),
          //   ],
          // ),
          const SizedBox(height: 8),
          Text(
            'The key is stored in your device\u2019s secure storage and is '
            'only ever sent to wallhaven.cc. It is never shown again after '
            'saving — not even here.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          SignalBuilder(
            builder: (context) {
              final hasKey = settings.hasApiKey.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasKey && !_replacing)
                    const M3EListItem(
                      headline: 'A key is configured on this device.',
                      variant: M3ECardVariant.filled,
                      leading: Icon(PhosphorIconsBold.checkCircle),
                    )
                  else
                    M3ETextField(
                      controller: _keyField,
                      focusNode: _keyFocus,
                      supportingText: 'Paste your Wallhaven API key.',
                      variant: M3ETextFieldVariant.outlined,
                      leading: Icon(
                        PhosphorIconsFill.key,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      trailing: M3EIconButton(
                        tooltip: _obscured ? 'Show key' : 'Hide key',
                        semanticLabel: _obscured ? 'Show key' : 'Hide key',
                        size: M3EIconButtonSize.xs,
                        onPressed: () => setState(() => _obscured = !_obscured),
                        icon: Icon(
                          _obscured
                              ? PhosphorIconsFill.eye
                              : PhosphorIconsFill.eyeSlash,
                          size: 20,
                        ),
                      ),
                      obscureText: _obscured,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (_keyField.text.trim().isNotEmpty && !_busy) _save();
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  const SizedBox(height: 16),
                  if (hasKey && !_replacing) ...[
                    M3EButton.tonal(
                      size: M3EButtonSize.md,
                      onPressed: _busy ? null : _replace,
                      child: const Text('Replace key'),
                    ),
                    const SizedBox(height: 10),
                    M3EButton.icon(
                      style: M3EButtonStyle.outlined,
                      size: M3EButtonSize.md,
                      onPressed: _busy ? null : _remove,
                      icon: _removing
                          ? const M3EProgressIndicator.circularWavy(size: 16)
                          : const Icon(PhosphorIconsFill.trash, size: 16),
                      label: Text(_removing ? 'Removing…' : 'Remove key'),
                    ),
                  ] else
                    M3EButton.icon(
                      style: M3EButtonStyle.filled,
                      size: M3EButtonSize.md,
                      onPressed: _keyField.text.trim().isEmpty || _busy
                          ? null
                          : _save,
                      icon: _saving
                          ? M3EProgressIndicator.circularWavy(
                              size: 16,
                              color: theme.colorScheme.onPrimary,
                            )
                          : const Icon(PhosphorIconsBold.check, size: 16),
                      label: Text(
                        _saving
                            ? 'Saving…'
                            : _replacing && hasKey
                            ? 'Save new key'
                            : 'Save key',
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

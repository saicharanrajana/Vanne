import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/buttons/enums/m3e_button_enums.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../../../app/theme/app_shapes.dart';
import '../../../app/dependencies.dart';
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
  bool _obscured = true;

  /// True while the user is entering a replacement for an existing key.
  bool _replacing = false;

  @override
  void dispose() {
    // Drop the plaintext from memory as soon as the screen leaves.
    _keyField.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _keyField.text.trim();
    if (key.isEmpty) return;
    await settings.saveApiKey(key);
    if (!mounted) return;
    // Signal-driven rebuild handles the UI; just drop the plaintext.
    _keyField.clear();
    FocusScope.of(context).unfocus();
    AppSnack.show(context, 'API key saved securely.');
  }

  Future<void> _remove() async {
    await settings.removeApiKey();
    if (!mounted) return;
    setState(() => _replacing = false);
    AppSnack.show(context, 'API key removed.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: M3EAppBar.top(
        leading: M3EIconButton(
          onPressed: widget.onBack,
          tooltip: 'Back',
          icon: const Icon(BootstrapIcons.arrow_left),
        ),
        title: const Text('Wallhaven API key'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                BootstrapIcons.info_circle_fill,
                size: 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'A key is optional. Normal browsing works without one. '
                  'Adding your own key unlocks NSFW content and personal '
                  'account features.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
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
              final showField = !hasKey || _replacing;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasKey && !_replacing)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: ShapeDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppShapes.extraLarge,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            BootstrapIcons.check_circle_fill,
                            size: 22,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'A key is configured on this device.',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    M3ETextField(
                      controller: _keyField,
                      label: 'Paste your API key',
                      variant: M3ETextFieldVariant.outlined,
                      leading: Icon(
                        BootstrapIcons.key_fill,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      obscureText: _obscured,
                      onChanged: (_) => setState(() {}),
                    ),
                  if (showField) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: M3EButton.icon(
                        style: M3EButtonStyle.text,
                        onPressed: () => setState(() => _obscured = !_obscured),
                        icon: Icon(
                          _obscured
                              ? BootstrapIcons.eye_fill
                              : BootstrapIcons.eye_slash_fill,
                          size: 20,
                        ),
                        label: Text(_obscured ? 'Show key' : 'Hide key'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (hasKey && !_replacing) ...[
                    M3EButton(
                      style: M3EButtonStyle.filled,
                      size: M3EButtonSize.lg,
                      onPressed: () => setState(() => _replacing = true),
                      child: const Text('Replace key'),
                    ),
                    const SizedBox(height: 10),
                    M3EButton(
                      style: M3EButtonStyle.outlined,
                      size: M3EButtonSize.lg,
                      onPressed: _remove,
                      child: const Text('Remove key'),
                    ),
                  ] else
                    M3EButton(
                      style: M3EButtonStyle.filled,
                      size: M3EButtonSize.lg,
                      onPressed: _keyField.text.trim().isEmpty ? null : _save,
                      child: Text(
                        _replacing && hasKey ? 'Save new key' : 'Save key',
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

import 'package:m3e_core/m3e_core.dart';
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
    _keyField.clear();
    FocusScope.of(context).unfocus();
    AppSnack.show(context, 'API key saved securely.');
    setState(() {});
  }

  Future<void> _remove() async {
    await settings.removeApiKey();
    if (!mounted) return;
    AppSnack.show(context, 'API key removed.');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onBack,
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
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
                Icons.info_outline,
                size: 20,
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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasKey)
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
                            Icons.check_circle,
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
                    TextField(
                      controller: _keyField,
                      decoration: InputDecoration(
                        labelText: 'Paste your API key',
                        border: const OutlineInputBorder(),
                        prefixIcon: Icon(
                        Icons.vpn_key_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      ),
                      obscureText: _obscured,
                      onChanged: (_) => setState(() {}),
                    ),
                  if (!hasKey) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _obscured = !_obscured),
                        icon: Icon(
                          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                        label: Text(_obscured ? 'Show key' : 'Hide key'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (hasKey) ...[
                    M3EButton(style: M3EButtonStyle.filled, 
                      size: M3EButtonSize.lg,
                      onPressed: onOpenKeyEntry,
                      child: const Text('Replace key'),
                    ),
                    const SizedBox(height: 10),
                    M3EButton(style: M3EButtonStyle.outlined, 
                      size: M3EButtonSize.lg,
                      onPressed: _remove,
                      child: const Text('Remove key'),
                    ),
                  ] else
                    M3EButton(style: M3EButtonStyle.filled, 
                      size: M3EButtonSize.lg,
                      onPressed: _keyField.text.trim().isEmpty ? null : _save,
                      child: const Text('Save key'),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void onOpenKeyEntry() => setState(() {});
}

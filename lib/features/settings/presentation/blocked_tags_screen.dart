import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/buttons/enums/m3e_button_enums.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:wallpaper_app/app/theme/app_spacing.dart';

import '../../../app/dependencies.dart';
import '../../../shared/widgets/app_snack.dart';
import '../../../shared/widgets/bottom_padding.dart';
import '../application/settings_controller.dart';

/// Dedicated screen for editing blocked Wallhaven tags.
///
/// Mirrors [ApiKeyScreen] appbar/background treatment: no surface tint,
/// tonal back button, scaffold background. The main affordance is a large
/// full-width multiline field (30-40% of viewport height) with help text
/// describing comma / new-line separation.
final class BlockedTagsScreen extends StatefulWidget {
  final VoidCallback onBack;

  const BlockedTagsScreen({super.key, required this.onBack});

  @override
  State<BlockedTagsScreen> createState() => _BlockedTagsScreenState();
}

final class _BlockedTagsScreenState extends State<BlockedTagsScreen> {
  late final SettingsController settings = locator<SettingsController>();
  late final TextEditingController _field;
  final _focus = FocusNode();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController(
      text: SettingsController.serializeBlockedTags(settings.blockedTags.value),
    );
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final parsed = SettingsController.parseBlockedTags(_field.text);
    final current = settings.blockedTags.value;
    if (parsed.length != current.length) return true;
    return !parsed.containsAll(current) || !current.containsAll(parsed);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      settings.saveBlockedTagsFromRaw(_field.text);
      FocusManager.instance.primaryFocus?.unfocus();
      AppSnack.showRoot('Blocked tags saved.', type: AppSnackType.success);
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearAll() {
    _field.text = '';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            pinned: false,
            backgroundColor: theme.scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: M3EIconButton(
                onPressed: widget.onBack,
                tooltip: 'Back',
                size: M3EIconButtonSize.xs,
                variant: M3EIconButtonVariant.tonal,
                icon: Icon(
                  PhosphorIconsBold.arrowLeft,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            title: const Text('Blocked tags'),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                BottomPadding.of(context, minimum: 20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Hide wallpapers containing these tags. Tags are sent to Wallhaven as -tag exclusions. Applies to Discover and Search, not Collections.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final viewportH = MediaQuery.of(context).size.height;
                      final targetH = (viewportH * 0.35).clamp(220.0, 360.0);
                      return ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: 220,
                          maxHeight: 360,
                          minWidth: double.infinity,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: targetH,
                          child: TextField(
                            controller: _field,
                            focusNode: _focus,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: InputDecoration(
                              hintText: 'anime, ai-generated',
                              helperMaxLines: 2,
                            ),
                            textInputAction: TextInputAction.newline,
                            keyboardType: TextInputType.multiline,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  M3EButton.icon(
                    style: M3EButtonStyle.filled,
                    size: M3EButtonSize.md,
                    onPressed: !_isDirty || _saving ? null : _save,
                    icon: _saving
                        ? M3EProgressIndicator.circularWavy(
                            size: 16,
                            color: scheme.onPrimary,
                          )
                        : const Icon(PhosphorIconsBold.check, size: 16),
                    label: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                  const SizedBox(height: 10),
                  M3EButton.icon(
                    style: M3EButtonStyle.outlined,
                    size: M3EButtonSize.md,
                    onPressed: _field.text.trim().isEmpty ? null : _clearAll,
                    icon: const Icon(PhosphorIconsFill.eraser, size: 16),
                    label: const Text('Clear all'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

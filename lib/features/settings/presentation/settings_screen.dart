import '../../../core/services/image_cache_service.dart';

import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../../../app/dependencies.dart';
import '../../../app/router/tab_scroll_coordinator.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/downloads/app_identity.dart';
import '../../../core/downloads/download_destination.dart';
import '../../../core/downloads/download_destination_controller.dart';
import '../../../shared/widgets/app_snack.dart';
import '../../../shared/widgets/bottom_padding.dart';
import '../application/settings_controller.dart';
import '../../../core/storage/settings_store.dart';

import 'package:intl/intl.dart';

/// Grouped, expressive settings screen. Every toggle mutates a
/// [SettingsController] signal which persists immediately.
final class SettingsScreen extends StatelessWidget {
  final VoidCallback onOpenApiKey;
  final VoidCallback onOpenBlockedTags;

  const SettingsScreen({
    super.key,
    required this.onOpenApiKey,
    required this.onOpenBlockedTags,
  });

  @override
  Widget build(BuildContext context) {
    final settings = locator<SettingsController>();
    final theme = Theme.of(context);

    final headerSliver = SliverAppBar(
      floating: true,
      snap: true,
      pinned: false,
      automaticallyImplyLeading: false,
      backgroundColor: theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 0,
      collapsedHeight: 0,
      expandedHeight: 80,
      flexibleSpace: FlexibleSpaceBar(
        background: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text('Settings', style: theme.textTheme.displaySmall),
            ),
          ),
        ),
      ),
    );

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        controller: locator<TabScrollCoordinator>().settings,
        slivers: [
          headerSliver,
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              BottomPadding.of(context, minimum: 24),
            ),
            sliver: SliverList.list(
              children: [
                _Section(
                  title: 'Appearance',
                  children: [
                    SignalBuilder(
                      builder: (context) => _SwitchTile(
                        icon: PhosphorIconsFill.palette,
                        title: 'Use dynamic color',
                        subtitle: 'Match app colors to your wallpaper.',
                        value: settings.dynamicColor.value,
                        onChanged: settings.setDynamicColor,
                      ),
                    ),
                    SignalBuilder(
                      builder: (context) => _SwitchTile(
                        icon: PhosphorIconsFill.moonStars,
                        title: 'Pitch black mode',
                        subtitle: 'Pure black in dark mode for OLED screens.',
                        value: settings.pitchBlack.value,
                        onChanged: settings.setPitchBlack,
                      ),
                    ),
                    _ThemeModeSelector(settings: settings),
                  ],
                ),
                const _SectionDivider(),
                _Section(
                  title: 'Content',
                  children: [
                    SignalBuilder(
                      builder: (context) {
                        final hasKey = settings.hasApiKey.value;
                        return _SwitchTile(
                          icon: PhosphorIconsFill.shield,
                          title: 'Show NSFW wallpapers',
                          subtitle: hasKey
                              ? 'Mature content (18+). Filtered by purity.'
                              : 'Requires a Wallhaven API key.',
                          value: hasKey && settings.nsfwEnabled.value,
                          onChanged: hasKey ? settings.setNsfwEnabled : null,
                          onTapOverride: hasKey ? null : onOpenApiKey,
                        );
                      },
                    ),
                    SignalBuilder(
                      builder: (context) {
                        final tags = settings.blockedTags.value;
                        final subtitle = tags.isEmpty
                            ? 'Hide wallpapers by tag'
                            : tags.join(', ');
                        return _ActionTile(
                          icon: PhosphorIconsFill.prohibit,
                          title: 'Blocked tags',
                          subtitle: subtitle,
                          onTap: onOpenBlockedTags,
                        );
                      },
                    ),
                    SignalBuilder(
                      builder: (context) => _ActionTile(
                        icon: PhosphorIconsFill.key,
                        title: 'API key',
                        subtitle: settings.hasApiKey.value
                            ? 'Connected. NSFW unlock available.'
                            : 'Add your Wallhaven API key.',
                        onTap: onOpenApiKey,
                      ),
                    ),
                  ],
                ),
                const _SectionDivider(),
                _Section(
                  title: 'Storage',
                  children: [const _DownloadsTile(), _CacheTile()],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Separates Settings groups without drawing a border around each row.
final class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 24,
      thickness: 1,
      indent: 4,
      endIndent: 4,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

final class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTapOverride;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.onTapOverride,
  });

  @override
  Widget build(BuildContext context) {
    return M3EListItem(
      headline: title,
      supportingText: subtitle,
      variant: M3ECardVariant.filled,
      leading: Icon(icon),
      trailing: M3ESwitch(
        value: value,
        semanticLabel: title,
        onChanged: onChanged == null
            ? null
            : (v) {
                M3EHaptics.trigger(M3EHapticFeedback.light);
                onChanged!.call(v);
              },
      ),
      onTap:
          onTapOverride ??
          (onChanged != null
              ? () {
                  M3EHaptics.trigger(M3EHapticFeedback.light);
                  onChanged!(!value);
                }
              : null),
    );
  }
}

/// System / Light / Dark selection row.
final class _ThemeModeSelector extends StatelessWidget {
  final SettingsController settings;

  const _ThemeModeSelector({required this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m3eTheme = M3ETheme.of(context);
    final itemTheme = m3eTheme.listTheme.item;
    final typeScale = m3eTheme.typeScale;

    return SignalBuilder(
      builder: (context) {
        final mode = settings.themeMode.value;
        return M3ECard(
          variant: itemTheme.variant,
          border: null,
          color: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: itemTheme.horizontalPadding,
            vertical: itemTheme.threeLineVerticalPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                PhosphorIconsFill.sun,
                size: itemTheme.iconSize,
                color: scheme.onSurfaceVariant,
              ),
              SizedBox(width: itemTheme.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Theme',
                      style: itemTheme.headlineStyle(
                        typeScale,
                        m3eTheme.colorScheme,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose how Vanne follows your device appearance.',
                      style: itemTheme.supportingStyle(
                        typeScale,
                        m3eTheme.colorScheme,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: M3ESegmentedButton<AppThemeMode>(
                        showSelectedIcon: false,
                        segments: [
                          M3ESegment<AppThemeMode>(
                            value: AppThemeMode.system,
                            icon: Tooltip(
                              message: 'System theme',
                              child: Icon(
                                mode == AppThemeMode.system
                                    ? PhosphorIconsFill.deviceMobile
                                    : PhosphorIconsRegular.deviceMobile,
                              ),
                            ),
                            semanticLabel: 'System theme',
                          ),
                          M3ESegment<AppThemeMode>(
                            value: AppThemeMode.light,
                            icon: Tooltip(
                              message: 'Light theme',
                              child: Icon(
                                mode == AppThemeMode.light
                                    ? PhosphorIconsFill.sun
                                    : PhosphorIconsRegular.sun,
                              ),
                            ),
                            semanticLabel: 'Light theme',
                          ),
                          M3ESegment<AppThemeMode>(
                            value: AppThemeMode.dark,
                            icon: Tooltip(
                              message: 'Dark theme',
                              child: Icon(
                                mode == AppThemeMode.dark
                                    ? PhosphorIconsFill.moon
                                    : PhosphorIconsRegular.moon,
                              ),
                            ),
                            semanticLabel: 'Dark theme',
                          ),
                        ],
                        selected: {mode},
                        onSelectionChanged: (selection) {
                          if (selection.isNotEmpty) {
                            M3EHaptics.selection();
                            settings.setThemeMode(selection.first);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

final class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return M3EListItem(
      headline: title,
      supportingText: subtitle,
      variant: M3ECardVariant.filled,
      leading: Icon(icon),
      trailing: const Icon(PhosphorIconsBold.caretRight),
      onTap: onTap,
    );
  }
}

/// Where downloads land: one emphasized folder line, one hint line.
///
/// Tapping opens an explainer dialog (folder-picker constraints + the
/// explicit way back to the default) with the `Choose folder` action, so the
/// system picker is never a surprise and "use default" is reachable without
/// hunting through menus.
final class _DownloadsTile extends StatelessWidget {
  const _DownloadsTile();

  @override
  Widget build(BuildContext context) {
    final controller = locator<DownloadDestinationController>();
    return SignalBuilder(
      builder: (context) {
        final destination = controller.destination.value;
        final lost = controller.access.value == DestinationAccess.lost;
        final picking = controller.picking.value;
        return _FolderTile(
          icon: PhosphorIconsFill.downloadSimple,
          title: 'Downloads',
          folderPath: destination.folderPath,
          hint: lost
              ? 'Folder access was lost. Choose it again or use the default.'
              : 'Tap to change the downloads location',
          isError: lost,
          busy: picking,
          onTap: picking
              ? null
              : () => showDownloadFolderDialog(context, controller),
        );
      },
    );
  }
}

/// List-item shell matching [M3EListItem] metrics with an emphasized second
/// line for a folder path (plain [M3EListItem.supportingText] is a single
/// unemphasized string, which reads as prose).
final class _FolderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String folderPath;
  final String hint;
  final bool isError;
  final bool busy;
  final VoidCallback? onTap;

  const _FolderTile({
    required this.icon,
    required this.title,
    required this.folderPath,
    required this.hint,
    required this.isError,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m3eTheme = M3ETheme.of(context);
    final itemTheme = m3eTheme.listTheme.item;
    final typeScale = m3eTheme.typeScale;

    return M3ECard(
      variant: itemTheme.variant,
      border: null,
      color: Colors.transparent,
      elevation: 0,
      onPressed: onTap,
      semanticLabel: '$title. Saving to $folderPath. $hint',
      padding: EdgeInsets.symmetric(
        horizontal: itemTheme.horizontalPadding,
        vertical: itemTheme.verticalPadding,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: itemTheme.minHeight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconTheme.merge(
              data: IconThemeData(
                color: scheme.onSurfaceVariant,
                size: itemTheme.iconSize,
              ),
              child: Icon(icon),
            ),
            SizedBox(width: itemTheme.gap),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: itemTheme.headlineStyle(
                        typeScale,
                        m3eTheme.colorScheme,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // Emphasized destination line: the directory is the
                    // important part of this row.
                    Text(
                      folderPath,
                      style: itemTheme
                          .supportingStyle(typeScale, m3eTheme.colorScheme)
                          .copyWith(color: isError ? scheme.error : null),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      hint,
                      style: itemTheme
                          .supportingStyle(typeScale, m3eTheme.colorScheme)
                          .copyWith(color: isError ? scheme.error : null),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: itemTheme.gap),
            busy
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: M3ELoadingIndicator(
                      size: 24,
                      color: scheme.primary,
                      semanticLabel: 'Opening folder picker',
                    ),
                  )
                : IconTheme.merge(
                    data: IconThemeData(
                      color: scheme.onSurfaceVariant,
                      size: itemTheme.iconSize,
                    ),
                    child: const Icon(PhosphorIconsBold.caretRight),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Explains the folder picker, then offers the two destination actions.
Future<void> showDownloadFolderDialog(
  BuildContext context,
  DownloadDestinationController controller,
) async {
  final chosen = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _DownloadFolderDialog(controller: controller),
  );
  if (!context.mounted || chosen == null) return;
  if (chosen) {
    await _chooseFolder(context, controller);
  } else {
    await controller.resetToDefault();
    if (!context.mounted) return;
    AppSnack.show(
      context,
      'Saving downloads to ${controller.destination.peek().folderPath}',
      type: AppSnackType.success,
    );
  }
}

Future<void> _chooseFolder(
  BuildContext context,
  DownloadDestinationController controller,
) async {
  final outcome = await controller.chooseParent();
  if (!context.mounted) return;
  switch (outcome) {
    case DestinationPickOutcome.picked:
      AppSnack.show(
        context,
        'Saving downloads to ${controller.destination.peek().folderPath}',
        type: AppSnackType.success,
      );
    case DestinationPickOutcome.canceled:
    case DestinationPickOutcome.busy:
      break;
    case DestinationPickOutcome.failed:
      AppSnack.show(
        context,
        controller.error.peek() ?? 'Could not open the folder picker.',
        type: AppSnackType.error,
      );
  }
}

final class _DownloadFolderDialog extends StatelessWidget {
  final DownloadDestinationController controller;

  const _DownloadFolderDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final destination = controller.destination.peek();
    final lost = controller.access.peek() == DestinationAccess.lost;
    final isChosen = destination is ChosenDownloadDestination;

    return M3EDialog(
      title: 'Download folder',
      icon: const Icon(PhosphorIconsFill.folderSimple),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Current folder',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            destination.folderPath,
            style: theme.textTheme.titleMedium?.copyWith(
              color: lost ? scheme.error : scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (lost) ...[
            Text(
              'This folder is no longer accessible. Choose it again, or use '
              'the default folder.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(
            'A ${AppIdentity.storageFolderName} folder is created inside the '
            'folder you pick, and all wallpapers are saved there.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Internal-storage root and Download are not selectable. Folders '
            'in cloud apps may not appear in your gallery.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        M3EButton.text(
          size: M3EButtonSize.md,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (isChosen)
          M3EButton.outlined(
            size: M3EButtonSize.md,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Use default'),
          ),
        M3EButton.filled(
          size: M3EButtonSize.md,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Choose folder'),
        ),
      ],
    );
  }
}

/// Image cache tile: shows accumulated disk cache size and clears on tap.
///
/// Implementation:
/// - Size via [ImageCacheService.getCachedSizeBytes] which sums
///   `libCachedImageData` (flutter_cache_manager) + legacy
///   `cacheImageFolderName` (extended_image, orphaned) on IO; on web 0.
/// - Subheading displays formatted MB (`X.X MB`) and is live — re-queried
///   on init and after clear.
/// - Tap clears both disk (`DefaultCacheManager.emptyCache`) and memory
///   (`PaintingBinding.imageCache`) caches, plus legacy dir, then re-queries
///   size and shows a `SnackBar`.
final class _CacheTile extends StatefulWidget {
  const _CacheTile();

  @override
  State<_CacheTile> createState() => _CacheTileState();
}

final class _CacheTileState extends State<_CacheTile> {
  int? _bytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final b = await ImageCacheService.getCachedSizeBytes();
      if (!mounted) return;
      setState(() => _bytes = b);
    } catch (_) {
      if (!mounted) return;
      setState(() => _bytes = 0);
    }
  }

  String _format(int? bytes, String locale) {
    if (bytes == null) return 'Calculating…';
    if (bytes == 0) return '0 MB • Tap to clear image cache';
    final mb = bytes / (1024 * 1024);
    if (mb < 0.1) {
      final kb = NumberFormat.decimalPatternDigits(
        locale: locale,
        decimalDigits: 1,
      ).format(bytes / 1024);
      return '$kb KB • Tap to clear';
    }
    final mbText = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 1,
    ).format(mb);
    return '$mbText MB • Tap to clear image cache';
  }

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await ImageCacheService.clearCache();
      await _refresh();
      if (!mounted) return;
      AppSnack.show(
        context,
        ok ? 'Image cache cleared' : 'Failed to clear cache',
        type: ok ? AppSnackType.success : AppSnackType.error,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        'Failed to clear cache: $e',
        type: AppSnackType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return M3EListItem(
      headline: 'Clear image cache',
      supportingText: _format(_bytes, locale),
      variant: M3ECardVariant.filled,
      leading: const Icon(PhosphorIconsFill.eraser),
      trailing: _busy
          ? M3ELoadingIndicator(
              size: 24,
              color: scheme.primary,
              semanticLabel: 'Clearing cache',
            )
          : null,
      onTap: _busy ? null : _clear,
    );
  }
}

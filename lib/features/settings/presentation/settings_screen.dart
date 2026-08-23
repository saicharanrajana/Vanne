import '../../../core/services/image_cache_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../../../app/theme/app_shapes.dart';
import '../../../app/dependencies.dart';
import '../../../shared/widgets/app_snack.dart';
import '../../../shared/widgets/bottom_padding.dart';
import '../application/settings_controller.dart';
import '../../../core/storage/settings_store.dart';
/// Grouped, expressive settings screen. Every toggle mutates a
/// [SettingsController] signal which persists immediately.
final class SettingsScreen extends StatelessWidget {
  final VoidCallback onOpenApiKey;

  const SettingsScreen({super.key, required this.onOpenApiKey});

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
        slivers: [
          headerSliver,
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, BottomPadding.of(context, minimum: 24)),
            sliver: SliverList.list(
              children: [
                _Section(
                  title: 'Appearance',
                  children: [
                    SignalBuilder(
                      builder: (context) => _SwitchTile(
                        icon: Icons.palette_outlined,
                        title: 'Use dynamic color',
                        subtitle: 'Match app colors to your wallpaper.',
                        value: settings.dynamicColor.value,
                        onChanged: settings.setDynamicColor,
                      ),
                    ),
                    SignalBuilder(
                      builder: (context) => _SwitchTile(
                        icon: Icons.dark_mode_outlined,
                        title: 'Pitch black mode',
                        subtitle: 'Pure black in dark mode for OLED screens.',
                        value: settings.pitchBlack.value,
                        onChanged: settings.setPitchBlack,
                      ),
                    ),
                    _ThemeModeSelector(settings: settings),
                  ],
                ),
                const SizedBox(height: 24),
                _Section(
                  title: 'Content',
                  children: [
                    SignalBuilder(
                      builder: (context) {
                        final hasKey = settings.hasApiKey.value;
                        return _SwitchTile(
                          icon: Icons.shield_outlined,
                          title: 'Show NSFW wallpapers',
                          subtitle: hasKey
                              ? 'Mature content (18+) — filtered by purity.'
                              : 'Requires a Wallhaven API key.',
                          value: hasKey && settings.nsfwEnabled.value,
                          onChanged: hasKey ? settings.setNsfwEnabled : null,
                          onTapOverride: hasKey ? null : onOpenApiKey,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _Section(
                  title: 'Wallhaven account',
                  children: [
                    _ActionTile(
                      icon: Icons.vpn_key_outlined,
                      title: 'API key',
                      subtitle: SignalBuilder(
                        builder: (context) => Text(
                          settings.hasApiKey.value
                              ? 'Connected — NSFW unlock available.'
                              : 'Add your Wallhaven API key.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      onTap: onOpenApiKey,
                    ),
                    _InfoTile(
                      icon: Icons.download_outlined,
                      title: 'Downloads',
                      subtitle: 'Saved to Pictures/WallpaperApp in your gallery.',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _Section(
                  title: 'Storage',
                  children: [
                    _CacheTile(),
                  ],
                ),
                const SizedBox(height: 24),
                _Section(
                  title: 'About',
                  children: [
                    _InfoTile(
                      icon: Icons.wallpaper_outlined,
                      title: 'Source',
                      subtitle: 'Powered by wallhaven.cc',
                    ),
                    _InfoTile(
                      icon: Icons.code_outlined,
                      title: 'Open source',
                      subtitle: 'Free & open — contributions welcome.',
                    ),
                  ],
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
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const SizedBox(height: 8),
        ],
      ],
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.extraLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap:
            onTapOverride ??
            (onChanged != null ? () => onChanged!(!value) : null),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: scheme.onSurfaceVariant),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: textTheme.titleSmall?.copyWith(height: 1.2)),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Semantics(
                  label: title,
                  child: Switch(
                    value: value,
                    onChanged: onChanged == null ? null : (v) => onChanged!.call(v),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// System / Light / Dark selection row.
final class _ThemeModeSelector extends StatelessWidget {
  final SettingsController settings;

  const _ThemeModeSelector({required this.settings});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SignalBuilder(
      builder: (context) {
        final mode = settings.themeMode.value;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: ShapeDecoration(
            color: scheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppShapes.extraLarge),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.brightness_4_outlined,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Text('Theme', style: textTheme.titleSmall)),
                ],
              ),
              const SizedBox(height: 12),
              // M3ESegmentedButton must never sit directly in a horizontal
              // Row: it lays out its segments with width: infinity and needs
              // bounded incoming constraints (a Row provides unbounded
              // width), which crashes layout.
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<AppThemeMode>(
                  segments: [
                    for (final m in AppThemeMode.values)
                      ButtonSegment<AppThemeMode>(
                        value: m,
                        label: Text(switch (m) {
                          AppThemeMode.system => 'Auto',
                          AppThemeMode.light => 'Light',
                          AppThemeMode.dark => 'Dark',
                        }),
                      ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) {
                    if (selection.isNotEmpty) {
                      settings.setThemeMode(selection.first);
                    }
                  },
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
  final Widget subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.extraLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: scheme.onSurfaceVariant),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: textTheme.titleSmall?.copyWith(height: 1.2)),
                      subtitle,
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShapes.extraLarge),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: scheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleSmall?.copyWith(height: 1.2)),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

  String _format(int? bytes) {
    if (bytes == null) return 'Calculating…';
    if (bytes == 0) return '0 MB • Tap to clear image cache';
    final mb = bytes / (1024 * 1024);
    if (mb < 0.1) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(1)} KB • Tap to clear';
    }
    return '${mb.toStringAsFixed(1)} MB • Tap to clear image cache';
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
        error: !ok,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(context, 'Failed to clear cache: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.extraLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : _clear,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.cleaning_services_outlined,
                    size: 22, color: scheme.onSurfaceVariant),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Clear image cache', style: textTheme.titleSmall?.copyWith(height: 1.2)),
                      const SizedBox(height: 2),
                      Text(
                        _format(_bytes),
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (_busy)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  )
                else
                  Icon(Icons.delete_outline, size: 20, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

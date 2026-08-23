import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';
import '../../../shared/widgets/bottom_padding.dart';
import '../../../core/domain/app_category.dart';

/// The Categories destination: expressive Material-shaped cards, one per
/// [AppCategory]. Each card uses a deterministic random [Shapes] so the
/// collection feels playful — no image background. Purely presentational.
final class CategoriesScreen extends StatelessWidget {
  final ValueChanged<AppCategory> onOpenCategory;

  const CategoriesScreen({super.key, required this.onOpenCategory});

  @override
  Widget build(BuildContext context) {
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
              child: Text('Categories', style: theme.textTheme.displaySmall),
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
            padding: EdgeInsets.fromLTRB(16, 8, 16, BottomPadding.of(context)),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.1,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final category = appCategories[index];
                return _CategoryCard(
                  category: category,
                  onTap: () => onOpenCategory(category),
                );
              }, childCount: appCategories.length),
            ),
          ),
        ],
      ),
    );
  }
}

final class _CategoryCard extends StatelessWidget {
  final AppCategory category;
  final VoidCallback onTap;

  const _CategoryCard({required this.category, required this.onTap});

  static const _shapes = [
    Shapes.gem,
    Shapes.slanted,
    Shapes.arch,
    Shapes.clampShell,
    Shapes.c9SidedCookie,
    Shapes.pentagon,
    Shapes.sunny,
    Shapes.flower,
    Shapes.puffy,
    Shapes.burst,
    Shapes.bun,
    Shapes.heart,
    Shapes.l4LeafClover,
    Shapes.l8LeafClover,
    Shapes.c4SidedCookie,
    Shapes.c6SidedCookie,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hash = category.id.hashCode.abs();
    final shape = _shapes[hash % _shapes.length];
    final bg = scheme.secondaryContainer;
    final fg = scheme.onSecondaryContainer;
    final accent = scheme.secondary;

    return Semantics(
      button: true,
      label: 'Browse ${category.title} wallpapers',
      child: M3EContainer(
        shape,
        color: bg,
        border: BorderSide(color: accent.withValues(alpha: 0.18), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      category.title[0].toUpperCase(),
                      style: textTheme.titleLarge?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  Text(
                    category.title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

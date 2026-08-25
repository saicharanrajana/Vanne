import 'package:material_ui/material_ui.dart';

import '../../../../shared/widgets/feed_filter_sheet.dart';
import '../../application/discover_controller.dart';

/// Opens the Discover filter/sort sheet — spring-driven. Thin wrapper over
/// the generic [showFeedFilterSheet] for backward compat.
Future<void> showDiscoverFilterSheet(
  BuildContext context, {
  required DiscoverController controller,
}) {
  return showFeedFilterSheet(
    context,
    initial: controller.filter.value,
    onApply: (filter) => controller.applyFilter(filter),
  );
}

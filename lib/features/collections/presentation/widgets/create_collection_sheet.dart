import 'package:material_ui/material_ui.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';

import '../../../../app/dependencies.dart';
import '../../../../shared/widgets/spring_sheet.dart';
import '../../application/collections_controller.dart';

/// Opens the spring-driven "New collection" sheet.
///
/// The user types only a title; the Wallhaven search query is derived from
/// it (title lowercased), so a collection is inherently a search shortcut.
Future<void> showCreateCollectionSheet(BuildContext context) {
  return showSpringBottomSheet<void>(
    context: context,
    builder: (ctx) => const _CreateCollectionSheet(),
  );
}

class _CreateCollectionSheet extends StatefulWidget {
  const _CreateCollectionSheet();

  @override
  State<_CreateCollectionSheet> createState() => _CreateCollectionSheetState();
}

class _CreateCollectionSheetState extends State<_CreateCollectionSheet> {
  final _nameCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final controller = locator<CollectionsController>();
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name required');
      return;
    }
    // The title IS the search query — e.g. "Dark Minimal" searches
    // `dark minimal`. Same syntax as the Search screen's q parameter.
    final err = await controller.create(name: name, query: name.toLowerCase());
    if (!mounted) return;
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

    return SheetContainer(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('New collection', style: textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'A collection is a shortcut to a search — we’ll use the '
                'title as the search term.',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Dark Minimal',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: textTheme.bodySmall?.copyWith(color: scheme.error),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(BootstrapIcons.plus_lg),
                    label: const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

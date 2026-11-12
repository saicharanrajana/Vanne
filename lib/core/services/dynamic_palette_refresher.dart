import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals.dart';

import '../../app/theme/dynamic_dark_surfaces.dart';

/// Keeps the app's dynamic schemes in sync with the system palette.
///
/// Android configuration notifications and app resume request fresh reads.
/// The last valid palette stays visible during reads and temporary failures.
final class DynamicPaletteController {
  static const _changes = MethodChannel(
    'com.saicharanrajana.vanne/dynamic_palette',
  );

  // CorePalette is the type returned by dynamic_color's current public API.
  // ignore: deprecated_member_use
  final _palette = signal<CorePalette?>(null);
  bool _listening = false;
  Future<void>? _running;
  bool _dirty = false;
  bool _started = false;
  bool _disposed = false;

  /// The light scheme from the last valid system palette.
  late final lightScheme = computed<ColorScheme?>(
    () => _palette.value?.toColorScheme(),
  );

  /// The dark scheme from the last valid system palette.
  ///
  /// Kept for pitch-black mode and for anything that expects the plugin's
  /// own conversion unchanged.
  late final darkScheme = computed<ColorScheme?>(
    () => _palette.value?.toColorScheme(brightness: Brightness.dark),
  );

  /// Normal dark mode, with its surface family resolved from the system
  /// palettes instead of a regenerated seed.
  late final darkSurfaceScheme = computed<ColorScheme?>(() {
    final palette = _palette.value;
    final legacy = darkScheme.value;
    if (palette == null || legacy == null) return null;
    return dynamicDarkSurfaceScheme(palette, legacy: legacy);
  });

  /// Subscribes to platform changes and reads the initial palette.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _changes.setMethodCallHandler((call) async {
        if (call.method != 'changed') throw MissingPluginException();
        await refresh();
      });
      _listening = true;
    }
    // Install the handler before reading so a concurrent change is not lost.
    unawaited(refresh());
  }

  /// Reconciles the palette, sharing one read loop across concurrent requests.
  ///
  /// A notification during a read marks its result stale and requests another
  /// read. Only the latest completed snapshot is published.
  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    _dirty = true;
    return _running ??= _readUntilCurrent().whenComplete(() => _running = null);
  }

  Future<void> _readUntilCurrent() async {
    while (_dirty && !_disposed) {
      _dirty = false;
      try {
        final next = await DynamicColorPlugin.getCorePalette();
        if (!_disposed && !_dirty && next != null && next != _palette.peek()) {
          _palette.value = next;
        }
      } catch (error) {
        // A transient platform failure must not replace a valid theme.
        debugPrint('Could not refresh the dynamic palette: $error');
      }
    }
  }

  /// Stops notifications and prevents pending reads from publishing changes.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_listening) _changes.setMethodCallHandler(null);
    lightScheme.dispose();
    darkScheme.dispose();
    darkSurfaceScheme.dispose();
    _palette.dispose();
  }
}

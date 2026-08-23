import 'dart:async';

import 'authentication_state.dart';

/// Holds the optional API key in memory and notifies listeners of changes.
///
/// The key lives only here for the lifetime of the manager — persistence
/// (secure storage) is an application-layer concern that feeds [setApiKey].
final class ApiKeyManager {
  String? _apiKey;
  final _controller = StreamController<AuthenticationState>.broadcast();

  ApiKeyManager({String? initialApiKey}) : _apiKey = initialApiKey;

  /// Current key, or `null` when unauthenticated.
  String? get apiKey => _apiKey;

  set apiKey(String? value) => setApiKey(value);

  bool get isAuthenticated => _apiKey != null && _apiKey!.isNotEmpty;

  AuthenticationState get state =>
      isAuthenticated ? const Authenticated() : const Unauthenticated();

  /// Broadcast stream of [AuthenticationState] transitions.
  Stream<AuthenticationState> get changes => _controller.stream;

  /// Sets or removes (`null`) the key and emits the new state.
  void setApiKey(String? value) {
    final next = (value == null || value.isEmpty) ? null : value;
    if (next == _apiKey) return;
    _apiKey = next;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }

  void dispose() {
    _apiKey = null;
    _controller.close();
  }
}

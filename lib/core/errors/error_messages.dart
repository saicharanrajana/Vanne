import 'package:wallhaven_client/wallhaven_client.dart';

/// Maps package exceptions to short, user-facing strings for the smoke UI.
///
/// Kept in one place so the presentation layer never needs to know the
/// exception taxonomy. Messages are safe to display: the package already
/// guarantees no secrets inside exception text.
String describeWallhavenError(WallhavenException error) {
  if (error is NsfwAuthenticationRequiredException) {
    return 'NSFW results need an API key (Settings).';
  }
  if (error is AuthenticationRequiredException) {
    return 'Sign in with an API key first (Settings).';
  }
  if (error is WallhavenUnauthorizedException) {
    return 'Invalid or missing API key.';
  }
  if (error is WallhavenRateLimitExceededException) {
    final retry = error.retryAfter;
    return retry == null
        ? 'Rate limit reached — try again in a minute.'
        : 'Rate limit reached — retry in ${retry.inSeconds}s.';
  }
  if (error is WallhavenNotFoundException) {
    return 'Not found on Wallhaven.';
  }
  if (error is WallhavenTimeoutException) {
    return 'Wallhaven took too long to respond.';
  }
  if (error is WallhavenCancelledException) {
    return 'Request cancelled.';
  }
  if (error is WallhavenNetworkException) {
    return 'Network unavailable. Check your connection.';
  }
  if (error is WallhavenBadRequestException) {
    return 'Wallhaven rejected the search parameters.';
  }
  if (error is WallhavenServerException) {
    return 'Wallhaven server error (${error.statusCode}). Try again later.';
  }
  if (error is WallhavenMalformedJsonException ||
      error is WallhavenInvalidResponseException) {
    return 'Unexpected response from Wallhaven.';
  }
  return 'Something went wrong: ${error.message}';
}

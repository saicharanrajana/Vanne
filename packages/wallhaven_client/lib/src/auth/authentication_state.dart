/// Whether the client currently carries an API key.
sealed class AuthenticationState {
  const AuthenticationState();
}

final class Unauthenticated extends AuthenticationState {
  const Unauthenticated();
}

final class Authenticated extends AuthenticationState {
  const Authenticated();
}

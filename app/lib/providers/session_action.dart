/// A redirect the app needs to perform regardless of which screen is
/// currently showing — e.g. a background reconciliation discovers the
/// session is no longer valid after Home was already painted from cache.
/// Set via [AppStateNotifier.requestSessionAction] and consumed by
/// [SessionGuard].
enum SessionAction {
  none,
  requireLogin,
  requireOnboarding,
}

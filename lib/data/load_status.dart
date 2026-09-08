/// The load state of a repository's remote data.
///
/// Repositories expose this instead of masquerading fabricated seed data as
/// loaded data. Screens can switch on it to render a spinner ([loading]), an
/// empty state ([loaded] with an empty list), or an error affordance ([error]).
enum LoadStatus {
  /// No load has been attempted yet (initial state before the first [load]).
  idle,

  /// A load is in flight.
  loading,

  /// The most recent load completed successfully. The cache is authoritative
  /// (it may still be empty, which is a real "no data" state, not an error).
  loaded,

  /// The most recent load failed. See the repository's error field for detail.
  error,
}

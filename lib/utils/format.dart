/// Small formatting helpers shared across widgets and screens.

/// Formats a count into a compact abbreviation (1.2K, 3.4M) like the web app.
String fmtCount(int value) {
  if (value < 1000) return value.toString();
  if (value < 1000000) {
    final k = value / 1000.0;
    return '${_trim(k)}K';
  }
  if (value < 1000000000) {
    final m = value / 1000000.0;
    return '${_trim(m)}M';
  }
  final b = value / 1000000000.0;
  return '${_trim(b)}B';
}

String _trim(double v) {
  // One decimal place, but drop a trailing '.0'.
  final s = v.toStringAsFixed(1);
  if (s.endsWith('.0')) {
    return s.substring(0, s.length - 2);
  }
  return s;
}

/// Returns a short relative timestamp like 'now', '5m', '2h', '3d', or a
/// 'MMM d' style date for older items. Mirrors the web timeAgo behavior.
String timeAgo(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time);
  final seconds = diff.inSeconds;

  if (seconds < 0) return 'now';
  if (seconds < 45) return 'now';

  final minutes = diff.inMinutes;
  if (minutes < 60) return '${minutes < 1 ? 1 : minutes}m';

  final hours = diff.inHours;
  if (hours < 24) return '${hours}h';

  final days = diff.inDays;
  if (days < 7) return '${days}d';

  // Older than a week: show a short date.
  return '${_month(time.month)} ${time.day}';
}

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _month(int month) {
  final idx = (month - 1).clamp(0, 11);
  return _months[idx];
}

/// How long ago [at] was, in the short Thai form the history shows. Never
/// negative: a clock that is a little behind the server's reads "เมื่อกี้".
String relativeTime(DateTime at, DateTime now) {
  final gap = now.difference(at);
  if (gap.inMinutes < 1) return 'เมื่อกี้';
  if (gap.inHours < 1) return '${gap.inMinutes} นาที';
  if (gap.inDays < 1) return '${gap.inHours} ชม.';
  return '${gap.inDays} วัน';
}

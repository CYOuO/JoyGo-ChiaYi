/// Shared HTML cleaning helper for government open-data content.
///
/// Decodes common HTML entities, converts `<br>`/`<p>` to newlines, strips all
/// remaining tags, and collapses excess whitespace.
String cleanHtml(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  var s = raw;
  s = s.replaceAll('&nbsp;', ' ');
  s = s.replaceAll('&amp;', '&');
  s = s.replaceAll('&lt;', '<');
  s = s.replaceAll('&gt;', '>');
  s = s.replaceAll('&quot;', '"');
  s = s.replaceAll('&#39;', "'");
  s = s.replaceAll('&hellip;', '…');
  s = s.replaceAll('&mdash;', '—');
  s = s.replaceAll('&ndash;', '–');
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

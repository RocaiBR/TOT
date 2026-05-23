String sanitize(String input) {
  if (input.isEmpty) return input;

  String sanitized = input.replaceAll(
      RegExp(r'<[^>]*>', multiLine: true, caseSensitive: true), '');

  sanitized = sanitized.replaceAll(RegExp(r'[\\;{}<>]'), '');

  return sanitized.trim();
}

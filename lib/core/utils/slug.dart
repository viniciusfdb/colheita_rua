String slugify(String input) {
  final lower = input.trim().toLowerCase();
  var replaced = lower
      .replaceAll(RegExp(r"[áàâãä]"), "a")
      .replaceAll(RegExp(r"[éèêë]"), "e")
      .replaceAll(RegExp(r"[íìîï]"), "i")
      .replaceAll(RegExp(r"[óòôõö]"), "o")
      .replaceAll(RegExp(r"[úùûü]"), "u")
      .replaceAll(RegExp(r"[ç]"), "c")
      .replaceAll(RegExp(r"[^a-z0-9]+"), "-")
      .replaceAll(RegExp(r"-+"), "-");
  if (replaced.startsWith('-')) {
    replaced = replaced.substring(1);
  }
  if (replaced.endsWith('-')) {
    replaced = replaced.substring(0, replaced.length - 1);
  }
  return replaced;
}

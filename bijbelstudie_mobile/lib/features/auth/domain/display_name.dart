/// Whether a stored `name` is really a placeholder rather than something a
/// user chose or typed.
///
/// The backend (a separate repo) stores the email local-part as `name` when
/// Apple or Google sign-in returns no name at all - which Apple only ever
/// sends on the *first* authorization, and Hide My Email relay addresses
/// (`xyz@privaterelay.appleid.com`) make that local-part look like random
/// noise. "Goedemorgen, drwddsspn" is the visible symptom.
///
/// This only special-cases the relay domain: a normal email whose local-part
/// happens to equal someone's real name (`alex@gmail.com`, name "Alex") is
/// not a placeholder, and must not be treated as one.
bool isPlaceholderName(String name, String email) {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) return true;
  if (trimmedName == 'Gebruiker') return true;
  if (trimmedName.contains('@')) return true;

  final trimmedEmail = email.trim().toLowerCase();
  if (!trimmedEmail.endsWith('@privaterelay.appleid.com')) return false;

  final localPart = trimmedEmail.split('@').first;
  return trimmedName.toLowerCase() == localPart;
}

/// The first name to greet someone with, or null when [name] is a
/// placeholder and nothing should be shown at all.
String? displayFirstName(String name, String email) {
  if (isPlaceholderName(name, email)) return null;
  final trimmed = name.trim();
  return trimmed.split(RegExp(r'\s+')).first;
}

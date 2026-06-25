// Shared validation helpers for the PeerStudy app.
// These help keep form validation consistent and easy to test.

// Checks that the email belongs to the official LIMU student domain.
bool isValidLimuEmail(String? email) {
  if (email == null || email.isEmpty) return false;
  return RegExp(r"^[\w-.]+@limu\.edu\.ly$").hasMatch(email);
}

// Keeps passwords at the minimum length Firebase accepts for this app.
bool isValidPassword(String? password) {
  if (password == null || password.isEmpty) return false;
  return password.length >= 6;
}

// Reusable helper for fields that only need non-empty text.
bool isNotEmpty(String? value) {
  return value != null && value.trim().isNotEmpty;
}

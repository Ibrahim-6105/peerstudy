// Small validation helpers used by forms.
// Putting these checks here keeps login, signup, and reset screens from copying
// the same email/password rules over and over.

// Checks that the email belongs to the official LIMU domain.
// This supports the project requirement that students sign up with university
// accounts instead of personal emails.
bool isValidLimuEmail(String? email) {
  if (email == null || email.isEmpty) return false;
  return RegExp(r"^[\w-.]+@limu\.edu\.ly$").hasMatch(email);
}

// Checks the minimum password length used by Firebase Auth.
// More complex password rules can be added here later without touching screens.
bool isValidPassword(String? password) {
  if (password == null || password.isEmpty) return false;
  return password.length >= 6;
}

// Checks that a text value has real content after trimming spaces.
// Use this for simple fields like names, post titles, or support messages.
bool isNotEmpty(String? value) {
  return value != null && value.trim().isNotEmpty;
}

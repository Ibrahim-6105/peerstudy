// Small validation helpers used by forms.
// Putting these checks here keeps login, signup, and reset screens from copying
// the same email/password rules over and over.
//
// Beginner note:
// A validator is a small function that checks whether user input is acceptable
// before the app sends it to the trusted Supabase backend.

// Converts a complete LIMU email into the normalized Supabase Auth value.
// Student signup and password recovery deliberately use this strict helper.
String? normalizedLimuLoginEmail(String? email) {
  // Missing text cannot identify any Supabase account.
  if (email == null) return null;

  // Email addresses are case-insensitive and ignore surrounding spaces.
  final normalizedEmail = email.trim().toLowerCase();

  // Every production role must use a complete university email address.
  return isValidLimuEmail(normalizedEmail) ? normalizedEmail : null;
}

// Converts the login screen's email-or-Admin-name input into an Auth email.
// The exact `admin` alias exists only for the user's pre-created test account.
String? normalizedLoginIdentifier(String? identifier) {
  // Null input cannot identify an account.
  if (identifier == null) return null;

  // Alias matching is case-insensitive and ignores surrounding spaces.
  final normalizedIdentifier = identifier.trim().toLowerCase();
  if (normalizedIdentifier == 'admin') return 'admin@limu.edu.ly';

  // Every Student and a directly entered Admin email use the strict rule.
  return normalizedLimuLoginEmail(normalizedIdentifier);
}

// Checks that the email belongs to the official LIMU domain.
// This supports the project requirement that students sign up with university
// accounts instead of personal emails.
bool isValidLimuEmail(String? email) {
  // Null means no value was provided. Empty means the field is blank.
  if (email == null || email.isEmpty) return false;

  // RegExp checks the email pattern. This one only accepts @limu.edu.ly.
  return RegExp(r"^[\w-.]+@limu\.edu\.ly$").hasMatch(email);
}

// Checks the minimum password length accepted by the login form.
// More complex password rules can be added here later without touching screens.
bool isValidPassword(String? password) {
  // Reject missing or blank passwords.
  if (password == null || password.isEmpty) return false;

  // The pre-created testing Admin password uses six characters.
  return password.length >= 6;
}

// Registration uses a stronger bounded policy than login. Login keeps
// six-character compatibility for the pre-created Admin account, while every
// newly created Student password is stronger.
bool isValidNewPassword(String? password) {
  // Reject missing values before checking the remaining policy.
  if (password == null) return false;

  // Keep credentials large enough for normal use and bounded for the backend.
  if (password.length < 8 || password.length > 128) return false;

  // Require at least one ordinary letter and one digit, matching the backend.
  return RegExp('[A-Za-z]').hasMatch(password) &&
      RegExp('[0-9]').hasMatch(password);
}

// Checks that a text value has real content after trimming spaces.
// Use this for simple fields like names, post titles, or support messages.
bool isNotEmpty(String? value) {
  // trim() removes spaces at the start/end, so "   " becomes empty.
  return value != null && value.trim().isNotEmpty;
}

/// Build-time configuration that lives outside the Firebase plugin config.
class AppConfig {
  AppConfig._();

  /// Firebase's type-3 ("web") OAuth client. Android signs in with Google,
  /// gets an ID token issued *for this client*, and exchanges it for a Firebase
  /// credential -- so it is not the Android client ID, and getting the two
  /// mixed up produces a silent `idToken == null`.
  ///
  /// Firebase mints this when Google is enabled as a sign-in provider, and it
  /// then appears in `android/app/google-services.json` as the `oauth_client`
  /// entry with `client_type: 3`. It is a public client identifier, not a
  /// secret -- it already ships inside the APK -- so it is checked in, and a
  /// clone of this repo builds a working app without extra flags.
  ///
  /// The override exists so a fork pointed at a different Firebase project can
  /// supply its own without editing source.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '332091201626-8952dt61rlnril4pmhqh0d0erc8k5l2j.apps.googleusercontent.com',
  );

  static bool get isGoogleSignInConfigured =>
      !googleServerClientId.contains('PLACEHOLDER');
}

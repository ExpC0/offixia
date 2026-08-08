import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/suspended_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/session_service.dart';
import 'services/theme_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Release builds attest through Play Integrity. Local development can opt
  // into Firebase's debug provider explicitly with
  // --dart-define=OFFIXIA_APP_CHECK_DEBUG=true; never select it merely because
  // this is a debug build, or a mistakenly published debug APK could receive
  // trusted backend access.
  const appCheckDebug = bool.fromEnvironment('OFFIXIA_APP_CHECK_DEBUG');
  await FirebaseAppCheck.instance.activate(
    providerAndroid: appCheckDebug
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
  );

  // Loaded before the first frame so the app opens in the right brightness
  // instead of flashing the wrong one.
  await ThemeService.instance.load();
  await AuthService.instance.initialize();

  // Creates the message channel and asks for permission. Android fixes a
  // channel's sound and vibration at creation time, so this has to happen
  // before the first notification is posted, not lazily on the first message.
  await NotificationService.instance.initialize();

  // Starts the auth -> membership -> org listener chain. Everything the UI
  // shows about "who am I here" comes from this.
  SessionService.instance.start();

  runApp(const OffixiaApp());
}

/// Held at the app level so the session gate can clear pushed routes when the
/// session ends. See [_SessionGate].
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class OffixiaApp extends StatelessWidget {
  const OffixiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.mode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Offixia',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: const _SessionGate(),
      ),
    );
  }
}

/// Picks the screen that matches the current session state.
///
/// The switch is exhaustive over the sealed [Session] hierarchy, so a new state
/// added later fails to compile here rather than silently falling through to a
/// blank screen.
class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Session>(
      valueListenable: SessionService.instance.state,
      builder: (context, session, _) {
        // The gate only controls what sits *under* the navigator. Anything
        // pushed on top of the shell -- Profile, an employee record, a chat
        // thread -- survives a session change and keeps covering the new
        // screen. That is why signing out from Profile looked like it did
        // nothing: auth had ended and the sign-in screen was already
        // underneath, hidden by the route the user was still standing on.
        if (session is! SessionReady) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
          });
        }

        final screen = switch (session) {
          SessionLoading() => const _Splash(),
          SessionSignedOut() => const SignInScreen(),
          SessionNeedsOrg() => const OnboardingScreen(),
          SessionSuspended(organization: final org) => SuspendedScreen(
            organization: org,
          ),
          SessionReady() => const HomeShell(),
          SessionFailed(message: final message) => _Failed(message: message),
        };

        // Keyed by runtime type so switching states animates, but a rebuild
        // within the same state does not restart the transition.
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey(session.runtimeType),
            child: screen,
          ),
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: SessionService.instance.retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: AuthService.instance.signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

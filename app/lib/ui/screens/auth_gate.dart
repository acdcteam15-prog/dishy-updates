import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

 import '../../state/app_state.dart';
 import '../../state/auth_service.dart';
 import '../widgets/common.dart';
import 'home_shell.dart';
import 'household_setup_screen.dart';
import 'onboarding_screen.dart';
import 'sign_in_screen.dart';

 class AuthGate extends StatefulWidget {
   const AuthGate({super.key});
   @override
   State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _silentTried = false;

  @override
  Widget build(BuildContext context) {
     return StreamBuilder<User?>(
       stream: FirebaseAuth.instance.authStateChanges(),
       builder: (c, snap) {
         if (snap.connectionState == ConnectionState.waiting) return const _Splash();
         final u = snap.data;
         final app = Provider.of<AppState>(context, listen: false);
         if (u == null) {
           app.detach();
          // First start after a successful Google login: Google still remembers
          // the account on this phone, so sign back in without any prompt.
          if (!_silentTried) {
            _silentTried = true;
            AuthService.signInGoogleSilently().then((_) {
              if (mounted) setState(() {});
            });
            return const _Splash();
          }
           return const SignInScreen();
         }
        app.attach(u);
        return const HouseholdGate();
      },
    );
  }
}

class HouseholdGate extends StatelessWidget {
  const HouseholdGate({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    Widget child;
    if (app.loadError != null && app.household == null) {
      child = Scaffold(
          body: SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: ErrorBox(code: 'load', meaning: app.loadError!)))));
    } else if (!app.userLoaded) {
      child = const _Splash();
    } else if (app.householdId == null) {
      child = const HouseholdSetupScreen();
    } else if (app.household == null) {
      child = const _Splash();
    } else if (!app.household!.onboarded) {
      child = const OnboardingScreen();
    } else {
      child = const HomeShell();
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: child);
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset('assets/logo.png', width: 88, height: 88),
          ),
        ),
      );
}

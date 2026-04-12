import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'screens/landing_page.dart';
import 'screens/ngo/ngo_dashboard.dart';
import 'screens/volunteer/volunteer_dashboard.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  print('KEY: ${dotenv.env['GEMINI_API_KEY']}'); // remove after confirming
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(
    const ProviderScope(
      child: NgoConnectApp(),
    ),
  );
}

class NgoConnectApp extends StatelessWidget {
  const NgoConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NGO Connect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const _AuthGate(),
    );
  }
}

/// Listens to Firebase Auth state and routes to the correct screen.
/// On refresh, Firebase restores the session automatically — this widget
/// waits for that and then routes to the right dashboard instead of
/// always showing the landing page.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        // Still waiting for Firebase to restore session
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnap.data;

        // Not logged in — show landing page
        if (user == null) {
          return const LandingPage();
        }

        // Logged in — fetch role and route to correct dashboard
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final role =
                (userSnap.data?.data() as Map<String, dynamic>?)?['role']
                    as String?;

            if (role == 'ngo') {
              return const NgoDashboard();
            } else if (role == 'volunteer') {
              return const VolunteerDashboard();
            }

            // Unknown role — fall back to landing page
            return const LandingPage();
          },
        );
      },
    );
  }
}

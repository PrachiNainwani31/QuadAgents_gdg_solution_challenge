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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: NgoConnectApp()));
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

/// Stateful auth gate — caches the role so page refreshes don't reset to landing.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  String? _cachedRole;
  String? _cachedUid;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) {
        if (mounted) setState(() { _cachedRole = null; _cachedUid = null; _loading = false; });
        return;
      }
      // Only re-fetch role if uid changed
      if (user.uid == _cachedUid && _cachedRole != null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final role = (doc.data() as Map<String, dynamic>?)?['role'] as String?;
      if (mounted) {
        setState(() {
          _cachedUid = user.uid;
          _cachedRole = role;
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_cachedRole == 'ngo') return const NgoDashboard();
    if (_cachedRole == 'volunteer') return const VolunteerDashboard();
    return const LandingPage();
  }
}

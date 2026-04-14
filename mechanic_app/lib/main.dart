import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/login_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await Supabase.initialize(
    url: 'https://lfeaeufshnclbabmxlhc.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxmZWFldWZzaG5jbGJhYm14bGhjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxMTA0MjMsImV4cCI6MjA5MTY4NjQyM30.EMrSYJmK5vitwZsCd8_so8WfvARlR9C96BxZHBo-FPs',
  );

  runApp(const IMSChatApp());
}

class IMSChatApp extends StatelessWidget {
  const IMSChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IMS Live Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8261D)),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

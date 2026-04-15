import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: Config.supabaseUrl,
    anonKey: Config.supabaseAnonKey,
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

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'config.dart';
import 'screens/chat_thread_screen.dart';
import 'screens/chat_list_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void _handleNotificationTap(RemoteMessage message) {
  final data = message.data;
  if (data['chat_id'] != null) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          chatId: data['chat_id'],
          customerName: data['customer_name'] ?? 'Customer',
          customerPhone: data['customer_phone'] ?? '',
          pageUrl: data['page_url'] ?? '',
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await Supabase.initialize(
    url: Config.supabaseUrl,
    anonKey: Config.supabaseAnonKey,
  );

  RemoteMessage? initialMessage = await FirebaseMessaging.instance
      .getInitialMessage();
  if (initialMessage != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationTap(initialMessage);
    });
  }
  // Handle notification tap when app is in background
  FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

  runApp(const IMSChatApp());
}

class IMSChatApp extends StatelessWidget {
  const IMSChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'IMS Live Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC81D24)),
        useMaterial3: true,
      ),
      home: const ChatListScreen(),
    );
  }
}

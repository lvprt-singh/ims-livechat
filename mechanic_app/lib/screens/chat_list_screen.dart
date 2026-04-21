import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'chat_thread_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;

  static const _red = Color(0xFFC81D24);

  @override
  void initState() {
    super.initState();
    _loadChats();
    _pollChats();
    _initFCM();
    _subscribeToMessages();
  }

  void _pollChats() async {
    if (!mounted) return;
    await _loadChats();
    Future.delayed(const Duration(seconds: 30), _pollChats);
  }

  void _subscribeToMessages() {
    _supabase
        .channel('realtime-messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            debugPrint('New message received, reloading chats');
            await _loadChats();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chats',
          callback: (payload) async {
            debugPrint('Chat updated, reloading');
            await _loadChats();
          },
        )
        .subscribe((status, [error]) {
          debugPrint('Realtime status: $status, error: $error');
        });
  }

  Future<void> _initFCM() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();

    if (token != null) {
      debugPrint('FCM Token: $token');
      await _supabase.from('fcm_tokens').upsert({
        'token': token,
      }, onConflict: 'token');
    }

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('Foreground message: ${message.notification?.title}');
      _loadChats();
    });
  }

  Future<void> _loadChats() async {
    final data = await _supabase
        .from('chats')
        .select(
          '*, customers(name, phone), messages(content, sender, created_at)',
        )
        .eq('status', 'open')
        .order('last_message_at', ascending: false);

    setState(() {
      _chats = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });
  }

  String _formatTime(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;

    if (diff == 0) return DateFormat('h:mm a').format(dt);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(dt);
    return DateFormat('d MMM').format(dt);
  }

  String _extractPage(String? url) {
    if (url == null) return 'Unknown page';
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final path = uri.path.replaceAll('-', ' ').replaceAll('/', ' ').trim();
    return path.isEmpty ? 'Home page' : path;
  }

  void _showCustomerInfo(
    BuildContext context,
    Map<String, dynamic> customer,
    String chatId,
  ) async {
    final messages = await _supabase
        .from('messages')
        .select()
        .eq('chat_id', chatId);
    final count = messages.where((m) => m['sender'] != 'system').length;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: _red,
                child: Text(
                  (customer['name'] as String)[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                customer['name'],
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                customer['phone'],
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count message${count == 1 ? '' : 's'} in this chat',
                  style: const TextStyle(
                    color: _red,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'IMS Live Chat',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        backgroundColor: _red,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadChats,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _red))
          : _chats.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline,
                      size: 40,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No active chats',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'New chats will appear here',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _chats.length,
              separatorBuilder: (_, _) => const SizedBox(height: 1),
              itemBuilder: (context, index) {
                final chat = _chats[index];
                final customer = chat['customers'];
                final page = _extractPage(chat['page_url']);
                return Container(
                  color: Colors.white,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    leading: GestureDetector(
                      onTap: () =>
                          _showCustomerInfo(context, customer, chat['id']),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: _red,
                        child: Text(
                          (customer['name'] as String)[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    title: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        customer['name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.link, size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                page,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Builder(
                          builder: (_) {
                            final msgs = (chat['messages'] as List?)
                                ?.where((m) => m['sender'] != 'system')
                                .toList();
                            msgs?.sort(
                              (a, b) => DateTime.parse(
                                b['created_at'],
                              ).compareTo(DateTime.parse(a['created_at'])),
                            );
                            final latest = msgs?.isNotEmpty == true
                                ? msgs!.first
                                : null;
                            final preview = latest?['content'] as String?;
                            final isMe = latest?['sender'] == 'mechanic';
                            if (preview == null) return const SizedBox.shrink();
                            return Text(
                              isMe ? 'You: $preview' : preview,
                              style: TextStyle(
                                fontSize: 12,
                                color: chat['has_unread'] == true && !isMe
                                    ? const Color(0xFF1A1A1A)
                                    : Colors.grey[500],
                                fontWeight: chat['has_unread'] == true && !isMe
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            );
                          },
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(chat['last_message_at']),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
                        ),
                        if (chat['has_unread'] == true) ...[
                          const SizedBox(height: 4),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: _red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatThreadScreen(
                            chatId: chat['id'],
                            customerName: customer['name'],
                            customerPhone: customer['phone'],
                            pageUrl: chat['page_url'] ?? '',
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

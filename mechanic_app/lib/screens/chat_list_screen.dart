import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'chat_thread_screen.dart';

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
    _subscribeToChats();
  }

  Future<void> _loadChats() async {
    final data = await _supabase
        .from('chats')
        .select('*, customers(name, phone)')
        .eq('status', 'open')
        .order('last_message_at', ascending: false);

    setState(() {
      _chats = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });
  }

  void _subscribeToChats() {
    _supabase
        .channel('chats-channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chats',
          callback: (payload) => _loadChats(),
        )
        .subscribe();
  }

  String _formatTime(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return DateFormat('h:mm a').format(dt);
    if (diff.inDays == 1) return 'Yesterday';
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
    final count = messages.length;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 32,
              backgroundColor: _red,
              child: Text(
                (customer['name'] as String)[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              customer['name'],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              customer['phone'],
              style: const TextStyle(fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count message${count == 1 ? '' : 's'} in this chat',
                style: const TextStyle(
                  color: _red,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
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
              separatorBuilder: (_, __) => const SizedBox(height: 1),
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
                        Row(
                          children: [
                            Icon(
                              Icons.phone,
                              size: 12,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              customer['phone'],
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: Text(
                      _formatTime(chat['last_message_at']),
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
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

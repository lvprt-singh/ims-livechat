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
  RealtimeChannel? _channel;

  static const _red = Color(0xFFC81D24);
  static const _jesse = Color(0xFF2563EB);
  static const _stathi = Color(0xFF059669);
  static const _bg = Color(0xFFF7F7F8);

  @override
  void initState() {
    super.initState();
    _loadChats();
    _initFCM();
    _subscribeToChanges();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToChanges() {
    _channel = _supabase
        .channel('chat-list-realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => _loadChats(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chats',
          callback: (_) => _loadChats(),
        )
        .subscribe((status, [error]) {
          debugPrint('List realtime: $status error: $error');
          if (status == RealtimeSubscribeStatus.subscribed) _loadChats();
        });
  }

  Future<void> _initFCM() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    if (token != null) {
      await _supabase.from('fcm_tokens').upsert({
        'token': token,
      }, onConflict: 'token');
    }
    FirebaseMessaging.onMessage.listen((_) => _loadChats());
  }

  Future<void> _loadChats() async {
    try {
      final data = await _supabase
          .from('chats')
          .select(
            '*, customers(name, email), messages(content, sender, created_at)',
          )
          .eq('status', 'open')
          .order('last_message_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _chats = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Load chats error: $e');
    }
  }

  Future<void> _assign(String chatId, String? who) async {
    await _supabase.from('chats').update({'assigned_to': who}).eq('id', chatId);
    _loadChats();
  }

  Future<void> _markUnread(String chatId) async {
    await _supabase.from('chats').update({'has_unread': true}).eq('id', chatId);
    _loadChats();
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

  Color _badgeColor(String? who) {
    if (who == 'Jesse') return _jesse;
    if (who == 'Stathi') return _stathi;
    return const Color(0xFF1A1A1A);
  }

  void _showLongPressMenu(BuildContext context, Map<String, dynamic> chat) {
    final chatId = chat['id'] as String;
    final current = chat['assigned_to'] as String?;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            _sheetTile(
              Icons.mark_email_unread_outlined,
              'Mark as unread',
              _red,
              () {
                Navigator.pop(context);
                _markUnread(chatId);
              },
            ),
            _sheetTile(
              Icons.person_outline,
              current == 'Jesse' ? 'Unassign Jesse' : 'Assign to Jesse',
              _jesse,
              () {
                Navigator.pop(context);
                _assign(chatId, current == 'Jesse' ? null : 'Jesse');
              },
            ),
            _sheetTile(
              Icons.person_outline,
              current == 'Stathi' ? 'Unassign Stathi' : 'Assign to Stathi',
              _stathi,
              () {
                Navigator.pop(context);
                _assign(chatId, current == 'Stathi' ? null : 'Stathi');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sheetTile(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
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
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _red))
            : _chats.isEmpty
            ? _emptyState()
            : RefreshIndicator(
                color: _red,
                onRefresh: _loadChats,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  itemCount: _chats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) => _chatTile(_chats[index]),
                ),
              ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
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
    );
  }

  Widget _chatTile(Map<String, dynamic> chat) {
    final customer = chat['customers'] as Map<String, dynamic>?;
    final name = (customer?['name'] as String?) ?? 'Unknown';
    final email = (customer?['email'] as String?) ?? '';
    final page = _extractPage(chat['page_url']);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final hasUnread = chat['has_unread'] == true;
    final assignee = chat['assigned_to'] as String?;

    final msgs = (chat['messages'] as List?)
        ?.where((m) => m['sender'] != 'system')
        .toList();
    msgs?.sort(
      (a, b) => DateTime.parse(
        b['created_at'],
      ).compareTo(DateTime.parse(a['created_at'])),
    );
    final latest = msgs?.isNotEmpty == true ? msgs!.first : null;
    final preview = latest?['content'] as String?;
    final isMe = latest?['sender'] == 'mechanic';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatThreadScreen(
                chatId: chat['id'],
                customerName: name,
                customerEmail: email,
                pageUrl: chat['page_url'] ?? '',
              ),
            ),
          );
        },
        onLongPress: () => _showLongPressMenu(context, chat),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _red,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Color(0xFF1A1A1A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _assignmentChip(assignee),
                      ],
                    ),
                    const SizedBox(height: 4),
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
                    const SizedBox(height: 4),
                    if (preview != null)
                      Text(
                        isMe ? 'You: $preview' : preview,
                        style: TextStyle(
                          fontSize: 13,
                          color: hasUnread && !isMe
                              ? const Color(0xFF1A1A1A)
                              : Colors.grey[500],
                          fontWeight: hasUnread && !isMe
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(chat['last_message_at']),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 8),
                  if (hasUnread)
                    Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: _red,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(height: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _assignmentChip(String? who) {
    final color = _badgeColor(who);
    final label = who ?? 'Unassigned';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

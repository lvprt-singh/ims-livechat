import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:convert';

class ChatThreadScreen extends StatefulWidget {
  final String chatId;
  final String customerName;
  final String customerPhone;
  final String pageUrl;

  const ChatThreadScreen({
    super.key,
    required this.chatId,
    required this.customerName,
    required this.customerPhone,
    required this.pageUrl,
  });

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _latestPageUrl;

  static const _red = Color(0xFFC81D24);

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _markAsRead();
    _subscribeToMessages();
  }

  void _showCustomerInfo(BuildContext context) async {
    final messages = await _supabase
        .from('messages')
        .select()
        .eq('chat_id', widget.chatId);
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
                  widget.customerName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.customerName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.customerPhone,
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

  Future<void> _markAsRead() async {
    await _supabase
        .from('chats')
        .update({'has_unread': false})
        .eq('id', widget.chatId);
  }

  Future<void> _loadMessages() async {
    final data = await _supabase
        .from('messages')
        .select()
        .eq('chat_id', widget.chatId)
        .order('created_at', ascending: true);

    final msgs = List<Map<String, dynamic>>.from(data);

    // Find latest system message for sticky banner
    final systemMsgs = msgs.where((m) => m['sender'] == 'system').toList();
    String? latestPage;
    if (systemMsgs.isNotEmpty) {
      final content = systemMsgs.last['content'] as String? ?? '';
      latestPage = content.replaceAll('📍 Customer returned from: ', '');
    } else {
      latestPage = widget.pageUrl;
    }

    setState(() {
      _messages = msgs;
      _latestPageUrl = latestPage;
      _loading = false;
    });
    _scrollToBottom();
  }

  void _subscribeToMessages() {
    _supabase
        .channel('messages-${widget.chatId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: widget.chatId,
          ),
          callback: (payload) {
            final newMsg = Map<String, dynamic>.from(payload.newRecord);
            setState(() {
              _messages.add(newMsg);
              if (newMsg['sender'] == 'system') {
                final content = newMsg['content'] as String? ?? '';
                _latestPageUrl = content.replaceAll(
                  '📍 Customer returned from: ',
                  '',
                );
              }
            });
            _scrollToBottom();
          },
        )
        .subscribe((status, [error]) {
          debugPrint('Thread realtime: $status error: $error');
        });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage({String? text, String? imageUrl}) async {
    if ((text == null || text.isEmpty) && imageUrl == null) return;
    setState(() => _sending = true);

    await _supabase.from('messages').insert({
      'chat_id': widget.chatId,
      'sender': 'mechanic',
      'content': text,
      'image_url': imageUrl,
      'source': 'widget',
    });

    await _supabase
        .from('chats')
        .update({'last_message_at': DateTime.now().toIso8601String()})
        .eq('id', widget.chatId);

    if (text != null && text.isNotEmpty) {
      await _sendSms(widget.customerPhone, text);
    }

    setState(() => _sending = false);
  }

  Future<void> _sendSms(String phone, String message) async {
    try {
      // Convert Australian number to international format
      String formattedPhone = phone.trim();
      if (formattedPhone.startsWith('04')) {
        formattedPhone = '+61${formattedPhone.substring(1)}';
      } else if (formattedPhone.startsWith('0')) {
        formattedPhone = '+61${formattedPhone.substring(1)}';
      }

      final credentials = base64Encode(utf8.encode('25QAM_:5zerpmlzljmnlr'));
      final response = await HttpClient().postUrl(
        Uri.parse('https://api.sms-gate.app/3rdparty/v1/message'),
      );
      response.headers.set('Authorization', 'Basic $credentials');
      response.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      response.write(
        jsonEncode({
          "message": message,
          "phoneNumbers": [formattedPhone],
          "deviceId": "jGPZsSEMigpxOf7_yAetR",
        }),
      );
      final result = await response.close();
      debugPrint('SMS result: ${result.statusCode}');
    } catch (e) {
      debugPrint('SMS send failed: $e');
    }
  }

  Future<void> _pickAndSendImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked == null) return;

    setState(() => _sending = true);
    final file = File(picked.path);
    final fileName =
        '${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _supabase.storage.from('chat-images').upload(fileName, file);
    final url = _supabase.storage.from('chat-images').getPublicUrl(fileName);
    await _sendMessage(imageUrl: url);
  }

  Future<void> _makeCall() async {
    final uri = Uri.parse('tel:${widget.customerPhone}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openPage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatTime(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('h:mm a').format(dt);
  }

  String _extractPage(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final path = uri.path.replaceAll('-', ' ').replaceAll('/', ' ').trim();
    return path.isEmpty ? 'Home page' : path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () => _showCustomerInfo(context),
          child: Text(
            widget.customerName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white),
            onPressed: _makeCall,
            tooltip: widget.customerPhone,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Sticky latest page banner
            if (_latestPageUrl != null && _latestPageUrl!.isNotEmpty)
              GestureDetector(
                onTap: () => _openPage(_latestPageUrl!),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 14,
                        color: _red.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Currently viewing: ${_extractPage(_latestPageUrl!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.open_in_new,
                        size: 12,
                        color: Colors.grey[400],
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _red))
                  : _messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg['sender'] == 'mechanic';
                        final isSystem = msg['sender'] == 'system';

                        if (isSystem) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  msg['content'] ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          );
                        }

                        final showTime =
                            index == _messages.length - 1 ||
                            DateTime.parse(_messages[index + 1]['created_at'])
                                    .difference(
                                      DateTime.parse(msg['created_at']),
                                    )
                                    .inMinutes >
                                5;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: isMe
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (!isMe)
                                    Container(
                                      width: 28,
                                      height: 28,
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: const BoxDecoration(
                                        color: _red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          widget.customerName[0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Container(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                          0.70,
                                    ),
                                    padding: msg['image_url'] != null
                                        ? EdgeInsets.zero
                                        : const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                    decoration: BoxDecoration(
                                      color: isMe ? _red : Colors.white,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(18),
                                        topRight: const Radius.circular(18),
                                        bottomLeft: Radius.circular(
                                          isMe ? 18 : 4,
                                        ),
                                        bottomRight: Radius.circular(
                                          isMe ? 4 : 18,
                                        ),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.06,
                                          ),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (msg['image_url'] != null)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: CachedNetworkImage(
                                              imageUrl: msg['image_url'],
                                              width: 200,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        else
                                          Text(
                                            msg['content'] ?? '',
                                            style: TextStyle(
                                              color: isMe
                                                  ? Colors.white
                                                  : const Color(0xFF1A1A1A),
                                              fontSize: 15,
                                              height: 1.3,
                                            ),
                                          ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _formatTime(msg['created_at']),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isMe
                                                ? Colors.white.withValues(
                                                    alpha: 0.65,
                                                  )
                                                : Colors.grey[400],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (showTime && index < _messages.length - 1)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    DateFormat('h:mm a').format(
                                      DateTime.parse(
                                        _messages[index + 1]['created_at'],
                                      ).toLocal(),
                                    ),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: _red),
                    onPressed: _sending ? null : _pickAndSendImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _sending
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _red,
                          ),
                        )
                      : GestureDetector(
                          onTap: () async {
                            final text = _messageController.text.trim();
                            if (text.isEmpty) return;
                            _messageController.clear();
                            await _sendMessage(text: text);
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(
                              color: _red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

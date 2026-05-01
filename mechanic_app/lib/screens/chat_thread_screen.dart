import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'dart:io';
import 'quote_form_screen.dart';

class ChatThreadScreen extends StatefulWidget {
  final String chatId;
  final String customerName;
  final String customerEmail;
  final String pageUrl;

  const ChatThreadScreen({
    super.key,
    required this.chatId,
    required this.customerName,
    required this.customerEmail,
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
  String? _assignedTo;
  String? _emailToken;
  RealtimeChannel? _channel;

  static const _red = Color(0xFFC81D24);
  static const _jesse = Color(0xFF2563EB);
  static const _stathi = Color(0xFF059669);
  static const _bg = Color(0xFFF0F0F2);

  @override
  void initState() {
    super.initState();
    _loadChat();
    _loadMessages();
    _markAsRead();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChat() async {
    final data = await _supabase
        .from('chats')
        .select('assigned_to, email_token')
        .eq('id', widget.chatId)
        .maybeSingle();
    if (!mounted || data == null) return;
    setState(() {
      _assignedTo = data['assigned_to'] as String?;
      _emailToken = data['email_token'] as String?;
    });
  }

  Future<void> _assign(String? who) async {
    final next = _assignedTo == who ? null : who;
    setState(() => _assignedTo = next);
    await _supabase
        .from('chats')
        .update({'assigned_to': next})
        .eq('id', widget.chatId);
  }

  Future<void> _markAsRead() async {
    await _supabase
        .from('chats')
        .update({'has_unread': false})
        .eq('id', widget.chatId);
  }

  Future<void> _markUnread() async {
    await _supabase
        .from('chats')
        .update({'has_unread': true})
        .eq('id', widget.chatId);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _loadMessages() async {
    final data = await _supabase
        .from('messages')
        .select()
        .eq('chat_id', widget.chatId)
        .order('created_at', ascending: true);
    final msgs = List<Map<String, dynamic>>.from(data);
    final pageMsgs = msgs.where(
      (m) =>
          m['sender'] == 'system' &&
          (m['content'] as String? ?? '').contains('Customer returned from'),
    );
    String? latestPage;
    if (pageMsgs.isNotEmpty) {
      latestPage = (pageMsgs.last['content'] as String? ?? '').replaceAll(
        '📍 Customer returned from: ',
        '',
      );
    } else {
      latestPage = widget.pageUrl;
    }
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _latestPageUrl = latestPage;
      _loading = false;
    });
    _scrollToBottom();
  }

  void _subscribe() {
    _channel = _supabase
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
            if (!mounted) return;
            setState(() {
              _messages.add(newMsg);
              final c = newMsg['content'] as String? ?? '';
              if (newMsg['sender'] == 'system' &&
                  c.contains('Customer returned from')) {
                _latestPageUrl = c.replaceAll(
                  '📍 Customer returned from: ',
                  '',
                );
              }
            });
            _scrollToBottom();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chats',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.chatId,
          ),
          callback: (payload) {
            if (!mounted) return;
            setState(
              () => _assignedTo = payload.newRecord['assigned_to'] as String?,
            );
          },
        )
        .subscribe();
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
      'source': 'dashboard',
    });
    await _supabase
        .from('chats')
        .update({'last_message_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', widget.chatId);
    if (!mounted) return;
    setState(() => _sending = false);
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

  Future<void> _requestQuoteForm() async {
    if (_emailToken == null) {
      _toast('Loading chat... try again');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Send quote form?'),
        content: Text(
          'A form link will be sent to ${widget.customerEmail} so they can fill in their vehicle details and describe the work needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final res = await _supabase.functions.invoke(
        'request-quote-form',
        body: {
          'chat_id': widget.chatId,
          'customer_email': widget.customerEmail,
          'chat_email_token': _emailToken,
        },
      );
      if (!mounted) return;
      if (res.status == 200) {
        _toast('Form link sent to customer');
      } else {
        _toast('Failed: ${res.data}');
      }
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _openSubmittedDraft(String token) async {
    try {
      final res = await _supabase.functions.invoke(
        'get-quote-draft',
        body: {'token': token},
      );
      if (!mounted) return;
      if (res.status != 200) {
        _toast('Couldn\'t load draft');
        return;
      }
      final data = res.data as Map<String, dynamic>;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuoteFormScreen(
            chatId: widget.chatId,
            customerName: data['customer_name'] ?? widget.customerName,
            customerEmail: widget.customerEmail,
            chatEmailToken: _emailToken!,
            prefilledTitle: data['title'] as String?,
            prefilledRego: data['rego'] as String?,
            prefilledCarType: data['car_type'] as String?,
            prefilledTransmission: data['transmission'] as String?,
            prefilledPhone: data['phone'] as String?,
            prefilledEngine: data['engine'] as String?,
            prefilledOdometer: data['odometer'] as String?,
            workDescription: data['work_description'] as String?,
          ),
        ),
      );
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri))
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<File?> _downloadImage(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/ims_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(path);
      await file.writeAsBytes(res.bodyBytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareImage(String url) async {
    final file = await _downloadImage(url);
    if (file == null) {
      _toast('Couldn\'t load image');
      return;
    }
    await Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> _saveImage(String url) async {
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          _toast('Permission denied');
          return;
        }
      }
      final file = await _downloadImage(url);
      if (file == null) {
        _toast('Couldn\'t load image');
        return;
      }
      await Gal.putImage(file.path, album: 'IMS');
      _toast('Saved to Photos');
    } catch (_) {
      _toast('Save failed');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _openImageViewer(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ImageViewer(
          url: url,
          onShare: () => _shareImage(url),
          onSave: () => _saveImage(url),
        ),
      ),
    );
  }

  void _showImageOptions(String url) {
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
            ListTile(
              leading: const Icon(Icons.share, color: _red),
              title: const Text(
                'Share',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(context);
                _shareImage(url);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: _red),
              title: const Text(
                'Save to Photos',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(context);
                _saveImage(url);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatTime(String iso) =>
      DateFormat('h:mm a').format(DateTime.parse(iso).toLocal());

  String _extractPage(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final path = uri.path.replaceAll('-', ' ').replaceAll('/', ' ').trim();
    return path.isEmpty ? 'Home page' : path;
  }

  void _showCustomerInfo() {
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
                  widget.customerName.isNotEmpty
                      ? widget.customerName[0].toUpperCase()
                      : '?',
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
                widget.customerEmail.isNotEmpty
                    ? widget.customerEmail
                    : 'No email',
                style: const TextStyle(fontSize: 15, color: Colors.grey),
                textAlign: TextAlign.center,
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: _showCustomerInfo,
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
            icon: const Icon(
              Icons.mark_email_unread_outlined,
              color: Colors.white,
            ),
            tooltip: 'Mark as unread',
            onPressed: _markUnread,
          ),
          IconButton(
            icon: const Icon(Icons.request_quote_outlined, color: Colors.white),
            tooltip: 'Request quote details',
            onPressed: _requestQuoteForm,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_latestPageUrl != null && _latestPageUrl!.isNotEmpty)
              _pageBanner(),
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
                  : _messagesList(),
            ),
            _inputArea(),
            _assignmentBar(),
          ],
        ),
      ),
    );
  }

  Widget _pageBanner() {
    return GestureDetector(
      onTap: () => _openUrl(_latestPageUrl!),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            Icon(Icons.open_in_new, size: 12, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _messagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final sender = msg['sender'] as String?;
        final content = msg['content'] as String? ?? '';

        if (sender == 'system' && content.contains('QUOTE_SENT|')) {
          return _quoteCard(content, msg['created_at']);
        }
        if (sender == 'system' && content.contains('QUOTE_REQUEST_SENT|')) {
          return _quoteRequestCard(content, msg['created_at']);
        }
        if (sender == 'customer' &&
            content.contains('QUOTE_DRAFT_SUBMITTED|')) {
          return _quoteDraftCard(content, msg['created_at']);
        }

        if (sender == 'system') {
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
                  content,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final isMe = sender == 'mechanic';
        final viaEmail = !isMe && msg['source'] == 'email';
        final imageUrl = msg['image_url'] as String?;

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
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
                      widget.customerName.isNotEmpty
                          ? widget.customerName[0].toUpperCase()
                          : '?',
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
                  maxWidth: MediaQuery.of(context).size.width * 0.70,
                ),
                padding: imageUrl != null
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe ? _red : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (imageUrl != null)
                      GestureDetector(
                        onTap: () => _openImageViewer(imageUrl),
                        onLongPress: () => _showImageOptions(imageUrl),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: 200,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              width: 200,
                              height: 150,
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _red,
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              width: 200,
                              height: 150,
                              color: Colors.grey[200],
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Text(
                        content,
                        style: TextStyle(
                          color: isMe ? Colors.white : const Color(0xFF1A1A1A),
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                    Padding(
                      padding: imageUrl != null
                          ? const EdgeInsets.fromLTRB(8, 4, 8, 6)
                          : const EdgeInsets.only(top: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (viaEmail) ...[
                            Icon(
                              Icons.email,
                              size: 10,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(width: 3),
                          ],
                          Text(
                            _formatTime(msg['created_at']),
                            style: TextStyle(
                              fontSize: 10,
                              color: isMe
                                  ? (imageUrl != null
                                        ? Colors.grey[500]
                                        : Colors.white.withValues(alpha: 0.65))
                                  : Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _quoteCard(String content, String createdAt) {
    final parts = content.replaceFirst('📄 QUOTE_SENT|', '').split('|');
    final quoteNum = parts.isNotEmpty ? parts[0] : '';
    final url = parts.length > 1 ? parts[1] : '';
    final total = parts.length > 2 ? parts[2] : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: GestureDetector(
          onTap: () => _openUrl(url),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _red.withValues(alpha: 0.25), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf,
                    color: _red,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quote sent',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$quoteNum  ·  $total',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(createdAt),
                        style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quoteRequestCard(String content, String createdAt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _jesse.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _jesse.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.send_outlined, size: 14, color: _jesse),
              const SizedBox(width: 6),
              Text(
                'Quote form sent · ${_formatTime(createdAt)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: _jesse,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quoteDraftCard(String content, String createdAt) {
    final parts = content
        .replaceFirst('📋 QUOTE_DRAFT_SUBMITTED|', '')
        .split('|');
    final token = parts.isNotEmpty ? parts[0] : '';
    final title = parts.length > 1 ? parts[1] : '';
    final name = parts.length > 2 ? parts[2] : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: GestureDetector(
          onTap: () => _openSubmittedDraft(token),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _stathi.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _stathi.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.assignment_turned_in,
                    color: _stathi,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Customer submitted details',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title.isNotEmpty ? '$title · $name' : name,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to build quote · ${_formatTime(createdAt)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _stathi,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputArea() {
    return Container(
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: _red),
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
    );
  }

  Widget _assignmentBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Row(
        children: [
          Expanded(child: _assignButton('Jesse', _jesse)),
          const SizedBox(width: 10),
          Expanded(child: _assignButton('Stathi', _stathi)),
        ],
      ),
    );
  }

  Widget _assignButton(String name, Color color) {
    final selected = _assignedTo == name;
    return GestureDetector(
      onTap: () => _assign(name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 40,
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.person_outline,
              size: 16,
              color: selected ? Colors.white : color,
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final String url;
  final VoidCallback onShare;
  final VoidCallback onSave;

  const _ImageViewer({
    required this.url,
    required this.onShare,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: onShare,
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: onSave,
          ),
        ],
      ),
      body: PhotoView(
        imageProvider: CachedNetworkImageProvider(url),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4,
        loadingBuilder: (_, __) =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
  }
}

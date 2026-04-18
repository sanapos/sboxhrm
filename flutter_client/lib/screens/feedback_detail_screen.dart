import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';

class FeedbackDetailScreen extends StatefulWidget {
  final String feedbackId;
  final bool isMine; // true = I am the original sender

  const FeedbackDetailScreen({
    super.key,
    required this.feedbackId,
    required this.isMine,
  });

  @override
  State<FeedbackDetailScreen> createState() => _FeedbackDetailScreenState();
}

class _FeedbackDetailScreenState extends State<FeedbackDetailScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _replyCtl = TextEditingController();
  final ScrollController _scrollCtl = ScrollController();
  final ImagePicker _picker = ImagePicker();

  Map<String, dynamic>? _feedback;
  List<Map<String, dynamic>> _replies = [];
  bool _isLoading = true;
  bool _isSending = false;

  static const _primary = Color(0xFF1E3A5F);
  static const _statusLabels = {
    'Pending': 'Chờ xử lý',
    'InProgress': 'Đang xử lý',
    'Resolved': 'Đã giải quyết',
    'Closed': 'Đã đóng',
  };
  static const _statusColors = {
    'Pending': Color(0xFFF59E0B),
    'InProgress': Color(0xFF3B82F6),
    'Resolved': Color(0xFF10B981),
    'Closed': Color(0xFF6B7280),
  };
  static const _categoryLabels = {
    'General': 'Chung',
    'Complaint': 'Khiếu nại',
    'Suggestion': 'Đề xuất',
    'Other': 'Khác',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _replyCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getFeedbackReplies(widget.feedbackId);
      if (res['isSuccess'] == true) {
        final data = res['data'];
        _feedback = Map<String, dynamic>.from(data['feedback'] ?? {});
        _replies = List<Map<String, dynamic>>.from(data['replies'] ?? []);
      }
    } catch (e) {
      debugPrint('Load feedback detail error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtl.hasClients) {
        _scrollCtl.animateTo(
          _scrollCtl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendReply() async {
    final text = _replyCtl.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final res = await _apiService.createFeedbackReply(
        widget.feedbackId,
        {'content': text},
      );
      if (res['isSuccess'] == true) {
        _replyCtl.clear();
        await _loadData();
      } else {
        if (mounted) {
          NotificationOverlayManager().showError(
            title: 'Lỗi',
            message: res['message'] ?? 'Không thể gửi phản hồi',
          );
        }
      }
    } catch (e) {
      debugPrint('Send reply error: $e');
    }
    if (mounted) setState(() => _isSending = false);
  }

  Future<void> _pickAndUploadImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (picked == null) return;

    // First create a reply with image placeholder text
    setState(() => _isSending = true);
    try {
      final replyRes = await _apiService.createFeedbackReply(
        widget.feedbackId,
        {'content': '📷 Hình ảnh'},
      );
      if (replyRes['isSuccess'] == true) {
        final replyData = replyRes['data'];
        final replyId = replyData['id']?.toString();
        if (replyId != null) {
          // Upload image to the reply
          await _apiService.uploadFeedbackReplyImage(
            widget.feedbackId, replyId, picked.path,
          );
        }
        await _loadData();
      }
    } catch (e) {
      debugPrint('Upload image error: $e');
    }
    if (mounted) setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Phản ánh'),
          backgroundColor: _primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_feedback == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Phản ánh'),
          backgroundColor: _primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Không tìm thấy phản ánh')),
      );
    }

    final fb = _feedback!;
    final status = fb['status'] ?? 'Pending';
    final isAnonymous = fb['isAnonymous'] == true;
    final isClosed = status == 'Closed';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          fb['title'] ?? 'Phản ánh',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (_statusColors[status] ?? Colors.grey).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _statusLabels[status] ?? status,
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: _statusColors[status] ?? Colors.grey,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: ListView(
              controller: _scrollCtl,
              padding: const EdgeInsets.all(12),
              children: [
                // Original feedback as first message
                _buildOriginalFeedback(fb),
                const SizedBox(height: 8),
                // Old single response (if exists, for backward compat)
                if (fb['response'] != null && fb['response'].toString().isNotEmpty)
                  _buildLegacyResponse(fb),
                // Replies
                ..._replies.map((r) => _buildReplyBubble(r, isAnonymous)),
              ],
            ),
          ),
          // Reply input bar
          if (!isClosed) _buildReplyBar(),
        ],
      ),
    );
  }

  Widget _buildOriginalFeedback(Map<String, dynamic> fb) {
    final isAnonymous = fb['isAnonymous'] == true;
    final senderName = fb['senderName'] as String?;
    final createdAt = DateTime.tryParse(fb['createdAt'] ?? '') ?? DateTime.now();
    final category = fb['category'] ?? 'General';
    final imageUrls = List<String>.from(fb['imageUrls'] ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isAnonymous ? const Color(0xFFEF4444) : _primary,
                child: Icon(
                  isAnonymous ? Icons.visibility_off : Icons.person,
                  size: 16, color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAnonymous ? 'Ẩn danh' : (senderName ?? 'Nhân viên'),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    Text(
                      '${_categoryLabels[category] ?? category} • ${DateFormat('dd/MM/yyyy HH:mm').format(createdAt)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Title
          Text(
            fb['title'] ?? '',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          // Content with linkified text
          _buildRichContent(fb['content'] ?? ''),
          // Images
          if (imageUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildImageGrid(imageUrls),
          ],
        ],
      ),
    );
  }

  Widget _buildLegacyResponse(Map<String, dynamic> fb) {
    final response = fb['response'] as String?;
    if (response == null || response.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, right: 48),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.reply, size: 14, color: Color(0xFF059669)),
                const SizedBox(width: 4),
                Text(
                  'Phản hồi (cũ)',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _buildRichContent(response),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBubble(Map<String, dynamic> reply, bool isAnonymousFeedback) {
    final isFromSender = reply['isFromSender'] == true;
    final senderName = reply['senderName'] as String?;
    final content = reply['content'] ?? '';
    final createdAt = DateTime.tryParse(reply['createdAt'] ?? '') ?? DateTime.now();
    final imageUrls = List<String>.from(reply['imageUrls'] ?? []);

    // If this feedback is mine: my replies on right, others on left
    // If this is mailbox: sender replies on left, my replies on right
    final isMe = widget.isMine ? isFromSender : !isFromSender;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? _primary.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(2),
            bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(12),
          ),
          border: Border.all(
            color: isMe ? _primary.withValues(alpha: 0.2) : const Color(0xFFE4E4E7),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender name
            if (!isMe) ...[
              Text(
                isAnonymousFeedback && isFromSender
                    ? 'Ẩn danh'
                    : (senderName ?? 'Nhân viên'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isFromSender ? const Color(0xFFEF4444) : _primary,
                ),
              ),
              const SizedBox(height: 4),
            ],
            // Content
            _buildRichContent(content),
            // Images
            if (imageUrls.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildImageGrid(imageUrls),
            ],
            // Time
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm dd/MM').format(createdAt),
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRichContent(String text) {
    // Split text by URL patterns and make them tappable
    final urlRegex = RegExp(
      r'(https?://[^\s<>\[\]{}|\\^]+)',
      caseSensitive: false,
    );

    final matches = urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 14, height: 1.4));
    }

    final spans = <InlineSpan>[];
    var lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
        ));
      }
      final url = match.group(0)!;
      spans.add(WidgetSpan(
        child: GestureDetector(
          onTap: () => _launchUrl(url),
          child: Text(
            url,
            style: const TextStyle(
              fontSize: 14, height: 1.4,
              color: Color(0xFF3B82F6),
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildImageGrid(List<String> imageUrls) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: imageUrls.map((url) => GestureDetector(
        onTap: () => _showFullImage(url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            width: 120, height: 120,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 120, height: 120,
              color: Colors.grey[200],
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        ),
      )).toList(),
    );
  }

  void _showFullImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
            Positioned(
              top: 8, right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12, right: 8, top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8, offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Image button
          IconButton(
            icon: const Icon(Icons.image_outlined, color: Color(0xFF64748B)),
            onPressed: _isSending ? null : _pickAndUploadImage,
            tooltip: 'Gửi hình ảnh',
          ),
          // Text input
          Expanded(
            child: TextField(
              controller: _replyCtl,
              decoration: InputDecoration(
                hintText: 'Nhập phản hồi...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: _primary),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10,
                ),
                isDense: true,
              ),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendReply(),
            ),
          ),
          const SizedBox(width: 4),
          // Send button
          IconButton(
            icon: _isSending
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, color: _primary),
            onPressed: _isSending ? null : _sendReply,
          ),
        ],
      ),
    );
  }
}

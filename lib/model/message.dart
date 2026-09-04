import 'dart:convert';
import 'dart:typed_data';

class Message {
  final String id;
  final String text;
  final bool isUser;
  bool isLoading;
  final String? attachmentName;
  final String? attachmentMimeType;

  final List<Uint8List>? attachmentBytesList;

  final List<String>? attachmentImageUrls;
  final String? aiSource;
  final String? replyToId;
  final String? replyToPreview;
  final String? replyToSource;
  final String? imageUrl;

  Message({
    String? id,
    this.imageUrl,
    required this.text,
    required this.isUser,
    this.isLoading = false,
    this.attachmentName,
    this.attachmentMimeType,
    this.attachmentBytesList,
    this.attachmentImageUrls,
    this.aiSource,
    this.replyToId,
    this.replyToPreview,
    this.replyToSource,
  }) : id = id ?? _generateId();

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  static String _generateId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  bool get hasAttachment => attachmentName != null;
  bool get isImageAttachment =>
      attachmentMimeType?.startsWith('image/') ?? false;
  bool get hasReply => replyToId != null;

  bool get hasAttachedImages =>
      (attachmentBytesList != null && attachmentBytesList!.isNotEmpty) ||
      (attachmentImageUrls != null && attachmentImageUrls!.isNotEmpty);

  static List<String>? _parseImageUrls(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {
        return [raw];
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'isUser': isUser,
    'image_url': imageUrl,
    'attachmentName': attachmentName,
    'attachmentMimeType': attachmentMimeType,
    'attachmentImageUrls': attachmentImageUrls,
    'aiSource': aiSource,
    'replyToId': replyToId,
    'replyToPreview': replyToPreview,
    'replyToSource': replyToSource,
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String?,
    text: json['text'] as String? ?? '',
    isUser: json['isUser'] as bool,
    imageUrl: json['image_url'] as String?,
    attachmentName: json['attachmentName'] as String?,
    attachmentMimeType: json['attachmentMimeType'] as String?,
    attachmentImageUrls: _parseImageUrls(json['attachmentImageUrls']),
    aiSource: json['aiSource'] as String?,
    replyToId: json['replyToId'] as String?,
    replyToPreview: json['replyToPreview'] as String?,
    replyToSource: json['replyToSource'] as String?,
  );
}

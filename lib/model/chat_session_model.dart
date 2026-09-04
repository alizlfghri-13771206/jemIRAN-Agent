import 'dart:convert';
import 'package:jemiran/model/message.dart';

class ChatSessionModel {
  final int? id;
  final String title;
  final List<Message> messages;
  final int createdAt;
  final String? modelDefault;

  const ChatSessionModel({
    this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    this.modelDefault,
  });

  static String buildTitle(List<Message> messages) {
    final firstUser = messages.firstWhere(
      (m) => m.isUser && !m.isLoading,
      orElse: () => Message(text: '', isUser: true),
    );
    final raw = firstUser.text.trim();
    return raw.isEmpty
        ? ''
        : (raw.length > 40 ? '${raw.substring(0, 40)}…' : raw);
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'messages': jsonEncode(
        messages.where((m) => !m.isLoading).map((m) => m.toJson()).toList(),
      ),
      'created_at': createdAt,
    };
  }

  factory ChatSessionModel.fromMap(Map<String, dynamic> map) {
    final List<dynamic> msgList =
        jsonDecode(map['messages'] as String) as List<dynamic>;
    return ChatSessionModel(
      id: map['id'] as int?,
      title: map['title'] as String,
      messages: msgList
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList(),
      createdAt: map['created_at'] as int,
    );
  }

  ChatSessionModel copyWith({
    int? id,
    String? title,
    List<Message>? messages,
    int? createdAt,
  }) {
    return ChatSessionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

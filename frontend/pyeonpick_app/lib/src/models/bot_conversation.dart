import 'bot_message.dart';

class BotConversation {
  const BotConversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
  });

  factory BotConversation.fromJson(Map<String, dynamic> json) {
    return BotConversation(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '대화',
      messages: (json['messages'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => BotMessage.fromJson(item as Map<String, dynamic>))
          .toList(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  final String id;
  final String title;
  final List<BotMessage> messages;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((message) => message.toJson()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

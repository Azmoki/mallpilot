import 'store.dart';

/// One bubble in the chat. A bot message may carry recommended stores.
class ChatMessage {
  final String text;
  final bool isUser;
  final List<Store> stores;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.stores = const [],
  });
}

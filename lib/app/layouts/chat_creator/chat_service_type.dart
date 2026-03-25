/// Represents the messaging service to use when creating a new chat.
///
/// Add new service types here. Set [isVisible] to false to define a service
/// without exposing it in the UI (e.g. RCS, which is defined but not yet shown).
enum ChatServiceType {
  iMessage(label: 'iMessage', isVisible: true),
  sms(label: 'SMS', isVisible: true),
  rcs(label: 'RCS', isVisible: false);

  const ChatServiceType({required this.label, required this.isVisible});

  final String label;
  final bool isVisible;

  /// Returns the server-side method string for this service type.
  String get method {
    switch (this) {
      case ChatServiceType.iMessage:
        return 'iMessage';
      case ChatServiceType.sms:
        return 'SMS';
      case ChatServiceType.rcs:
        return 'RCS';
    }
  }

  /// Whether chats of this type are iMessage chats (used to filter the chat list).
  bool get isIMessageService => this == ChatServiceType.iMessage;
}

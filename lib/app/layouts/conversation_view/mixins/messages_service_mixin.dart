import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';

/// Mixin for initializing and managing MessagesService with proper message controllers and states.
/// This ensures MessageHolder widgets have access to MessageState observables for reactivity.
/// 
/// Supports two initialization modes:
/// 1. Pre-loaded messages (peek view, dialogs): Use initializeMessagesService()
/// 2. Lazy loading (conversation view): Use initializeMessagesServiceWithLoading()
/// 
/// Usage:
/// 1. Apply this mixin to your State class
/// 2. Call one of the initialize methods in initState
/// 3. Call disposeMessagesService() in dispose
/// 4. Access via the messageService getter
mixin MessagesServiceMixin<T extends StatefulWidget> on State<T> {
  MessagesService? _messageService;
  
  /// Get the messages service instance
  MessagesService get messageService {
    assert(_messageService != null, 'MessagesService not initialized. Call initialize method first.');
    return _messageService!;
  }
  
  /// Check if the service has been initialized
  bool get isMessagesServiceInitialized => _messageService != null;
  
  /// Initialize the messages service with a pre-loaded list of messages.
  /// Use this for simple cases like peek views or dialogs where messages are already loaded.
  /// 
  /// Parameters:
  /// - chat: The chat for this messages service
  /// - messages: Initial list of messages to add to struct and create controllers for
  /// - cvController: The conversation view controller to link to each message controller
  /// - customService: Optional custom MessagesService instance (for testing or special cases)
  /// - onNewMessage: Handler for new messages (optional, defaults to no-op)
  /// - onUpdatedMessage: Handler for updated messages (optional, defaults to no-op)
  /// - onDeletedMessage: Handler for deleted messages (optional, defaults to no-op)
  /// - onJumpToMessage: Handler for jump to message requests (optional, defaults to no-op)
  void initializeMessagesService(
    Chat chat,
    List<Message> messages,
    ConversationViewController cvController, {
    MessagesService? customService,
    void Function(Message)? onNewMessage,
    void Function(Message, {String? oldGuid})? onUpdatedMessage,
    void Function(Message)? onDeletedMessage,
    void Function(String)? onJumpToMessage,
  }) {
    // Use custom service or get/create singleton
    _messageService = customService ?? MessagesSvc(chat.guid);
    
    // Initialize with handlers (use no-ops if not provided)
    _messageService!.init(
      chat,
      onNewMessage ?? (_) {},
      onUpdatedMessage ?? (_, {String? oldGuid}) {},
      onDeletedMessage ?? (_) {},
      onJumpToMessage ?? (_) {},
    );
    
    // Add messages to struct (required for MessageState creation)
    final messagesToAdd = messages.where((m) => m.guid != null && _messageService!.struct.getMessage(m.guid!) == null).toList();
    if (messagesToAdd.isNotEmpty) {
      _messageService!.struct.addMessages(messagesToAdd);
    }
    
    // Ensure MessageStates exist for all messages (created on-demand via getMessageState)
    for (final message in messages) {
      if (message.guid != null) {
        _messageService!.getOrCreateMessageState(message.guid!);
      }
    }
    
    // Create controllers and link them
    _createControllers(messages, cvController);
  }
  
  /// Initialize the messages service with lazy loading support.
  /// Use this for conversation views where messages are loaded incrementally.
  /// 
  /// Parameters:
  /// - chat: The chat for this messages service
  /// - cvController: The conversation view controller to link to each message controller
  /// - customService: Optional custom MessagesService instance (for testing or special cases)
  /// - loadInitialChunk: Whether to load the first chunk of messages (defaults to true)
  /// - searchMessage: Optional message to load around (for search results)
  /// - onNewMessage: Handler for new messages (required for conversation views)
  /// - onUpdatedMessage: Handler for updated messages (required for conversation views)
  /// - onDeletedMessage: Handler for deleted messages (required for conversation views)
  /// - onJumpToMessage: Handler for jump to message requests (required for conversation views)
  /// 
  /// Returns: List of loaded messages (empty if loadInitialChunk is false)
  Future<List<Message>> initializeMessagesServiceWithLoading(
    Chat chat,
    ConversationViewController cvController, {
    MessagesService? customService,
    bool loadInitialChunk = true,
    Message? searchMessage,
    required void Function(Message) onNewMessage,
    required void Function(Message, {String? oldGuid}) onUpdatedMessage,
    required void Function(Message) onDeletedMessage,
    required void Function(String) onJumpToMessage,
  }) async {
    // Use custom service or get/create singleton
    _messageService = customService ?? MessagesSvc(chat.guid);
    
    // Initialize with handlers
    _messageService!.init(chat, onNewMessage, onUpdatedMessage, onDeletedMessage, onJumpToMessage);
    
    List<Message> messages = [];
    
    if (loadInitialChunk) {
      // Handle search-based loading
      if (_messageService!.method != null && searchMessage != null) {
        await _messageService!.loadSearchChunk(
          searchMessage,
          _messageService!.method == "local" ? SearchMethod.local : SearchMethod.network,
        );
      } 
      // Handle normal chunk loading
      else if (_messageService!.struct.isEmpty) {
        await _messageService!.loadChunk(0, cvController);
      }
      
      // Get loaded messages from struct
      messages = _messageService!.struct.messages;
      messages.sort(Message.sort);
      
      // Ensure MessageStates exist for all loaded messages
      for (final message in messages) {
        if (message.guid != null) {
          _messageService!.getOrCreateMessageState(message.guid!);
        }
      }
      
      // Create controllers for loaded messages
      _createControllers(messages, cvController);
    }
    
    return messages;
  }
  
  /// Helper method to create and link controllers for a list of messages
  void _createControllers(List<Message> messages, ConversationViewController cvController) {
    for (final message in messages) {
      if (message.guid != null) {
        final controller = _messageService!.getOrCreateController(message);
        controller.cvController = cvController;
      }
    }
  }
  
  /// Load the next chunk of messages (for pagination)
  /// Returns true if more messages are available, false if no more messages
  Future<bool> loadNextChunk(
    ConversationViewController cvController,
    List<Message> currentMessages, {
    int limit = 25,
  }) async {
    assert(_messageService != null, 'MessagesService not initialized');
    
    // Load the next chunk using the service
    final hasMore = await _messageService!.loadChunk(
      currentMessages.length,
      cvController,
      limit: limit,
    );
    
    return hasMore;
  }
  
  /// Load a search chunk around a specific message
  Future<void> loadSearchChunk(Message message, SearchMethod method) async {
    assert(_messageService != null, 'MessagesService not initialized');
    await _messageService!.loadSearchChunk(message, method);
  }
  
  /// Reload the entire messages service (clears and reinitializes)
  Future<void> reloadMessagesService(
    Chat chat,
    ConversationViewController cvController, {
    required void Function(Message) onNewMessage,
    required void Function(Message, {String? oldGuid}) onUpdatedMessage,
    required void Function(Message) onDeletedMessage,
    required void Function(String) onJumpToMessage,
  }) async {
    assert(_messageService != null, 'MessagesService not initialized');
    
    _messageService!.reload();
    _messageService!.init(chat, onNewMessage, onUpdatedMessage, onDeletedMessage, onJumpToMessage);
  }
  
  /// Create and link a controller for a new message
  /// Use this when handling new messages that aren't in the existing list
  /// Returns the created controller
  MessageWidgetController createControllerForMessage(
    Message message,
    ConversationViewController cvController,
  ) {
    assert(_messageService != null, 'MessagesService not initialized');
    
    final controller = _messageService!.getOrCreateController(message);
    controller.cvController = cvController;
    return controller;
  }
  
  /// Create and link controllers for multiple new messages
  /// Use this when handling bulk message additions
  void createControllersForMessages(
    List<Message> messages,
    ConversationViewController cvController,
  ) {
    assert(_messageService != null, 'MessagesService not initialized');
    _createControllers(messages, cvController);
  }
  
  /// Dispose the messages service and clean up resources
  void disposeMessagesService({bool force = false}) {
    _messageService?.close(force: force);
    _messageService = null;
  }
}

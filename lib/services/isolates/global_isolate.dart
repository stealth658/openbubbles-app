import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/services.dart';
import 'package:bluebubbles/helpers/backend/startup_tasks.dart';
import 'package:bluebubbles/services/isolates/isolate_actions.dart';
import 'package:bluebubbles/services/isolates/isolate_event.dart';

/// A global isolate manager for handling background tasks
class GlobalIsolate {
  Isolate? _isolate;
  final ReceivePort _receivePort = ReceivePort();
  SendPort? _sendPort;
  final Map<String, _RequestInfo> _pendingRequests = {};
  final StreamController<dynamic> _controller = StreamController.broadcast();
  final Map<IsolateEvent, List<Function(dynamic)>> _eventListeners = {};
  bool _isRunning = false;
  bool _isStarting = false;
  Completer<void> _startCompleter = Completer<void>();
  static const String _isolatePortName = 'GlobalIsolate';

  /// Default timeout duration for requests
  final Duration timeout;

  /// Stream of outputs from the isolate
  Stream<dynamic> get outputStream => _controller.stream;

  /// Whether the isolate is currently running
  bool get isRunning => _isRunning;

  GlobalIsolate({this.timeout = const Duration(seconds: 30)});

  /// Starts the isolate if not already running
  Future<void> _ensureStarted() async {
    if (_isRunning) return;
    if (_isStarting) {
      // Wait for startup to complete if already in progress
      return _startCompleter.future;
    }

    _isStarting = true;

    try {
      // Register the receive port with a name so it can be found by other isolates
      IsolateNameServer.registerPortWithName(_receivePort.sendPort, _isolatePortName);

      Logger.debug('Starting GlobalIsolate...');
      // Pass the RootIsolateToken from the main isolate so the spawned isolate can initialize BackgroundIsolateBinaryMessenger
      final rootToken = RootIsolateToken.instance;
      _isolate = await Isolate.spawn(GlobalIsolate._isolateEntryPoint, [_receivePort.sendPort, rootToken],
          debugName: 'GlobalIsolate');
      Logger.debug('GlobalIsolate started.');

      _isRunning = true;

      _receivePort.listen(_handleIsolateMessage);

      // Wait for the SendPort from the spawned isolate
      await _waitForSendPort();

      _startCompleter.complete();
    } catch (e) {
      _startCompleter.completeError(e);
      rethrow;
    } finally {
      _isStarting = false;
    }
  }

  Future<void> _waitForSendPort() async {
    final completer = Completer<void>();

    Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (_sendPort != null) {
        timer.cancel();
        completer.complete();
      }
    });

    return completer.future;
  }

  /// Stops the isolate
  void stop() {
    if (!_isRunning) return;

    // Unregister the named port when stopping
    IsolateNameServer.removePortNameMapping(_isolatePortName);
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort.close();
    _controller.close();

    // Complete all pending requests with an error
    for (final requestInfo in _pendingRequests.values) {
      if (!requestInfo.completer.isCompleted) {
        requestInfo.completer.completeError('Isolate was stopped');
        requestInfo.timer?.cancel();
      }
    }

    _pendingRequests.clear();
    _eventListeners.clear();
    _isolate = null;
    _sendPort = null;
    _isRunning = false;

    // Reset the start completer
    if (_startCompleter.isCompleted) {
      _startCompleter = Completer<void>();
    }
  }

  /// Closes the isolate and clears all listeners
  void close() {
    stop();
  }

  /// Register a listener for a specific event type
  void addEventListener(IsolateEvent event, Function(dynamic) listener) {
    if (!_eventListeners.containsKey(event)) {
      _eventListeners[event] = [];
    }
    _eventListeners[event]!.add(listener);
    Logger.debug('Registered listener for event: ${event.name}');
  }

  /// Remove a specific listener for an event type
  void removeEventListener(IsolateEvent event, Function(dynamic) listener) {
    if (_eventListeners.containsKey(event)) {
      _eventListeners[event]!.remove(listener);
      if (_eventListeners[event]!.isEmpty) {
        _eventListeners.remove(event);
      }
      Logger.debug('Removed listener for event: ${event.name}');
    }
  }

  /// Remove all listeners for a specific event type
  void removeAllEventListeners(IsolateEvent event) {
    if (_eventListeners.containsKey(event)) {
      _eventListeners.remove(event);
      Logger.debug('Removed all listeners for event: ${event.name}');
    }
  }

  /// Clear all event listeners
  void clearAllEventListeners() {
    _eventListeners.clear();
    Logger.debug('Cleared all event listeners');
  }

  /// Sends a request to the isolate and waits for a response
  Future<T> send<T>(IsolateRequestType type, {dynamic input, Duration? customTimeout}) async {
    await _ensureStarted();

    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    final completer = Completer<T>();

    // Set up timeout
    final timer = Timer(customTimeout ?? timeout, () {
      if (_pendingRequests.containsKey(requestId)) {
        final requestInfo = _pendingRequests.remove(requestId)!;
        if (!requestInfo.completer.isCompleted) {
          requestInfo.completer.completeError('Request timeout after ${customTimeout ?? timeout}');
        }
      }
    });

    _pendingRequests[requestId] = _RequestInfo(completer: completer, timer: timer, type: type);

    // Create a standard request message
    final message = IsolateRequest(uuid: requestId, type: type, data: input).toMap();

    _sendPort!.send(message);

    return completer.future;
  }

  /// Fire-and-forget send (no response expected)
  void broadcast(IsolateRequestType type, dynamic input) {
    _ensureStarted().then((_) {
      // Create a standard request message with empty UUID since no response is expected
      final message = IsolateRequest(uuid: '', type: type, data: input).toMap();

      _sendPort!.send(message);
    });
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      return;
    }

    if (message is Map<String, dynamic>) {
      // Check if this is an event message
      if (message.containsKey('event')) {
        try {
          final eventMessage = IsolateEventMessage.fromMap(message);
          _handleEvent(eventMessage);
          return;
        } catch (e) {
          Logger.error('Failed to parse event message: $e');
        }
      }

      // Otherwise, treat it as a response
      final isolateResponse = IsolateResponse.fromMap(message);
      final uuid = isolateResponse.uuid;

      if (uuid.isNotEmpty && _pendingRequests.containsKey(uuid)) {
        final requestInfo = _pendingRequests.remove(uuid)!;
        requestInfo.timer?.cancel();

        if (isolateResponse.ok) {
          requestInfo.completer.complete(isolateResponse.data);
        } else {
          requestInfo.completer.completeError(isolateResponse.error ?? 'Unknown error');
        }
      } else if (isolateResponse.data != null) {
        // Broadcast the response data
        _controller.add(isolateResponse.data);
      }
    } else {
      // Direct message from isolate (not wrapped in IsolateResponse)
      _controller.add(message);
    }
  }

  /// Handle an event from the isolate
  void _handleEvent(IsolateEventMessage eventMessage) {
    Logger.debug('Received event from isolate: ${eventMessage.type.name}');
    
    if (_eventListeners.containsKey(eventMessage.type)) {
      final listeners = List.from(_eventListeners[eventMessage.type]!);
      for (final listener in listeners) {
        try {
          listener(eventMessage.data);
        } catch (e, stack) {
          Logger.error('Error in event listener for ${eventMessage.type.name}: $e', trace: stack);
        }
      }
    }
  }

  /// The isolate entry point - should be implemented by the service using this class
  static Future<void> _isolateEntryPoint(List<dynamic> args) async {
    final SendPort sendPort = args[0];
    final RootIsolateToken? rootIsolateToken = args.length > 1 ? args[1] : null;
    await StartupTasks.initGlobalIsolateServices(rootIsolateToken);

    // Store the send port for event emission
    IsolateEventEmitter._setSendPort(sendPort);

    // Create a receiver for the isolate
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    receivePort.listen((message) async {
      if (message is! Map<String, dynamic>) return;

      final isolateRequest = IsolateRequest.fromMap(message);
      final String uuid = isolateRequest.uuid;
      final type = isolateRequest.type;
      final dynamic data = isolateRequest.data;
      print('Received request: $type');

      try {
        final action = IsolateActons.actions[type];
        if (action == null) {
          throw Exception('Unknown request type: $type');
        }

        // Check function signature using Function.toString() introspection
        final functionStr = action.toString();
        final isAsync = functionStr.contains('Future<');
        final hasInput = !functionStr.contains('()') && !functionStr.contains('Function()');
        final hasOutput = !functionStr.contains('void Function');

        if (isAsync) {
          if (!hasInput && hasOutput) {
            // Future<T> Function()
            final result = await action();
            sendPort.send(IsolateResponse.success(uuid: uuid, data: result).toMap());
          } else if (hasInput && !hasOutput) {
            // Future<void> Function(T)
            await action(data);
            sendPort.send(IsolateResponse.success(uuid: uuid).toMap());
          } else if (!hasInput && !hasOutput) {
            // Future<void> Function()
            await action();
            sendPort.send(IsolateResponse.success(uuid: uuid).toMap());
          } else {
            // Future<R> Function(T)
            final result = await action(data);
            sendPort.send(IsolateResponse.success(uuid: uuid, data: result).toMap());
          }
        } else {
          // Synchronous functions
          if (!hasInput && hasOutput) {
            // T Function()
            final result = action();
            sendPort.send(IsolateResponse.success(uuid: uuid, data: result).toMap());
          } else if (hasInput && !hasOutput) {
            // void Function(T)
            action(data);
            sendPort.send(IsolateResponse.success(uuid: uuid).toMap());
          } else if (!hasInput && !hasOutput) {
            // void Function()
            action();
            sendPort.send(IsolateResponse.success(uuid: uuid).toMap());
          } else {
            // R Function(T)
            final result = action(data);
            sendPort.send(IsolateResponse.success(uuid: uuid, data: result).toMap());
          }
        }

        print('Returning request: $type');
      } catch (e) {
        print('Error in isolate action: $e');

        // Send standardized error response
        sendPort.send(
          IsolateResponse.error(uuid: uuid, error: e.toString(), message: "Error executing isolate action").toMap(),
        );
      }
    });
  }
}

enum IsolateRequestType {
  // Test actions
  testReturnInput,
  testPrintInput,
  testThrowError,

  // App actions
  checkForUpdate,
  getFcmData,

  // Server actions
  checkForServerUpdate,
  getServerDetails,

  // Image actions
  convertImageToPng,
  readExifData,
  getGifDimensions,

  // Prefs actions
  saveReplyToMessageState,
  loadReplyToMessageState,
  syncAllSettings,
  syncSettings,

  // Messages actions
  getMessages,

  // Chat actions
  clearNotificationForChat,
  markChatReadUnread,
  saveChat,
  deleteChat,
  softDeleteChat,
  unDeleteChat,
  addMessageToChat,
  loadSupplementalData,
  syncLatestMessages,
  bulkSyncChats,
  getMessagesAsync,
  bulkSyncMessages,
  getParticipantsAsync,
  clearTranscriptAsync,
  getChatsAsync,

  // Handle actions
  saveHandleAsync,
  bulkSaveHandlesAsync,
  findOneHandleAsync,
  findHandlesAsync,

  // Contact actions
  saveContactAsync,
  findOneContactAsync,

  // ContactV2 actions (new contact service)
  syncContactsToHandles,
  getStoredContactIds,
  findOneContact,
  getContactsForHandles,
  getContactByAddress,
  getAllContacts,
  fetchNetworkContacts,
  getContactAvatar,

  // Attachment actions
  saveAttachmentAsync,
  bulkSaveAttachmentsAsync,
  replaceAttachmentAsync,
  findOneAttachmentAsync,
  findAttachmentsAsync,
  deleteAttachmentAsync,

  // Sync actions
  performIncrementalSync,
  uploadContacts,
  getAllContactsAsync,

  // Message actions
  bulkSaveNewMessages,
  bulkAddMessages,
  replaceMessage,
  fetchAttachmentsAsync,
  getChatAsync,
  deleteMessage,
  softDeleteMessage,
  fetchAssociatedMessagesAsync,
  saveMessageAsync,
  findOneAsync,
  findAsync,
}

/// Internal class to track pending requests
class _RequestInfo<T> {
  final Completer<T> completer;
  final Timer? timer;
  final IsolateRequestType type;

  _RequestInfo({required this.completer, this.timer, required this.type});
}

/// A standard request format for isolate communication
class IsolateRequest<T> {
  /// Unique identifier for the request
  final String uuid;

  /// Type of the request
  final IsolateRequestType type;

  /// Data payload
  final T? data;

  IsolateRequest({required this.uuid, required this.type, this.data});

  /// Convert request to a map
  Map<String, dynamic> toMap() {
    return {'uuid': uuid, 'type': type, if (data != null) 'data': data};
  }

  /// Create a request from a map
  factory IsolateRequest.fromMap(Map<String, dynamic> map) {
    return IsolateRequest(uuid: map['uuid'] as String, type: map['type'], data: map['data'] as T?);
  }
}

/// A standard response format for isolate communication
class IsolateResponse<T> {
  /// Unique identifier for the request
  final String uuid;

  /// Indicates if the operation was successful
  final bool ok;

  /// Error details if ok is false
  final String? error;

  /// Optional message about the operation
  final String? message;

  /// Optional data payload
  final T? data;

  IsolateResponse({required this.uuid, required this.ok, this.error, this.message, this.data});

  /// Create a success response
  factory IsolateResponse.success({required String uuid, String? message, T? data}) {
    return IsolateResponse(uuid: uuid, ok: true, message: message, data: data);
  }

  /// Create an error response
  factory IsolateResponse.error({required String uuid, required String error, String? message}) {
    return IsolateResponse(uuid: uuid, ok: false, error: error, message: message);
  }

  /// Convert response to a map
  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'ok': ok,
      if (error != null) 'error': error,
      if (message != null) 'message': message,
      if (data != null) 'data': data,
    };
  }

  /// Create a response from a map
  factory IsolateResponse.fromMap(Map<String, dynamic> map) {
    return IsolateResponse(
      uuid: map['uuid'] as String,
      ok: map['ok'] as bool,
      error: map['error'] as String?,
      message: map['message'] as String?,
      data: map['data'] as T?,
    );
  }
}

/// Helper class to emit events from within the isolate to the main thread
class IsolateEventEmitter {
  static SendPort? _sendPort;

  /// Internal method to set the send port (called from isolate entry point)
  static void _setSendPort(SendPort port) {
    _sendPort = port;
  }

  /// Emit an event from the isolate to the main thread
  static void emit(IsolateEvent event, dynamic data) {
    if (_sendPort == null) {
      Logger.warn('Cannot emit event ${event.name}: SendPort not initialized');
      return;
    }

    final eventMessage = IsolateEventMessage(type: event, data: data);
    _sendPort!.send(eventMessage.toMap());
  }
}

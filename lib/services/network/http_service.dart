import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/models/models.dart' show ServerDetails;
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/helpers/ui/ui_helpers.dart';
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/utils/file_utils.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/services/network/api/attachment_api.dart';
import 'package:bluebubbles/services/network/api/backup_api.dart';
import 'package:bluebubbles/services/network/api/base_api.dart';
import 'package:bluebubbles/services/network/api/chat_api.dart';
import 'package:bluebubbles/services/network/api/contact_api.dart';
import 'package:bluebubbles/services/network/api/facetime_api.dart';
import 'package:bluebubbles/services/network/api/fcm_api.dart';
import 'package:bluebubbles/services/network/api/icloud_api.dart';
import 'package:bluebubbles/services/network/api/firebase_api.dart';
import 'package:bluebubbles/services/network/api/handle_api.dart';
import 'package:bluebubbles/services/network/api/message_api.dart';
import 'package:bluebubbles/services/network/api/server_api.dart';
import 'package:bluebubbles/services/network/http_overrides.dart';
import 'package:bluebubbles/services/network/user_certificates.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:universal_io/io.dart';
import 'package:get_it/get_it.dart';

/// Get an instance of our [HttpService]
// ignore: non_constant_identifier_names
HttpService get HttpSvc => GetIt.I<HttpService>();


/// OpenBubbles: the [BackendService] implementation that talks to a classic
/// BlueBubbles server. Every method here is a thin adapter over the [HttpService]
/// sub-services; the rustpush-native implementation lives in
/// `services/rustpush/rustpush_service.dart` as `RustPushBackend`.
class HttpBackend implements BackendService {
  ServerDetails get _details => SettingsSvc.serverDetails;

  @override
  void init() {}

  @override
  HttpService? getRemoteService() => HttpSvc;

  // ── Chats ─────────────────────────────────────────────────────────────────

  @override
  Future<Chat> createChat(List<String> addresses, AttributedBody? message, String service,
      {CancelToken? cancelToken, String? existingGuid}) async {
    final response = await HttpSvc.chat.create(addresses, message?.string, service, cancelToken: cancelToken);
    return Chat.fromMap(response.data["data"]);
  }

  @override
  Future<bool> renameChat(Chat chat, String newName) async {
    return (await HttpSvc.chat.setDisplayName(chat.guid, newName)).statusCode == 200;
  }

  @override
  Future<bool> chatParticipant(ParticipantOp op, Chat chat, String address) async {
    final method = op == ParticipantOp.Add ? "add" : "remove";
    return (await HttpSvc.chat.modifyParticipant(method, chat.guid, address)).statusCode == 200;
  }

  @override
  Future<bool> leaveChat(Chat chat) async {
    return (await HttpSvc.chat.leave(chat.guid)).statusCode == 200;
  }

  /// The BlueBubbles server has no recycle bin — deletes are handled locally.
  @override
  Future<void> moveToRecycleBin(Chat c, Message? message) async {}

  @override
  Future<void> restoreChat(Chat c) async {}

  @override
  Future<void> permanentlyDeleteChat(Chat c) async {}

  @override
  bool canDelete() => false;

  @override
  bool canLeaveChat() => _details.supportsGroupChatManagement;

  @override
  bool canCreateGroupChats() => SettingsSvc.canCreateGroupChatSync();

  @override
  Future<bool> canUploadGroupPhotos() async => _details.isMinBigSur && _details.supportsGroupChatManagement;

  @override
  Future<bool> setChatIcon(Chat chat, String path,
      {void Function(int, int)? onSendProgress, CancelToken? cancelToken}) async {
    return (await HttpSvc.chat.setIcon(chat.guid, path, onSendProgress: onSendProgress, cancelToken: cancelToken))
            .statusCode ==
        200;
  }

  @override
  Future<bool> deleteChatIcon(Chat chat, {CancelToken? cancelToken}) async {
    return (await HttpSvc.chat.removeIcon(chat.guid, cancelToken: cancelToken)).statusCode == 200;
  }

  @override
  Future<bool> markRead(Chat chat, bool notifyOthers) async {
    return (await HttpSvc.chat.markRead(chat.guid)).statusCode == 200;
  }

  @override
  Future<bool> markUnread(Chat chat) async {
    return (await HttpSvc.chat.markUnread(chat.guid)).statusCode == 200;
  }

  // ── Sending ───────────────────────────────────────────────────────────────

  String _sendMethod(Message m, {required bool attachment}) {
    final papiToggle =
        attachment ? SettingsSvc.settings.privateAPIAttachmentSend.value : SettingsSvc.settings.privateAPISend.value;
    return (SettingsSvc.settings.enablePrivateAPI.value && papiToggle) ||
            (m.subject?.isNotEmpty ?? false) ||
            m.threadOriginatorGuid != null ||
            m.expressiveSendStyleId != null
        ? "private-api"
        : "apple-script";
  }

  int? _replyPartIndex(Message m) => int.tryParse(m.threadOriginatorPart?.split(":").firstOrNull ?? "");

  @override
  Future<Message> sendMessage(Chat c, Message m, {CancelToken? cancelToken}) async {
    if (m.attributedBody.isNotEmpty) {
      final body = m.attributedBody.first;
      final response = await HttpSvc.message.sendMultipart(
        c.guid,
        m.guid!,
        body.runs
            .map((e) => {
                  "text": body.string.substring(e.range.first, e.range.first + e.range.last),
                  "mention": e.attributes!.mention,
                  "partIndex": e.attributes!.messagePart,
                })
            .toList(),
        subject: m.subject,
        selectedMessageGuid: m.threadOriginatorGuid,
        effectId: m.expressiveSendStyleId,
        partIndex: _replyPartIndex(m),
        ddScan: !_details.isMinSonoma && (m.text?.hasUrl ?? false),
        cancelToken: cancelToken,
      );
      return Message.fromMap(response.data["data"]);
    }

    final response = await HttpSvc.message.sendText(
      c.guid,
      m.guid!,
      m.text!,
      subject: m.subject,
      method: _sendMethod(m, attachment: false),
      selectedMessageGuid: m.threadOriginatorGuid,
      effectId: m.expressiveSendStyleId,
      partIndex: _replyPartIndex(m),
      ddScan: !_details.isMinSonoma && m.text!.hasUrl,
      cancelToken: cancelToken,
    );
    return Message.fromMap(response.data["data"]);
  }

  @override
  Future<Message> sendAttachment(Chat c, Message m, bool isAudioMessage, Attachment attachment,
      {void Function(int, int)? onSendProgress, CancelToken? cancelToken}) async {
    final response = await HttpSvc.message.sendAttachment(
      c.guid,
      attachment.guid!,
      attachment.getFile(),
      onSendProgress: onSendProgress,
      method: _sendMethod(m, attachment: true),
      selectedMessageGuid: m.threadOriginatorGuid,
      effectId: m.expressiveSendStyleId,
      subject: m.subject,
      partIndex: _replyPartIndex(m),
      isAudioMessage: isAudioMessage,
      cancelToken: cancelToken,
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to upload attachment!");
    }
    return Message.fromMap(response.data['data']);
  }

  @override
  Future<Message> sendTapback(Chat chat, Message selected, String reaction, int? repPart) async {
    final response =
        await HttpSvc.message.sendTapback(chat.guid, selected.text ?? "", selected.guid!, reaction, partIndex: repPart);
    return Message.fromMap(response.data['data']);
  }

  @override
  Future<Message?> unsend(Message msg, MessagePart part) async {
    final response = await HttpSvc.message.unsend(msg.guid!, partIndex: part.part);
    if (response.statusCode != 200) return null;
    return Message.fromMap(response.data['data']);
  }

  @override
  Future<Message?> edit(Message msg, AttributedBody text, int part) async {
    final response = await HttpSvc.message.edit(msg.guid!, text.string, "Edited to: “${text.string}”", partIndex: part);
    if (response.statusCode != 200) return null;
    return Message.fromMap(response.data['data']);
  }

  /// The BlueBubbles server has no equivalent of rustpush's in-place message
  /// payload update (used for polls / handwriting / Digital Touch sessions).
  @override
  Future<Message> updateMessage(
      Chat chat, Message old, PayloadData newData, PlatformFile? newImage, bool isMeta, String? notifText) {
    throw Exception("The BlueBubbles server does not support updating messages!");
  }

  @override
  bool canEditUnsend() => _details.isMinVentura && _details.supportsEditAndUnsend;

  @override
  bool canSendSubject() => _details.supportsSubjectLines;

  @override
  bool canSchedule() => _details.supportsScheduledMessages;

  @override
  bool canCancelUploads() => true;

  // ── Attachments ───────────────────────────────────────────────────────────

  @override
  Future<PlatformFile> downloadAttachment(Attachment att,
      {void Function(int, int)? onReceiveProgress, bool original = false, CancelToken? cancelToken}) async {
    // On native platforms stream into a `.part` file and only move it into
    // place once it is complete, so readers never observe a partial file.
    // (AttachmentDownloadController treats file presence as "downloaded".)
    final String? savePath = kIsWeb ? null : att.path;
    final String? tempPath = savePath == null ? null : "$savePath.part";

    final response = await HttpSvc.attachment.download(
      att.guid!,
      onReceiveProgress: onReceiveProgress,
      original: original,
      cancelToken: cancelToken,
      savePath: tempPath,
    );
    if (response.statusCode != 200) {
      if (tempPath != null) {
        try {
          final temp = File(tempPath);
          if (await temp.exists()) await temp.delete();
        } catch (_) {}
      }
      throw Exception("Failed to download attachment ${att.guid}!");
    }

    att.webUrl = response.requestOptions.path;

    if (tempPath == null || savePath == null) {
      // Web: everything stays in memory.
      att.bytes = att.mimeType == "image/gif" ? await fixSpeedyGifs(response.data) : response.data;
      return att.getFile();
    }

    if (att.mimeType == "image/gif") {
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(await fixSpeedyGifs(await tempFile.readAsBytes()));
    }

    try {
      await moveFile(File(tempPath), savePath);
    } on PathNotFoundException {
      // A newer request for the same attachment already renamed its own copy in.
      if (!await File(savePath).exists()) rethrow;
    }

    return att.getFile();
  }

  @override
  Future<bool> downloadLivePhoto(Attachment att, String target,
      {void Function(int, int)? onReceiveProgress, CancelToken? cancelToken}) async {
    final response =
        await HttpSvc.attachment.downloadLivePhoto(att.guid!, onReceiveProgress: onReceiveProgress, cancelToken: cancelToken);
    if (response.statusCode != 200) return false;
    final file = PlatformFile(
      name: target,
      size: response.data.length,
      bytes: response.data,
    );
    await AttachmentsSvc.saveToDisk(file);
    return true;
  }

  // ── Typing indicators / presence ──────────────────────────────────────────

  @override
  void startedTyping(Chat c, [iMessageAppData? appdata]) {
    SocketSvc.sendMessage("started-typing", {"chatGuid": c.guid});
  }

  @override
  void stoppedTyping(Chat c) {
    SocketSvc.sendMessage("stopped-typing", {"chatGuid": c.guid});
  }

  @override
  void updateTypingStatus(Chat c) {
    SocketSvc.sendMessage("update-typing-status", {"chatGuid": c.guid});
  }

  @override
  bool supportsFocusStates() => _details.isMinMonterey;

  @override
  bool supportsFindMy() => _details.isMinCatalina;

  @override
  bool supportsSmsForwarding() => true;

  // ── Account ───────────────────────────────────────────────────────────────

  @override
  Future<bool> handleiMessageState(String address) async {
    final response = await HttpSvc.handle.handleiMessageState(address);
    return response.data["data"]["available"];
  }

  @override
  Future<Map<String, dynamic>> getAccountInfo() async {
    final result = await HttpSvc.icloud.getAccountInfo();
    if (result.data is Map && result.data['data'] != null) {
      return Map<String, dynamic>.from(result.data['data']);
    }
    return {};
  }

  @override
  Future<void> setDefaultHandle(String defaultHandle) async {
    await HttpSvc.icloud.setAccountAlias(defaultHandle);
  }

  @override
  Future<Map<String, dynamic>> getAccountContact() async {
    if (_details.isMinBigSur) {
      final result = await HttpSvc.icloud.getAccountContact();
      if (result.data is Map && result.data['data'] != null) {
        return Map<String, dynamic>.from(result.data['data']);
      }
    }
    return {};
  }
}

/// Class that manages foreground network requests from client to server, using
/// GET or POST requests.
class HttpService implements BaseApi {
  @override
  late Dio dio;
  String? originOverride;

  // ── Sub-services ────────────────────────────────────────────────────────────
  late ServerApi server;
  late FcmApi fcm;
  late AttachmentApi attachment;
  late ChatApi chat;
  late MessageApi message;
  late HandleApi handle;
  late ContactApi contact;
  late BackupApi backup;
  late FaceTimeApi faceTime;
  late iCloudApi icloud;
  late FirebaseApi firebase;

  /// Get the URL origin from the current server address
  @override
  String get origin =>
      originOverride ??
      (Uri.parse(SettingsSvc.settings.serverAddress.value).hasScheme
          ? Uri.parse(SettingsSvc.settings.serverAddress.value).origin
          : '');
  @override
  String get apiRoot => "$origin/api/v1";

  /// iOS font download status
  RxBool downloadingFont = false.obs;
  RxnDouble fontDownloadProgress = RxnDouble();
  RxnInt fontDownloadTotalSize = RxnInt();

  /// Helper function to build query params, this way we only need to add the
  /// required guid auth param in one place
  @override
  Map<String, dynamic> buildQueryParams([Map<String, dynamic> params = const {}]) {
    // we can't add items to a const map
    if (params.isEmpty) {
      params = {};
    }
    params['guid'] = SettingsSvc.settings.guidAuthKey.value;
    return params;
  }

  @override
  Future<Response> runApiGuarded(Future<Response> Function() func, {bool checkOrigin = true}) async {
    if (HttpSvc.origin.isEmpty && checkOrigin) {
      return Future.error("No server URL!");
    }
    try {
      return await func();
    } catch (e, s) {
      // try again if 502 error and Cloudflare.
      //
      // Both shapes have to be matched: JSON requests surface a `Response`
      // (ApiInterceptor resolves the failure into one), while binary requests
      // surface the raw `DioException` — checking only `Response` would silently
      // drop the retry for attachment downloads on a Cloudflare tunnel.
      final statusCode = e is Response
          ? e.statusCode
          : e is DioException
              ? e.response?.statusCode
              : null;
      if (statusCode == 502 && apiRoot.contains("trycloudflare")) {
        try {
          return await func();
        } catch (e, s) {
          return Future.error(e, s);
        }
      }
      return Future.error(e, s);
    }
  }

  /// Return the future with either a value or error, depending on response from API
  @override
  Future<Response> returnSuccessOrError(Response r) {
    if (r.statusCode == 200) {
      return Future.value(r);
    } else {
      return Future.error(r);
    }
  }

  @override
  Map<String, String> get headers {
    final extraHeaders = Map<String, String>.from(SettingsSvc.settings.customHeaders.value);
    if (SettingsSvc.settings.serverAddress.contains('ngrok')) {
      extraHeaders['ngrok-skip-browser-warning'] = 'true';
    } else if (SettingsSvc.settings.serverAddress.contains('zrok')) {
      extraHeaders['skip_zrok_interstitial'] = 'true';
    }

    return extraHeaders;
  }

  Future<void> init() async {
    dio = Dio(BaseOptions(
      connectTimeout: Duration(milliseconds: SettingsSvc.settings.apiTimeout.value),
      receiveTimeout: Duration(milliseconds: SettingsSvc.settings.apiTimeout.value),
      sendTimeout: Duration(milliseconds: SettingsSvc.settings.apiTimeout.value),
      headers: headers,
    ));
    // Use IOHttpClientAdapter with certificate validation so that:
    // 1. Self-signed server certs are accepted via shouldAcceptCertificate.
    // 2. Device-level user-installed certificates (Android) are trusted by
    //    loading them into the SecurityContext via UserCertificates.
    // NativeAdapter was removed because it bypasses Dart's HttpOverrides and
    // therefore the shouldAcceptCertificate callback, breaking self-signed cert support.
    if (!kIsWeb) {
      // Pre-fetch user cert context (async; Android only — null on other platforms).
      final SecurityContext? userCertContext = await UserCertificates().getContext();
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient(context: userCertContext);
          client.badCertificateCallback = shouldAcceptCertificate;
          return client;
        },
      );
    }
    dio.interceptors.add(ApiInterceptor());

    // Initialise sub-services after dio is ready.
    server = ServerApi(this);
    fcm = FcmApi(this);
    attachment = AttachmentApi(this);
    chat = ChatApi(this);
    message = MessageApi(this);
    handle = HandleApi(this);
    contact = ContactApi(this);
    backup = BackupApi(this);
    faceTime = FaceTimeApi(this);
    icloud = iCloudApi(this);
    firebase = FirebaseApi(this);

    // Uncomment to run tests on most API requests
    // testAPI();
  }

  void updateHeaders() {
    dio.options.headers = headers;
  }

  Future<Response> downloadFromUrl(String url, {Function(int, int)? progress, CancelToken? cancelToken}) async {
    return runApiGuarded(() async {
      final response = await dio.get(
        url,
        options: Options(
            responseType: ResponseType.bytes, receiveTimeout: dio.options.receiveTimeout! * 12, headers: headers),
        cancelToken: cancelToken,
        onReceiveProgress: progress,
      );
      return returnSuccessOrError(response);
    });
  }

  Future<void> downloadAppleEmojiFont() async {
    if (downloadingFont.value) return;

    final response = await downloadFromUrl(
        "https://github.com/BlueBubblesApp/bluebubbles-fonts/releases/latest/download/AppleColorEmoji.ttf",
        progress: (current, total) {
      if (current <= total) {
        downloadingFont.value = true;
        fontDownloadProgress.value = current / total;
        fontDownloadTotalSize.value = total;
      }
    }).catchError((error) {
      downloadingFont.value = false;
      fontDownloadProgress.value = null;
      fontDownloadTotalSize.value = null;

      return Response(requestOptions: RequestOptions(path: ''));
    });

    if (response.statusCode == 200) {
      try {
        final Uint8List data = response.data;
        final file = File(join(FilesystemSvc.fontPath, 'apple.ttf'));
        await file.create(recursive: true);
        await file.writeAsBytes(data);
        FilesystemSvc.fontExistsOnDisk.value = true;
        final fontLoader = FontLoader("Apple Color Emoji");
        final cachedFontBytes = ByteData.view(data.buffer);
        fontLoader.addFont(
          Future<ByteData>.value(cachedFontBytes),
        );
        await fontLoader.load();
        showSnackbar("Notice", "Font loaded");
      } catch (e, stack) {
        Logger.error("Failed to load font!", error: e, trace: stack);
        showSnackbar("Error", "Failed to load font! Error: ${e.toString()}");
      }
    }

    // Reset download state after all processing (HTTP download + file write) is complete.
    // This keeps downloadingFont = true during file write, preventing the user from
    // re-tapping the tile and starting a duplicate download.
    downloadingFont.value = false;
    fontDownloadProgress.value = null;
    fontDownloadTotalSize.value = null;
  }

  /// Test most API GET requests (the ones that don't have required parameters)
  void testAPI() {
    Stopwatch s = Stopwatch();
    group("API Service Test", () {
      test("Ping", () async {
        s.start();
        var res = await server.ping();
        expect(res.data['message'], "pong");
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Server Info", () async {
        s.start();
        var res = await server.info();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Server Stat Totals", () async {
        s.start();
        var res = await server.getTotalStats();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Server Stat Media", () async {
        s.start();
        var res = await server.getMediaStats();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Server Logs", () async {
        s.start();
        var res = await server.getLogs();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("FCM Client", () async {
        s.start();
        var res = await fcm.getServiceAccount();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Attachment Count", () async {
        s.start();
        var res = await attachment.getCount();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Chats", () async {
        s.start();
        var res = await chat.query();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Chat Count", () async {
        s.start();
        var res = await chat.getCount();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Message Count", () async {
        s.start();
        var res = await message.getCount();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("My Message Count", () async {
        s.start();
        var res = await message.getCount(onlyMe: true);
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Messages", () async {
        s.start();
        var res = await message.query();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Handle Count", () async {
        s.start();
        var res = await handle.handleCount();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("iCloud Contacts", () async {
        s.start();
        var res = await contact.fetchAll();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Theme Backup", () async {
        s.start();
        var res = await backup.getTheme();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Settings Backup", () async {
        s.start();
        var res = await backup.getSettings();
        expect(res.data['status'], 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
      test("Landing Page", () async {
        s.start();
        var res = await server.landingPage();
        expect(res.statusCode, 200);
        s.stop();
        Logger.info("Request took ${s.elapsedMilliseconds} ms");
      });
    });
  }
}

/// Intercepts API requests, responses, and errors and logs them to console
class ApiInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    Logger.info("Request: [${options.method}] ${options.path}", tag: "HTTP Service");
    return super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    Logger.info("Response: [${response.statusCode}] ${response.requestOptions.path}", tag: "HTTP Service");
    return super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Get params without sensitive info
    final params = err.requestOptions.queryParameters;
    params.remove("guid");
    params.remove("password");

    // Make a nice log of what failed
    Logger.error("""Failed Request: [${err.requestOptions.method}] ${err.requestOptions.path}
  -> Error: ${err.error ?? 'No Error'}
  -> Request Params: ${params.toString()}
  -> Request Data: ${err.requestOptions.data ?? 'No Data'}
  -> Response Status: ${err.response?.statusCode ?? 'No Response'}
  -> Response Data: ${err.response?.data ?? 'No Data'}""", tag: "HTTP Service");

    // The rewrites below synthesize the BlueBubbles server's JSON error
    // envelope, which only makes sense for a request that asked for JSON.
    //
    // Resolving a bytes/stream/plain request with a Map means dio's
    // `assureResponse` casts that Map to the caller's `T` and throws
    // `type '_Map<String, Object>' is not a subtype of type 'List<int>?'` --
    // burying the real network failure under a TypeError. That affects every
    // binary path: attachment downloads, embedded media, chat icons, URL
    // preview images, clipboard paste.
    //
    // Non-JSON requests get the untouched DioException instead, so callers see
    // what actually went wrong.
    if (err.requestOptions.responseType != ResponseType.json) {
      return super.onError(err, handler);
    }

    // `message` is what consumers actually read off these envelopes
    // (`data["error"]["message"]`, ~10 call sites). Emitting only `error` left
    // every one of them with null — and ChatsService.getMessages passes that
    // straight to completeError, which rejects null with
    // "type 'Null' is not a subtype of type 'Object'".
    if (err.response != null && err.response!.data is Map) return handler.resolve(err.response!);
    if (err.response != null) {
      final body = err.response!.data.toString();
      return handler.resolve(Response(data: {
        'status': err.response!.statusCode,
        'error': {
          'type': 'Error',
          'error': body,
          'message': body.isEmpty ? 'Server returned ${err.response!.statusCode}' : body,
        }
      }, requestOptions: err.requestOptions, statusCode: err.response!.statusCode));
    }
    if (err.type.name.contains("Timeout")) {
      return handler.resolve(Response(data: {
        'status': 500,
        'error': {
          'type': 'timeout',
          'error': 'Failed to receive response from server.',
          'message': 'Failed to receive response from server.',
        }
      }, requestOptions: err.requestOptions, statusCode: 500));
    }
    return super.onError(err, handler);
  }
}

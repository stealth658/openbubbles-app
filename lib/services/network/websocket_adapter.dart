import 'dart:io';
import 'package:bluebubbles/services/network/user_certificates.dart';
import 'package:socket_io_client/socket_io_client.dart';

class WebsocketAdapter implements HttpClientAdapter {
  @override
  Future<WebSocket?> connect(String uri, {Map<String, dynamic>? headers}) async {
    return WebSocket.connect(
      uri,
      headers: headers?.map((key, value) => MapEntry(key, value.toString())) ?? {},
      customClient: HttpClient(context: await UserCertificates().getContext()),
    );
  }
}
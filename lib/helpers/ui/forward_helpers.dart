import 'dart:io';
import 'dart:typed_data';

import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/services/ui/chat/send_data.dart';

/// One [SendData] per forwarded message, oldest first, each carrying that
/// message's text and its downloaded attachments, so a forward of three
/// messages arrives as three messages, the way the iPhone forwards.
Future<List<SendData>> forwardSendData(List<Message> messages) async {
  final sorted = [...messages]..sort((a, b) => Message.sort(a, b, descending: false));
  final out = <SendData>[];
  for (final m in sorted) {
    final attachments = <PlatformFile>[];
    final files = m.dbAttachments
        .where((e) => AttachmentsSvc.getContent(e, autoDownload: false) is PlatformFile)
        .map((e) => AttachmentsSvc.getContent(e, autoDownload: false) as PlatformFile);
    for (final a in files) {
      Uint8List? bytes = a.bytes;
      bytes ??= await File(a.path!).readAsBytes();
      attachments.add(PlatformFile(name: a.name, path: a.path, size: bytes.length, bytes: bytes));
    }
    final text = m.text ?? "";
    if (attachments.isEmpty && isNullOrEmpty(text)) continue;
    out.add(SendData(attachments: attachments, text: text, subject: ""));
  }
  return out;
}

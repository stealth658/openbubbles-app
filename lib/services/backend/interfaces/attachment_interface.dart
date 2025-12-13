import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/actions/attachment_actions.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';
import 'package:get_it/get_it.dart';

class AttachmentInterface {
  static Future<Map<String, dynamic>> saveAttachmentAsync({
    required Map<String, dynamic> attachmentData,
    Map<String, dynamic>? messageData,
  }) async {
    final data = {
      'attachmentData': attachmentData,
      'messageData': messageData,
    };

    if (isIsolate()) {
      return await AttachmentActions.saveAttachmentAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.saveAttachmentAsync, input: data);
    }
  }

  static Future<void> bulkSaveAttachmentsAsync({
    required Map<Map<String, dynamic>, List<Map<String, dynamic>>> mapData,
  }) async {
    final data = {
      'mapData': mapData,
    };

    if (isIsolate()) {
      return await AttachmentActions.bulkSaveAttachmentsAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.bulkSaveAttachmentsAsync, input: data);
    }
  }

  static Future<Map<String, dynamic>> replaceAttachmentAsync({
    required String oldGuid,
    required Map<String, dynamic> newAttachmentData,
  }) async {
    final data = {
      'oldGuid': oldGuid,
      'newAttachmentData': newAttachmentData,
    };

    if (isIsolate()) {
      return await AttachmentActions.replaceAttachmentAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.replaceAttachmentAsync, input: data);
    }
  }

  static Future<Map<String, dynamic>?> findOneAttachmentAsync({
    required String guid,
  }) async {
    final data = {
      'guid': guid,
    };

    if (isIsolate()) {
      return await AttachmentActions.findOneAttachmentAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>?>(IsolateRequestType.findOneAttachmentAsync, input: data);
    }
  }

  static Future<List<Map<String, dynamic>>> findAttachmentsAsync() async {
    if (isIsolate()) {
      return await AttachmentActions.findAttachmentsAsync({});
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.findAttachmentsAsync, input: {});
    }
  }

  static Future<void> deleteAttachmentAsync({
    required String guid,
  }) async {
    final data = {
      'guid': guid,
    };

    if (isIsolate()) {
      return await AttachmentActions.deleteAttachmentAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.deleteAttachmentAsync, input: data);
    }
  }
}

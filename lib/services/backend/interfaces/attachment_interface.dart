import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/actions/attachment_actions.dart';
import 'package:bluebubbles/services/backend/descriptors/attachment_query_descriptor.dart';
import 'package:bluebubbles/services/backend/hydration/attachment_hydration.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';
import 'package:get_it/get_it.dart';

class AttachmentInterface {
  static Future<Attachment> saveAttachmentAsync({
    required Map<String, dynamic> attachmentData,
    Map<String, dynamic>? messageData,
    bool hydrateMessage = true,
  }) async {
    final data = {
      'attachmentData': attachmentData,
      'messageData': messageData,
    };

    late Map<String, dynamic> attachmentMap;
    if (isIsolate) {
      attachmentMap = await AttachmentActions.saveAttachmentAsync(data);
    } else {
      attachmentMap = await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.saveAttachmentAsync, input: data);
    }
    
    final attachment = Attachment.fromMap(attachmentMap);
    if (hydrateMessage) {
      AttachmentHydration.hydrate(attachment);
    }
    return attachment;
  }

  static Future<void> bulkSaveAttachmentsAsync({
    required Map<Map<String, dynamic>, List<Map<String, dynamic>>> mapData,
  }) async {
    final data = {
      'mapData': mapData,
    };

    if (isIsolate) {
      return await AttachmentActions.bulkSaveAttachmentsAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.bulkSaveAttachmentsAsync, input: data);
    }
  }

  static Future<Attachment> replaceAttachmentAsync({
    required String oldGuid,
    required Map<String, dynamic> newAttachmentData,
    bool hydrateMessage = true,
  }) async {
    final data = {
      'oldGuid': oldGuid,
      'newAttachmentData': newAttachmentData,
    };

    late Map<String, dynamic> attachmentMap;
    if (isIsolate) {
      attachmentMap = await AttachmentActions.replaceAttachmentAsync(data);
    } else {
      attachmentMap = await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.replaceAttachmentAsync, input: data);
    }
    
    final attachment = Attachment.fromMap(attachmentMap);
    if (hydrateMessage) {
      AttachmentHydration.hydrate(attachment);
    }
    return attachment;
  }

  static Future<Attachment?> findOneAttachmentAsync({
    required String guid,
    bool hydrateMessage = true,
  }) async {
    final data = {
      'guid': guid,
    };

    late Map<String, dynamic>? attachmentMap;
    if (isIsolate) {
      attachmentMap = await AttachmentActions.findOneAttachmentAsync(data);
    } else {
      attachmentMap = await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>?>(IsolateRequestType.findOneAttachmentAsync, input: data);
    }
    
    if (attachmentMap == null) return null;
    
    final attachment = Attachment.fromMap(attachmentMap);
    if (hydrateMessage) {
      AttachmentHydration.hydrate(attachment);
    }
    return attachment;
  }

  static Future<List<Attachment>> findAttachmentsAsync({
    AttachmentQueryDescriptor? queryDescriptor,
    bool hydrateMessage = true,
  }) async {
    final data = {
      'queryDescriptor': queryDescriptor?.toMap(),
    };
    
    late List<Map<String, dynamic>> attachmentsData;
    if (isIsolate) {
      attachmentsData = await AttachmentActions.findAttachmentsAsync(data);
    } else {
      attachmentsData = await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.findAttachmentsAsync, input: data);
    }
    
    final attachments = attachmentsData.map((e) => Attachment.fromMap(e)).toList();
    if (hydrateMessage) {
      AttachmentHydration.hydrateAll(attachments);
    }
    return attachments;
  }

  static Future<void> deleteAttachmentAsync({
    required String guid,
  }) async {
    final data = {
      'guid': guid,
    };

    if (isIsolate) {
      return await AttachmentActions.deleteAttachmentAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<void>(IsolateRequestType.deleteAttachmentAsync, input: data);
    }
  }
}

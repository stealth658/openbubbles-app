import 'package:bluebubbles/services/backend/actions/app_actions.dart';
import 'package:bluebubbles/services/backend/actions/attachment_actions.dart';
import 'package:bluebubbles/services/backend/actions/chat_actions.dart';
import 'package:bluebubbles/services/backend/actions/contact_actions.dart';
import 'package:bluebubbles/services/backend/actions/contact_v2_actions.dart';
import 'package:bluebubbles/services/backend/actions/handle_actions.dart';
import 'package:bluebubbles/services/backend/actions/image_actions.dart';
import 'package:bluebubbles/services/backend/actions/message_actions.dart';
import 'package:bluebubbles/services/backend/actions/prefs_actions.dart';
import 'package:bluebubbles/services/backend/actions/server_actions.dart';
import 'package:bluebubbles/services/backend/actions/sync_actions.dart';
import 'package:bluebubbles/services/backend/actions/test_actions.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';

class IsolateActons {
  static final Map<IsolateRequestType, dynamic> actions = {
    // Testing
    IsolateRequestType.testReturnInput: TestActions.executeTestReturnInput,
    IsolateRequestType.testPrintInput: TestActions.executeTestPrintInput,
    IsolateRequestType.testThrowError: TestActions.executeTestThrowError,

    // App
    IsolateRequestType.checkForUpdate: AppActions.checkForUpdate,
    IsolateRequestType.getFcmData: AppActions.getFcmData,

    // Server
    IsolateRequestType.checkForServerUpdate: ServerActions.checkForServerUpdate,
    IsolateRequestType.getServerDetails: ServerActions.getServerDetails,

    // Image
    IsolateRequestType.convertImageToPng: ImageActions.convertToPng,

    // Prefs
    IsolateRequestType.saveReplyToMessageState: PrefsActions.saveReplyToMessageState,
    IsolateRequestType.loadReplyToMessageState: PrefsActions.loadReplyToMessageState,
    IsolateRequestType.syncAllSettings: PrefsActions.syncAllSettings,
    IsolateRequestType.syncSettings: PrefsActions.syncSettings,

    // Messages
    IsolateRequestType.getMessages: MessageActions.getMessages,
    IsolateRequestType.bulkSaveNewMessages: MessageActions.bulkSaveNewMessages,
    IsolateRequestType.bulkAddMessages: MessageActions.bulkAddMessages,
    IsolateRequestType.replaceMessage: MessageActions.replaceMessage,
    IsolateRequestType.fetchAttachmentsAsync: MessageActions.fetchAttachmentsAsync,
    IsolateRequestType.getChatAsync: MessageActions.getChatAsync,
    IsolateRequestType.deleteMessage: MessageActions.deleteMessage,
    IsolateRequestType.softDeleteMessage: MessageActions.softDeleteMessage,
    IsolateRequestType.fetchAssociatedMessagesAsync: MessageActions.fetchAssociatedMessagesAsync,
    IsolateRequestType.saveMessageAsync: MessageActions.saveMessageAsync,
    IsolateRequestType.findOneAsync: MessageActions.findOneAsync,
    IsolateRequestType.findAsync: MessageActions.findAsync,

    // Chat
    IsolateRequestType.clearNotificationForChat: ChatActions.clearNotificationForChat,
    IsolateRequestType.markChatReadUnread: ChatActions.markChatReadUnread,
    IsolateRequestType.saveChat: ChatActions.saveChat,
    IsolateRequestType.deleteChat: ChatActions.deleteChat,
    IsolateRequestType.softDeleteChat: ChatActions.softDeleteChat,
    IsolateRequestType.unDeleteChat: ChatActions.unDeleteChat,
    IsolateRequestType.addMessageToChat: ChatActions.addMessageToChat,
    IsolateRequestType.loadSupplementalData: ChatActions.loadSupplementalData,
    IsolateRequestType.syncLatestMessages: ChatActions.syncLatestMessages,
    IsolateRequestType.bulkSyncChats: ChatActions.bulkSyncChats,
    IsolateRequestType.getMessagesAsync: ChatActions.getMessagesAsync,
    IsolateRequestType.bulkSyncMessages: ChatActions.bulkSyncMessages,
    IsolateRequestType.getParticipantsAsync: ChatActions.getParticipantsAsync,
    IsolateRequestType.clearTranscriptAsync: ChatActions.clearTranscriptAsync,
    IsolateRequestType.getChatsAsync: ChatActions.getChatsAsync,

    // Handle
    IsolateRequestType.saveHandleAsync: HandleActions.saveHandleAsync,
    IsolateRequestType.bulkSaveHandlesAsync: HandleActions.bulkSaveHandlesAsync,
    IsolateRequestType.findOneHandleAsync: HandleActions.findOneHandleAsync,
    IsolateRequestType.findHandlesAsync: HandleActions.findHandlesAsync,

    // Contact
    IsolateRequestType.saveContactAsync: ContactActions.saveContactAsync,
    IsolateRequestType.findOneContactAsync: ContactActions.findOneContactAsync,

    // ContactV2 (new contact service)
    IsolateRequestType.fetchAndMatchContactsV2: ContactV2Actions.fetchAndMatchContacts,
    IsolateRequestType.checkContactChangesV2: ContactV2Actions.checkContactChanges,
    IsolateRequestType.getStoredContactIdsV2: ContactV2Actions.getStoredContactIds,
    IsolateRequestType.findOneContactV2: ContactV2Actions.findOneContactV2,
    IsolateRequestType.getContactsForHandlesV2: ContactV2Actions.getContactsForHandles,
    IsolateRequestType.refreshContactsV2: ContactV2Actions.refreshContacts,

    // Attachment
    IsolateRequestType.saveAttachmentAsync: AttachmentActions.saveAttachmentAsync,
    IsolateRequestType.bulkSaveAttachmentsAsync: AttachmentActions.bulkSaveAttachmentsAsync,
    IsolateRequestType.replaceAttachmentAsync: AttachmentActions.replaceAttachmentAsync,
    IsolateRequestType.findOneAttachmentAsync: AttachmentActions.findOneAttachmentAsync,
    IsolateRequestType.findAttachmentsAsync: AttachmentActions.findAttachmentsAsync,
    IsolateRequestType.deleteAttachmentAsync: AttachmentActions.deleteAttachmentAsync,

    // Sync
    IsolateRequestType.performIncrementalSync: SyncActions.performIncrementalSync,
    IsolateRequestType.uploadContacts: ContactActions.uploadContacts,
  };
}

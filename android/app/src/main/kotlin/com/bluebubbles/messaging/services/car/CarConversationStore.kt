package com.bluebubbles.messaging.services.car

import android.content.Context
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.services.backend_ui_interop.DartWorkManager
import com.bluebubbles.messaging.utils.PersistentLog
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.ToNumberPolicy
import java.io.File

/// One message as the car screen needs it. Mirrors the JSON written by the Dart
/// `GetCarConversations` handler (method_channel_handlers.dart).
data class CarMessageData(
    val guid: String,
    val text: String,
    val date: Long,
    val isFromMe: Boolean,
    val sender: String,
    val senderKey: String,
)

data class CarConversationData(
    val guid: String,
    val title: String,
    val isGroup: Boolean,
    val hasUnread: Boolean,
    val messages: List<CarMessageData>,
    val avatarPath: String? = null,
)

private data class Snapshot(
    val generatedAt: Long = 0,
    val conversations: List<CarConversationData> = emptyList(),
)

/// Process-wide cache of the conversation list shown on Android Auto.
///
/// The car screen is Kotlin and cannot read ObjectBox, so the source of truth is
/// a snapshot the Dart side writes on request ([refresh]). Between refreshes it is
/// kept current cheaply: every incoming-message notification and every reply sent
/// from a notification or the car passes through here ([recordIncoming],
/// [recordOutgoing], [markRead]). Nothing here is authoritative -- it exists only
/// so the car has something sensible to draw, and it is rebuilt from Dart on every
/// car session start.
object CarConversationStore {
    private const val FILE_NAME = "car_conversations.json"
    private const val MAX_CONVERSATIONS = 10
    private const val MAX_MESSAGES = 5

    private val gson: Gson = GsonBuilder().setObjectToNumberStrategy(ToNumberPolicy.LONG_OR_DOUBLE).create()

    @Volatile private var conversations: List<CarConversationData> = emptyList()
    @Volatile private var loaded = false
    private val listeners = mutableSetOf<() -> Unit>()

    fun snapshotFile(context: Context): File = File(context.cacheDir, FILE_NAME)
    fun avatarDir(context: Context): File = File(context.cacheDir, "car_avatars")

    private fun avatarFileFor(context: Context, chatGuid: String): File =
        File(avatarDir(context), chatGuid.replace(Regex("[^A-Za-z0-9._-]"), "_") + ".png")

    fun current(context: Context): List<CarConversationData> {
        if (!loaded) loadFromDisk(context)
        return conversations
    }

    fun addListener(l: () -> Unit) = synchronized(listeners) { listeners.add(l) }
    fun removeListener(l: () -> Unit) = synchronized(listeners) { listeners.remove(l) }

    private fun notifyChanged() {
        val copy = synchronized(listeners) { listeners.toList() }
        copy.forEach { l ->
            try { l() } catch (e: Exception) { /* a dead screen must not break the store */ }
        }
    }

    @Synchronized
    private fun loadFromDisk(context: Context) {
        loaded = true
        try {
            val f = snapshotFile(context)
            if (!f.exists()) return
            val snap = gson.fromJson(f.readText(Charsets.UTF_8), Snapshot::class.java) ?: return
            conversations = snap.conversations.take(MAX_CONVERSATIONS)
            PersistentLog.d(context, Constants.logTag, "CarConversationStore loaded ${conversations.size} conversations from disk")
        } catch (e: Exception) {
            PersistentLog.w(context, Constants.logTag, "CarConversationStore failed to read snapshot", e)
        }
    }

    /// Ask Dart for a fresh snapshot. Runs through DartWorkManager so it works whether
    /// or not the app UI is open (it boots a headless engine if needed). [onDone] is
    /// called on completion either way; the store may or may not have changed.
    fun refresh(context: Context, onDone: (() -> Unit)? = null) {
        val path = snapshotFile(context).absolutePath
        PersistentLog.d(context, Constants.logTag, "CarConversationStore requesting snapshot from Dart")
        DartWorkManager.createWorker(
            context,
            "GetCarConversations",
            hashMapOf(
                "outputPath" to path,
                "avatarDir" to avatarDir(context).absolutePath,
                "limit" to MAX_CONVERSATIONS,
                "messagesPerChat" to MAX_MESSAGES,
            ),
        ) { succeeded ->
            if (succeeded) {
                loaded = false
                loadFromDisk(context)
                notifyChanged()
            } else {
                PersistentLog.w(context, Constants.logTag, "CarConversationStore snapshot request failed; keeping cached list")
            }
            onDone?.invoke()
        }
    }

    /// Called from CreateIncomingMessageNotification for every message that gets a
    /// notification. Moves the chat to the top and appends the message.
    @Synchronized
    fun recordIncoming(
        context: Context,
        chatGuid: String,
        chatTitle: String,
        isGroup: Boolean,
        senderName: String,
        senderKey: String,
        messageGuid: String,
        text: String,
        dateMillis: Long,
        isFromMe: Boolean,
        chatIcon: ByteArray? = null,
    ) {
        if (!loaded) loadFromDisk(context)
        if (text.isBlank()) return
        // The notification path already has the rendered chat avatar; keep a copy so
        // the car list has a picture even before the next Dart snapshot.
        var avatarPath: String? = conversations.firstOrNull { it.guid == chatGuid }?.avatarPath
        if (chatIcon != null && chatIcon.isNotEmpty()) {
            try {
                val f = avatarFileFor(context, chatGuid)
                f.parentFile?.mkdirs()
                f.writeBytes(chatIcon)
                avatarPath = f.absolutePath
            } catch (e: Exception) {
                PersistentLog.w(context, Constants.logTag, "CarConversationStore failed to save avatar", e)
            }
        }
        val msg = CarMessageData(messageGuid, text, dateMillis, isFromMe, senderName, senderKey)
        val existing = conversations.firstOrNull { it.guid == chatGuid }
        val updated = if (existing != null) {
            if (existing.messages.any { it.guid == messageGuid }) return
            existing.copy(
                title = chatTitle.ifBlank { existing.title },
                isGroup = isGroup || existing.isGroup,
                hasUnread = existing.hasUnread || !isFromMe,
                messages = (existing.messages + msg).takeLast(MAX_MESSAGES),
                avatarPath = avatarPath ?: existing.avatarPath,
            )
        } else {
            CarConversationData(chatGuid, chatTitle, isGroup, !isFromMe, listOf(msg), avatarPath)
        }
        conversations = (listOf(updated) + conversations.filter { it.guid != chatGuid }).take(MAX_CONVERSATIONS)
        persist(context)
        notifyChanged()
    }

    /// A reply the user sent from the car or a notification. Echoed locally so the
    /// car screen shows it immediately; the next Dart snapshot replaces it with the
    /// real record.
    @Synchronized
    fun recordOutgoing(context: Context, chatGuid: String, text: String) {
        if (!loaded) loadFromDisk(context)
        val existing = conversations.firstOrNull { it.guid == chatGuid } ?: return
        val msg = CarMessageData("local-${System.currentTimeMillis()}", text, System.currentTimeMillis(), true, "You", "self")
        val updated = existing.copy(hasUnread = false, messages = (existing.messages + msg).takeLast(MAX_MESSAGES))
        conversations = (listOf(updated) + conversations.filter { it.guid != chatGuid }).take(MAX_CONVERSATIONS)
        persist(context)
        notifyChanged()
    }

    @Synchronized
    fun markRead(context: Context, chatGuid: String) {
        if (!loaded) loadFromDisk(context)
        val existing = conversations.firstOrNull { it.guid == chatGuid } ?: return
        if (!existing.hasUnread) return
        conversations = conversations.map { if (it.guid == chatGuid) it.copy(hasUnread = false) else it }
        persist(context)
        notifyChanged()
    }

    private fun persist(context: Context) {
        try {
            val f = snapshotFile(context)
            val tmp = File(f.parentFile, "$FILE_NAME.tmp")
            tmp.writeText(gson.toJson(Snapshot(System.currentTimeMillis(), conversations)), Charsets.UTF_8)
            if (!tmp.renameTo(f)) f.writeText(tmp.readText(Charsets.UTF_8), Charsets.UTF_8)
        } catch (e: Exception) {
            PersistentLog.w(context, Constants.logTag, "CarConversationStore failed to persist", e)
        }
    }
}

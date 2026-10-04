package com.bluebubbles.messaging.services.genai

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.models.MethodCallHandlerImpl
import com.bluebubbles.messaging.utils.PersistentLog
import com.google.common.util.concurrent.ListenableFuture
import com.google.mlkit.genai.common.DownloadCallback
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.java.GenerativeModelFutures
import com.google.mlkit.genai.proofreading.Proofreader
import com.google.mlkit.genai.proofreading.ProofreaderOptions
import com.google.mlkit.genai.proofreading.Proofreading
import com.google.mlkit.genai.proofreading.ProofreadingRequest
import com.google.mlkit.genai.rewriting.Rewriter
import com.google.mlkit.genai.rewriting.RewriterOptions
import com.google.mlkit.genai.rewriting.Rewriting
import com.google.mlkit.genai.rewriting.RewritingRequest
import com.google.mlkit.genai.summarization.Summarization
import com.google.mlkit.genai.summarization.SummarizationRequest
import com.google.mlkit.genai.summarization.Summarizer
import com.google.mlkit.genai.summarization.SummarizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors

/// On-device generative AI through ML Kit's GenAI APIs (Gemini Nano via the
/// AICore system service). Nothing here leaves the phone: no API key, no
/// network call for inference. Each feature downloads its own model on first
/// use, which the Dart side drives through the `status` / `download` ops so it
/// can show progress.
///
/// Single method-channel entry point (`genai`) dispatched on `op`:
///   status     -> {summarize, proofread, rewrite, prompt: available|downloadable|downloading|unavailable}
///   download   -> feature name; resolves when the model is on device
///   summarize  -> text, bullets (1..3) -> summary string
///   proofread  -> text -> corrected text
///   rewrite    -> text, style (elaborate|emojify|shorten|friendly|professional|rephrase) -> [suggestions]
///   prompt     -> prompt -> model text
///
/// Clients are cached per configuration; ML Kit's own guidance is to reuse
/// them. Everything completes back on the main thread because
/// MethodChannel.Result requires it.
class GenAiHandler : MethodCallHandlerImpl() {
    companion object {
        const val tag: String = "genai"

        private val main = Handler(Looper.getMainLooper())
        private val executor = Executors.newSingleThreadExecutor()

        private val summarizers = HashMap<Int, Summarizer>()
        private val rewriters = HashMap<Int, Rewriter>()
        @Volatile private var proofreader: Proofreader? = null
        @Volatile private var promptModel: GenerativeModelFutures? = null

        private fun summarizer(context: Context, bullets: Int): Summarizer = synchronized(summarizers) {
            val type = when (bullets.coerceIn(1, 3)) {
                1 -> SummarizerOptions.OutputType.ONE_BULLET
                2 -> SummarizerOptions.OutputType.TWO_BULLETS
                else -> SummarizerOptions.OutputType.THREE_BULLETS
            }
            summarizers.getOrPut(type) {
                Summarization.getClient(
                    SummarizerOptions.builder(context.applicationContext)
                        .setInputType(SummarizerOptions.InputType.CONVERSATION)
                        .setOutputType(type)
                        .setLanguage(SummarizerOptions.Language.ENGLISH)
                        .setLongInputAutoTruncationEnabled(true)
                        .build()
                )
            }
        }

        private fun rewriter(context: Context, style: String): Rewriter = synchronized(rewriters) {
            val type = when (style.lowercase()) {
                "elaborate" -> RewriterOptions.OutputType.ELABORATE
                "emojify" -> RewriterOptions.OutputType.EMOJIFY
                "shorten" -> RewriterOptions.OutputType.SHORTEN
                "friendly" -> RewriterOptions.OutputType.FRIENDLY
                "professional" -> RewriterOptions.OutputType.PROFESSIONAL
                else -> RewriterOptions.OutputType.REPHRASE
            }
            rewriters.getOrPut(type) {
                Rewriting.getClient(
                    RewriterOptions.builder(context.applicationContext)
                        .setOutputType(type)
                        .setLanguage(RewriterOptions.Language.ENGLISH)
                        .build()
                )
            }
        }

        private fun proofreader(context: Context): Proofreader = proofreader ?: synchronized(this) {
            proofreader ?: Proofreading.getClient(
                ProofreaderOptions.builder(context.applicationContext)
                    .setInputType(ProofreaderOptions.InputType.KEYBOARD)
                    .setLanguage(ProofreaderOptions.Language.ENGLISH)
                    .build()
            ).also { proofreader = it }
        }

        private fun prompt(): GenerativeModelFutures = promptModel ?: synchronized(this) {
            promptModel ?: GenerativeModelFutures.from(Generation.INSTANCE.getClient()).also { promptModel = it }
        }

        private fun statusName(code: Int): String = when (code) {
            FeatureStatus.AVAILABLE -> "available"
            FeatureStatus.DOWNLOADABLE -> "downloadable"
            FeatureStatus.DOWNLOADING -> "downloading"
            else -> "unavailable"
        }
    }

    override fun handleMethodCall(call: MethodCall, result: MethodChannel.Result, context: Context) {
        val op: String = call.argument("op") ?: run {
            result.error("BAD_ARGS", "genai: missing op", null); return
        }
        try {
            when (op) {
                "status" -> status(context, result)
                "download" -> download(context, call.argument("feature") ?: "", result)
                "summarize" -> {
                    val text: String = call.argument("text") ?: ""
                    val bullets: Int = call.argument("bullets") ?: 3
                    val fut = summarizer(context, bullets).runInference(SummarizationRequest.builder(text).build())
                    await(fut, result) { it.summary }
                }
                "proofread" -> {
                    val text: String = call.argument("text") ?: ""
                    val fut = proofreader(context).runInference(ProofreadingRequest.builder(text).build())
                    await(fut, result) { r -> r.results.firstOrNull()?.text ?: text }
                }
                "rewrite" -> {
                    val text: String = call.argument("text") ?: ""
                    val style: String = call.argument("style") ?: "rephrase"
                    val fut = rewriter(context, style).runInference(RewritingRequest.builder(text).build())
                    await(fut, result) { r -> r.results.map { it.text } }
                }
                "prompt" -> {
                    val p: String = call.argument("prompt") ?: ""
                    val fut = prompt().generateContent(p)
                    await(fut, result) { r -> r.candidates.firstOrNull()?.text ?: "" }
                }
                else -> result.error("BAD_ARGS", "genai: unknown op $op", null)
            }
        } catch (e: Throwable) {
            // A device without AICore throws from getClient() itself, before any
            // future exists. Surface it as a normal error rather than crashing.
            PersistentLog.w(context, Constants.logTag, "genai $op failed synchronously", e)
            result.error("GENAI", describe(e), null)
        }
    }

    private fun status(context: Context, result: MethodChannel.Result) {
        val out = HashMap<String, String>()
        val pending = java.util.concurrent.atomic.AtomicInteger(4)
        fun put(key: String, fut: ListenableFuture<Int>?) {
            if (fut == null) {
                out[key] = "unavailable"
                if (pending.decrementAndGet() == 0) main.post { result.success(out) }
                return
            }
            fut.addListener({
                out[key] = try { statusName(fut.get()) } catch (e: Throwable) { "unavailable" }
                if (pending.decrementAndGet() == 0) main.post { result.success(out) }
            }, executor)
        }
        put("summarize", runCatching { summarizer(context, 3).checkFeatureStatus() }.getOrNull())
        put("proofread", runCatching { proofreader(context).checkFeatureStatus() }.getOrNull())
        put("rewrite", runCatching { rewriter(context, "rephrase").checkFeatureStatus() }.getOrNull())
        put("prompt", runCatching { prompt().checkStatus() }.getOrNull())
    }

    private fun download(context: Context, feature: String, result: MethodChannel.Result) {
        val cb = object : DownloadCallback {
            override fun onDownloadStarted(bytesToDownload: Long) {
                PersistentLog.d(context, Constants.logTag, "genai: downloading $feature ($bytesToDownload bytes)")
            }
            override fun onDownloadFailed(e: GenAiException) {
                PersistentLog.w(context, Constants.logTag, "genai: download of $feature failed", e)
            }
            override fun onDownloadProgress(totalBytesDownloaded: Long) {}
            override fun onDownloadCompleted() {
                PersistentLog.d(context, Constants.logTag, "genai: $feature downloaded")
            }
        }
        val fut: ListenableFuture<Void> = when (feature) {
            "summarize" -> summarizer(context, 3).downloadFeature(cb)
            "proofread" -> proofreader(context).downloadFeature(cb)
            "rewrite" -> rewriter(context, "rephrase").downloadFeature(cb)
            "prompt" -> prompt().download(cb)
            else -> { result.error("BAD_ARGS", "genai: unknown feature $feature", null); return }
        }
        await(fut, result) { true }
    }

    /// Bridge a ListenableFuture to a MethodChannel result on the main thread.
    private fun <T, R> await(fut: ListenableFuture<T>, result: MethodChannel.Result, map: (T) -> R) {
        fut.addListener({
            val outcome = runCatching { map(fut.get()) }
            main.post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { e -> result.error("GENAI", describe(e), null) },
                )
            }
        }, executor)
    }

    private fun describe(e: Throwable): String {
        val cause = if (e is ExecutionException) e.cause ?: e else e
        return "${cause.javaClass.simpleName}: ${cause.message ?: ""}"
    }
}

package kz.yerek.aireply.keyboard.reply

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kz.yerek.aireply.ai.AIReplyError
import kz.yerek.aireply.ai.AIReplyException
import kz.yerek.aireply.ai.AIReplyService
import kz.yerek.aireply.ai.ReplyDraftNormalizer
import kz.yerek.aireply.core.lang.AppLanguage
import kz.yerek.aireply.domain.model.ReplyConfiguration
import kz.yerek.aireply.domain.model.ReplyTemplate
import kz.yerek.aireply.keyboard.input.KeyboardTextFieldState
import kz.yerek.aireply.keyboard.input.ReplyContext
import kz.yerek.aireply.platform.ReplyLog

/**
 * Drives the copy → template → instruction → AI → draft → insert flow.
 *
 * GENERATION IS NEVER AUTOMATIC. Copying text does not start a request; opening
 * the keyboard does not start a request; the keyboard reappearing does not start
 * a request. Exactly two things do: the user tapping Generate, or tapping
 * Regenerate. That is what keeps token cost, accidental clipboard content and
 * privacy all under the user's control at once.
 *
 * PRIVACY. The source message, the instruction and the draft live only in this
 * object and in the views reading it, only while the panel is open. Nothing is
 * written to disk, to preferences or to a log at any point — [clear] drops all
 * three and cancels anything in flight.
 */
class ReplyFlowController(
    private val scope: CoroutineScope,
    private val service: AIReplyService,
    private val normalizer: ReplyDraftNormalizer
) {

    /** What the user copied. Read-only, and never seeded into [draft]. */
    var sourceMessage: String by mutableStateOf("")
        private set

    /** What the user wants this reply to do. Typed or dictated. */
    val instruction = KeyboardTextFieldState()

    /**
     * The model's answer, which becomes the user's the moment it appears. The
     * only value that can reach the host application.
     */
    val draft = KeyboardTextFieldState()

    var stage: ReplyStage by mutableStateOf(ReplyStage.IDLE)
        private set

    var template: ReplyTemplate? by mutableStateOf(null)
        private set

    /** Short-lived status line. Never changes the keyboard's geometry. */
    var toast: String? by mutableStateOf(null)
        private set

    /** Configuration snapshot taken when the keyboard appeared. */
    var configuration: ReplyConfiguration = ReplyConfiguration.INITIAL

    /**
     * The APP's language. Names the template in the prompt the way the user saw
     * it on the chip, and selects the error sentences. The LAYOUT is
     * deliberately absent: what the user is typing on has no bearing on the
     * reply, whose language follows the incoming message.
     */
    var uiLanguage: AppLanguage = AppLanguage.ENGLISH

    /** Rendered from an [AIReplyError] by the caller, which owns the strings. */
    var describeError: (AIReplyError) -> String = { "" }

    private var job: Job? = null

    val isGenerating: Boolean get() = stage == ReplyStage.GENERATING

    // ----------------------------------------------------------- entry points

    /** The user tapped a template chip and the message was acquired. */
    fun begin(context: ReplyContext, template: ReplyTemplate) {
        cancelJob()
        this.template = template
        sourceMessage = context.text
        instruction.clear()
        draft.clear()
        toast = null
        stage = ReplyStage.READY
        ReplyLog.event { "compose opened, source ${context.source}, length ${context.text.length}" }
    }

    /** Swap the template without losing the message or the instruction. */
    fun retarget(template: ReplyTemplate) {
        if (!stage.isComposing) return
        this.template = template
    }

    fun generate() {
        if (stage != ReplyStage.READY && stage != ReplyStage.RESULT) return
        start()
    }

    /** Regenerate: SAME message, SAME template, SAME instruction, new answer. */
    fun regenerate() {
        if (stage != ReplyStage.RESULT) return
        start()
    }

    private fun start() {
        // A second tap while a request is in flight is ignored rather than
        // queued, so an impatient double tap cannot spend twice.
        if (job != null) return
        val template = template ?: return

        stage = ReplyStage.GENERATING

        job = scope.launch {
            val request = AIReplyService.Request(
                message = sourceMessage,
                template = template,
                configuration = configuration,
                uiLanguage = uiLanguage,
                instruction = instruction.text
            )
            try {
                val reply = service.generate(request)
                job = null
                // The panel can have been closed while the request was in
                // flight. Dropping the answer is correct; there is nothing left
                // to put it in.
                if (stage != ReplyStage.GENERATING) return@launch
                draft.set(reply.text)
                stage = ReplyStage.RESULT
                ReplyLog.event { "draft received, length ${reply.text.length}" }
            } catch (exception: AIReplyException) {
                job = null
                fail(exception.error)
            } catch (throwable: Throwable) {
                job = null
                if (throwable is kotlinx.coroutines.CancellationException) throw throwable
                fail(AIReplyError.ServiceUnavailable)
            }
        }
    }

    private fun fail(error: AIReplyError) {
        if (error == AIReplyError.Cancelled) return
        ReplyLog.event { "generation failed: $error" }

        // A regeneration that fails must not throw the user's existing draft
        // away — it is the only copy of an answer they may already have edited.
        if (!draft.isBlank) {
            stage = ReplyStage.RESULT
            showToast(describeError(error))
            return
        }
        stage = if (sourceMessage.isNotEmpty()) ReplyStage.READY else ReplyStage.IDLE
        showToast(describeError(error))
    }

    // ----------------------------------------------------------------- insert

    /**
     * The text to hand to the host application, or null when the draft is blank.
     * Never returns the source message.
     */
    fun draftForInsertion(): String? {
        val raw = draft.text.trim()
        if (raw.isEmpty()) return null
        val normalized = normalizer.normalize(draft.text)
        if (normalized.isBlank()) return null
        ReplyLog.event { "insert accepted, length ${normalized.length}" }
        return normalized
    }

    fun awaitConflictChoice() {
        stage = ReplyStage.CONFLICT
    }

    /** Back to the draft with everything intact. Nothing was touched. */
    fun cancelConflict() {
        stage = ReplyStage.RESULT
    }

    // --------------------------------------------------------------- messages

    fun showToast(message: String) {
        if (message.isEmpty()) return
        toast = message
    }

    fun clearToast() {
        toast = null
    }

    // --------------------------------------------------------------- teardown

    /** Cancels any request and drops every trace of the message. */
    fun clear() {
        cancelJob()
        stage = ReplyStage.IDLE
        template = null
        sourceMessage = ""
        instruction.clear()
        draft.clear()
        toast = null
    }

    private fun cancelJob() {
        job?.cancel()
        job = null
    }
}

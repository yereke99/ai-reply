package kz.yerek.aireply.keyboard

import android.content.Intent
import android.content.res.Configuration
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kz.yerek.aireply.AIReplyApplication
import kz.yerek.aireply.MainActivity
import kz.yerek.aireply.R
import kz.yerek.aireply.ServiceLocator
import kz.yerek.aireply.ai.AIReplyError
import kz.yerek.aireply.ai.AIReplyService
import kz.yerek.aireply.core.lang.AppLanguage
import kz.yerek.aireply.core.lang.KeyboardLanguage
import kz.yerek.aireply.core.lang.KeyboardPlane
import kz.yerek.aireply.core.lang.TemplateNaming
import kz.yerek.aireply.data.settings.AppearancePreference
import kz.yerek.aireply.domain.model.ReplyConfiguration
import kz.yerek.aireply.domain.model.TemplateSummary
import kz.yerek.aireply.keyboard.input.ContextTextProvider
import kz.yerek.aireply.keyboard.input.HostField
import kz.yerek.aireply.keyboard.input.KeyboardStatus
import kz.yerek.aireply.keyboard.input.KeyboardTextFieldState
import kz.yerek.aireply.keyboard.reply.ReplyFlowController
import kz.yerek.aireply.keyboard.reply.ReplyStage
import kz.yerek.aireply.keyboard.ui.ConflictChoice
import kz.yerek.aireply.keyboard.ui.KeyGridLabels
import kz.yerek.aireply.keyboard.ui.KeyGridState
import kz.yerek.aireply.keyboard.ui.KeyboardRoot
import kz.yerek.aireply.keyboard.ui.PanelFocus
import kz.yerek.aireply.keyboard.ui.ReplyPanelActions
import kz.yerek.aireply.keyboard.ui.ReplyPanelModel
import kz.yerek.aireply.platform.ReplyLog
import kz.yerek.aireply.ui.design.AIReplyTheme
import kz.yerek.aireply.voice.AndroidSpeechRecognitionClient
import kz.yerek.aireply.voice.MicPermission
import kz.yerek.aireply.voice.SpeechRecognitionClient
import kz.yerek.aireply.voice.VoiceState

/**
 * The AI Reply keyboard.
 *
 * WHAT IT PROMISES, and what every decision below is in service of:
 *
 *  * Typing never waits for anything. No disk read, no network call and no
 *    JSON parse happens on a key press, and the AI panel's state is held apart
 *    from the key grid's so a generation in flight cannot recompose a single key.
 *  * A request is only ever started by the user tapping Generate or Regenerate.
 *    Appearing, reappearing, copying and typing all start nothing.
 *  * The clipboard is read in exactly one place, only when a template is tapped.
 *  * Nothing the user copied, dictated or drafted outlives the panel being
 *    closed, and none of it is ever written anywhere.
 *  * The messenger's own Send button stays under the user's finger. This service
 *    inserts text and does nothing else; there is no accessibility path here.
 */
class ReplyKeyboardService : InputMethodService() {

    private lateinit var services: ServiceLocator
    private lateinit var viewHost: KeyboardViewHost
    private lateinit var hostField: HostField
    private lateinit var feedback: KeyFeedback
    private lateinit var replyFlow: ReplyFlowController

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val contextProvider = ContextTextProvider()

    private var speech: SpeechRecognitionClient? = null
    private var voiceJob: Job? = null
    private var permissionJob: Job? = null
    private var toastJob: Job? = null

    private var inputView: ComposeView? = null

    // ------------------------------------------------------------------ state
    // Held as Compose state so the composition reads them directly. Everything
    // here is small and changes rarely; nothing in this block changes per
    // keystroke except shift.

    private var layout by mutableStateOf(KeyboardLanguage.ENGLISH)
    private var plane by mutableStateOf(KeyboardPlane.LETTERS)
    private var isShifted by mutableStateOf(false)
    private var isCapsLocked by mutableStateOf(false)
    private var uiLanguage by mutableStateOf(AppLanguage.ENGLISH)
    private var appearance by mutableStateOf(AppearancePreference.SYSTEM)
    private var chips by mutableStateOf<List<TemplateSummary>>(emptyList())
    private var focus by mutableStateOf(PanelFocus.INSTRUCTION)
    private var sourceExpanded by mutableStateOf(false)
    private var voiceState by mutableStateOf<VoiceState>(VoiceState.Idle)
    private var showsGlobeKey by mutableStateOf(false)
    private var isSecureField by mutableStateOf(false)
    private var editorAction by mutableStateOf(EditorInfo.IME_ACTION_NONE)
    private var isMultiline by mutableStateOf(false)

    private var configurationLoadedAt = 0L
    private var lastShiftTap = 0L
    private var lastSpaceTap = 0L
    private var pendingInsertion: String? = null

    // -------------------------------------------------------------- lifecycle

    override fun onCreate() {
        super.onCreate()
        services = AIReplyApplication.services(this)
        viewHost = KeyboardViewHost(this)
        viewHost.onCreate()
        hostField = HostField { currentInputConnection }
        feedback = KeyFeedback(this)
        replyFlow = ReplyFlowController(scope, services.replyService, services.draftNormalizer)

        layout = services.settings.keyboardLanguage
        uiLanguage = services.settings.effectiveAppLanguage
        appearance = services.settings.appearance
        chips = cachedChips()

        replyFlow.uiLanguage = uiLanguage
        replyFlow.describeError = { error -> services.strings(uiLanguage).message(error) }
        replyFlow.configuration = ReplyConfiguration.INITIAL
    }

    /**
     * Built once and reused.
     *
     * `onCreateInputView` is called again after a configuration change, but not
     * every time the keyboard is shown. Returning the same view across
     * appearances is what keeps switching to this keyboard cheap: the
     * composition is already built, so the second appearance is a layout pass
     * rather than a full construction.
     */
    override fun onCreateInputView(): View {
        inputView?.let { existing ->
            (existing.parent as? android.view.ViewGroup)?.removeView(existing)
            return existing
        }

        val view = ComposeView(this).apply {
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
            setContent { KeyboardContent() }
        }
        viewHost.attachTo(view)
        // Compose also looks the owners up from the window's decor view when it
        // needs one, which an IME window does not populate on its own.
        window?.window?.decorView?.let { viewHost.attachTo(it) }

        inputView = view
        return view
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)

        hostField.editorInfo = info
        isSecureField = hostField.isSecureField
        editorAction = (info?.imeOptions ?: 0) and EditorInfo.IME_MASK_ACTION
        isMultiline = ((info?.inputType ?: 0) and
            android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE) != 0

        refreshLanguages()
        refreshGlobeKey()
        loadConfigurationIfNeeded()

        plane = KeyboardPlane.LETTERS
        isCapsLocked = false
        isShifted = false
        refreshAutoShift()

        viewHost.onShown()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        super.onFinishInputView(finishingInput)
        viewHost.onHidden()

        // The keyboard is going away. Cancel anything in flight and drop the
        // copied message, the instruction and the draft with it — there is
        // nothing left to show them in, and holding private text past the moment
        // it is useful is exactly what this app promises not to do.
        if (replyFlow.stage.isComposing || replyFlow.isGenerating) {
            replyFlow.clear()
            pendingInsertion = null
        }

        // Release the microphone rather than waiting for onDestroy: an input
        // method can live for hours, and holding the mic across every app the
        // user visits would be indefensible.
        releaseSpeech()
    }

    override fun onDestroy() {
        releaseSpeech()
        toastJob?.cancel()
        permissionJob?.cancel()
        replyFlow.clear()
        viewHost.onDestroy()
        scope.cancel()
        inputView = null
        super.onDestroy()
    }

    /**
     * Never take over the whole screen in landscape.
     *
     * The default extract-text mode replaces the host app with a full-screen
     * editor, which would hide the very conversation the user is replying to.
     */
    override fun onEvaluateFullscreenMode(): Boolean = false

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Metrics are derived inside the composition from LocalConfiguration, so
        // rotation needs nothing here beyond letting Compose see it.
    }

    // ------------------------------------------------------------ composition

    @androidx.compose.runtime.Composable
    private fun KeyboardContent() {
        val configuration = LocalConfiguration.current

        val theme = KeyboardTheme.resolve(
            systemIsDark = (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES,
            override = when (appearance) {
                AppearancePreference.SYSTEM -> null
                AppearancePreference.LIGHT -> false
                AppearancePreference.DARK -> true
            }
        )

        val contentRowCount = if (plane == KeyboardPlane.LETTERS) {
            layout.letterRows.size
        } else {
            plane.rows.size
        }

        val metrics = KeyboardMetrics(
            width = configuration.screenWidthDp.dp,
            contentRowCount = contentRowCount,
            availableHeight = configuration.screenHeightDp.dp
        )

        val keyboardStrings = remember(layout) { services.localized(layout) }
        val productStrings = remember(uiLanguage) { services.strings(uiLanguage) }

        // Identity matters here. A method reference or a freshly built actions
        // object would be a new instance on every recomposition, so the key grid
        // would never be able to skip — which is the one thing this whole
        // layout is arranged to let it do.
        val keyHandler = remember { { key: KeyboardKey -> onKey(key) } }
        val globeLongPress = remember { { showKeyboardPicker() } }
        val actions = remember { panelActions() }

        val gridState = KeyGridState(
            language = layout,
            plane = plane,
            isShifted = isShifted,
            isCapsLocked = isCapsLocked,
            showsGlobeKey = showsGlobeKey,
            layoutBadge = keyboardStrings.getString(R.string.key_language_badge),
            spaceLabel = keyboardStrings.getString(R.string.key_space),
            returnLabel = keyboardStrings.getString(returnLabelResource()),
            returnIsProminent = returnKeyIsProminent()
        )

        val gridLabels = remember(uiLanguage) {
            KeyGridLabels(
                shift = productStrings[R.string.cd_shift],
                backspace = productStrings[R.string.cd_backspace],
                switchKeyboard = productStrings[R.string.cd_switch_keyboard],
                switchLayout = productStrings[R.string.cd_switch_layout]
            )
        }

        val panelModel = ReplyPanelModel(
            stage = replyFlow.stage,
            chips = chips,
            chipLanguageCode = uiLanguage.code,
            selectedTemplateName = selectedTemplateName(),
            sourceMessage = replyFlow.sourceMessage,
            instruction = replyFlow.instruction,
            draft = replyFlow.draft,
            focus = focus,
            toast = replyFlow.toast,
            voice = voiceState,
            isSecureField = isSecureField,
            sourceExpanded = sourceExpanded
        )

        AIReplyTheme(appearance = appearance) {
            KeyboardRoot(
                gridState = gridState,
                gridLabels = gridLabels,
                panelModel = panelModel,
                panelActions = actions,
                strings = productStrings,
                theme = theme,
                metrics = metrics,
                onKey = keyHandler,
                onGlobeLongPress = globeLongPress,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }

    private fun panelActions() = ReplyPanelActions(
        onSelectTemplate = ::startReply,
        onAddTemplate = ::openTemplateEditor,
        onClose = ::closeComposer,
        onGenerate = { replyFlow.generate() },
        onRegenerate = { replyFlow.regenerate() },
        onInsert = ::insertDraft,
        onFocus = { focus = it },
        onCaret = { target, offset -> fieldFor(target).moveCursor(offset) },
        onToggleSource = { sourceExpanded = !sourceExpanded },
        onMic = ::toggleMicrophone,
        onConflict = ::resolveConflict
    )

    // -------------------------------------------------------------- key input

    /**
     * Where a keystroke goes. The keyboard has exactly three possible
     * destinations and never guesses between them: the host application's
     * field, one of the panel's own fields, or nowhere.
     */
    private enum class InputTarget { HOST, LOCAL, DISCARDED }

    private val inputTarget: InputTarget
        get() = when {
            !replyFlow.stage.isComposing -> InputTarget.HOST
            replyFlow.stage.acceptsLocalInput -> InputTarget.LOCAL
            // While a request is in flight, keys are dropped rather than leaking
            // into WhatsApp behind the spinner.
            else -> InputTarget.DISCARDED
        }

    private fun fieldFor(target: PanelFocus): KeyboardTextFieldState =
        if (target == PanelFocus.DRAFT) replyFlow.draft else replyFlow.instruction

    private val activeLocalField: KeyboardTextFieldState
        get() = fieldFor(if (replyFlow.stage == ReplyStage.RESULT) PanelFocus.DRAFT else focus)

    private fun onKey(key: KeyboardKey) {
        feedback.onKeyPress(inputView)
        when (key) {
            is KeyboardKey.Character ->
                insertCharacter(if (plane == KeyboardPlane.LETTERS) displayed(key.value) else key.value)
            KeyboardKey.Shift -> toggleShift()
            KeyboardKey.Backspace -> deleteBackward()
            KeyboardKey.Space -> insertSpace()
            KeyboardKey.Return -> pressReturn()
            is KeyboardKey.Plane -> {
                plane = key.target
                isShifted = false
                isCapsLocked = false
                refreshAutoShift()
            }
            KeyboardKey.Layout -> cycleLayout()
            KeyboardKey.Globe -> switchToNextKeyboard()
        }
    }

    private fun displayed(value: String): String =
        if (isShifted || isCapsLocked) value.uppercase() else value

    private fun insert(text: String) {
        when (inputTarget) {
            InputTarget.HOST -> hostField.commitText(text)
            InputTarget.LOCAL -> activeLocalField.insert(text)
            InputTarget.DISCARDED -> Unit
        }
    }

    private fun deleteBackward() {
        when (inputTarget) {
            InputTarget.HOST -> hostField.deleteBackward()
            InputTarget.LOCAL -> activeLocalField.deleteBackward()
            InputTarget.DISCARDED -> Unit
        }
        refreshAutoShift()
    }

    private fun insertCharacter(value: String) {
        insert(value)
        // Shift is released once, here, at insertion time — so a caps lock is
        // never cancelled and a manual shift is never fought.
        if (plane == KeyboardPlane.LETTERS && isShifted && !isCapsLocked) {
            isShifted = false
        }
        refreshAutoShift()
    }

    private fun insertSpace() {
        val now = SystemClock.uptimeMillis()
        val before = textBeforeCursor()
        val doubleTap = now - lastSpaceTap < DOUBLE_TAP_MS
        val previous = before.dropLast(1).lastOrNull()

        if (doubleTap && before.endsWith(" ") && previous != null && previous.isLetterOrDigit()) {
            // ". " — the system keyboard's behaviour, and the one thing users
            // notice immediately when a third-party keyboard lacks it.
            when (inputTarget) {
                InputTarget.HOST -> hostField.deleteBackward()
                InputTarget.LOCAL -> activeLocalField.deleteBackward()
                InputTarget.DISCARDED -> Unit
            }
            insert(". ")
            lastSpaceTap = 0
        } else {
            insert(" ")
            lastSpaceTap = now
        }
        refreshAutoShift()
    }

    private fun pressReturn() {
        when (inputTarget) {
            // Inside the panel a return is a newline in a local field; it must
            // never reach the host's Send action while a draft is open.
            InputTarget.LOCAL -> activeLocalField.insert("\n")
            InputTarget.HOST -> hostField.sendReturn()
            InputTarget.DISCARDED -> Unit
        }
        refreshAutoShift()
    }

    private fun toggleShift() {
        val now = SystemClock.uptimeMillis()
        when {
            now - lastShiftTap < DOUBLE_TAP_MS -> {
                isCapsLocked = true
                isShifted = true
            }
            isCapsLocked -> {
                isCapsLocked = false
                isShifted = false
            }
            else -> isShifted = !isShifted
        }
        lastShiftTap = now
    }

    private fun cycleLayout() {
        layout = layout.next
        plane = KeyboardPlane.LETTERS
        isShifted = false
        isCapsLocked = false
        // Off the main thread: nothing in this frame reads it back, and it only
        // matters to the next launch.
        scope.launch(Dispatchers.IO) { services.settings.keyboardLanguage = layout }
        refreshAutoShift()
    }

    private fun textBeforeCursor(): String = when (inputTarget) {
        InputTarget.HOST -> hostField.textBeforeCursor()
        InputTarget.LOCAL -> activeLocalField.textBeforeCursor()
        InputTarget.DISCARDED -> ""
    }

    private fun refreshAutoShift() {
        if (plane != KeyboardPlane.LETTERS || isCapsLocked || isShifted) return
        if (inputTarget == InputTarget.HOST && !hostField.capitalizesSentences) return
        if (!AutoShift.isAtSentenceStart(textBeforeCursor())) return
        isShifted = true
    }

    // ----------------------------------------------------------- keyboard bar

    private fun returnLabelResource(): Int = when {
        replyFlow.stage.acceptsLocalInput -> R.string.key_return
        isMultiline -> R.string.key_return
        editorAction == EditorInfo.IME_ACTION_SEND -> R.string.key_send
        editorAction == EditorInfo.IME_ACTION_SEARCH -> R.string.key_search
        editorAction == EditorInfo.IME_ACTION_GO -> R.string.key_go
        editorAction == EditorInfo.IME_ACTION_DONE -> R.string.key_done
        else -> R.string.key_return
    }

    private fun returnKeyIsProminent(): Boolean {
        if (replyFlow.stage.acceptsLocalInput || isMultiline) return false
        return editorAction == EditorInfo.IME_ACTION_SEND ||
            editorAction == EditorInfo.IME_ACTION_SEARCH ||
            editorAction == EditorInfo.IME_ACTION_GO ||
            editorAction == EditorInfo.IME_ACTION_DONE
    }

    // -------------------------------------------------------------- reply flow

    /**
     * THE one place a network request can begin its life. Nothing else in this
     * file acquires a message, and nothing starts a request without the user
     * having tapped a chip and then Generate.
     */
    private fun startReply(templateId: String) {
        val template = resolveTemplate(templateId) ?: return

        if (replyFlow.stage.isComposing) {
            replyFlow.retarget(template)
            return
        }

        when (val result = contextProvider.acquire(this, currentInputConnection, isSecureField)) {
            is ContextTextProvider.Result.Failure -> showToast(result.error)

            is ContextTextProvider.Result.Success -> {
                // The 300-character rule is enforced BEFORE anything else, so an
                // over-long paste costs nothing and reports immediately.
                when (val validation = AIReplyService.validate(result.context.text)) {
                    is AIReplyService.ValidationResult.Invalid ->
                        showToast(validation.error)
                    is AIReplyService.ValidationResult.Valid -> {
                        sourceExpanded = false
                        focus = PanelFocus.INSTRUCTION
                        replyFlow.begin(result.context.copy(text = validation.message), template)
                    }
                }
            }
        }
    }

    /**
     * Turns a chip's identifier into the full template the request needs.
     *
     * Normally an in-memory lookup: the configuration was loaded when the
     * keyboard appeared. The fallback covers the narrow race where a user taps a
     * chip in the milliseconds before that load returns — one file read, on a
     * tap, never on a keystroke.
     */
    private fun resolveTemplate(id: String) =
        replyFlow.configuration.template(id) ?: run {
            val loaded = services.configuration.current
            replyFlow.configuration = loaded
            loaded.template(id)
        }

    private fun selectedTemplateName(): String {
        val template = replyFlow.template ?: return ""
        return TemplateNaming.displayName(
            services.localized(uiLanguage),
            template
        )
    }

    private fun closeComposer() {
        replyFlow.clear()
        pendingInsertion = null
        sourceExpanded = false
        focus = PanelFocus.INSTRUCTION
        cancelSpeech()
    }

    /**
     * The one place the reply draft reaches the host application.
     *
     * The source message is never what gets inserted, and nothing is ever sent:
     * the messenger's own Send button stays under the user's control.
     */
    private fun insertDraft() {
        val draft = replyFlow.draftForInsertion() ?: return

        // Never destroy what the user already typed. If the field looks
        // non-empty, ask before touching it.
        if (hostField.appearsToHaveText()) {
            pendingInsertion = draft
            replyFlow.awaitConflictChoice()
            return
        }

        hostField.commitText(draft)
        closeComposer()
        refreshAutoShift()
    }

    private fun resolveConflict(choice: ConflictChoice) {
        val draft = pendingInsertion
        if (draft == null) {
            closeComposer()
            return
        }
        pendingInsertion = null

        when (choice) {
            ConflictChoice.CANCEL -> {
                replyFlow.cancelConflict()
                return
            }
            ConflictChoice.APPEND -> hostField.commitText(hostField.separatorForAppend() + draft)
            ConflictChoice.REPLACE -> {
                hostField.clear()
                hostField.commitText(draft)
            }
        }

        closeComposer()
        refreshAutoShift()
    }

    private fun showToast(error: AIReplyError) {
        val message = services.strings(uiLanguage).message(error)
        if (message.isEmpty()) return
        replyFlow.showToast(message)
        toastJob?.cancel()
        toastJob = scope.launch {
            // Long enough to read a two-line sentence in Kazakh or Russian.
            delay(TOAST_MS)
            replyFlow.clearToast()
        }
    }

    // ------------------------------------------------------------------ voice

    /**
     * The microphone's single entry point.
     *
     * Every state it can be in has exactly one sensible next action, which is
     * what keeps this a tap rather than a menu: listening stops, a refusal opens
     * Settings, a missing permission asks for it, and anything else starts.
     */
    private fun toggleMicrophone() {
        val client = speech ?: AndroidSpeechRecognitionClient(this).also {
            speech = it
            observeVoice(it)
        }

        when (voiceState) {
            is VoiceState.Listening, is VoiceState.Starting -> client.stop()
            is VoiceState.Processing -> Unit
            is VoiceState.PermissionDenied -> KeyboardStatus.openAppSettings(this)
            is VoiceState.PermissionRequired -> requestMicrophone()
            else -> if (!MicPermission.isGranted(this)) {
                requestMicrophone()
            } else {
                client.reset()
                client.start(uiLanguage.languageTag)
            }
        }
    }

    /**
     * Asks for the microphone through [kz.yerek.aireply.voice.VoicePermissionActivity].
     *
     * The collector is started BEFORE the dialog, because the result flow has no
     * replay: subscribing afterwards would race the user answering quickly and
     * occasionally lose the outcome, leaving the mic button dead until the next
     * tap.
     */
    private fun requestMicrophone() {
        permissionJob?.cancel()
        permissionJob = scope.launch {
            val outcome = async { MicPermission.results.first() }
            MicPermission.request(this@ReplyKeyboardService)
            when (outcome.await()) {
                MicPermission.Outcome.GRANTED -> {
                    speech?.reset()
                    speech?.start(uiLanguage.languageTag)
                }
                MicPermission.Outcome.PERMANENTLY_DENIED -> voiceState = VoiceState.PermissionDenied
                MicPermission.Outcome.DENIED -> voiceState = VoiceState.PermissionRequired
            }
        }
    }

    private fun observeVoice(client: SpeechRecognitionClient) {
        voiceJob?.cancel()
        voiceJob = scope.launch {
            client.state.collect { state ->
                voiceState = state
                if (state is VoiceState.Done) {
                    // Dictation lands in the INSTRUCTION field, appended rather
                    // than replacing, so a user can dictate twice or fix a word
                    // by hand and dictate the rest.
                    appendDictation(state.text)
                    client.reset()
                }
            }
        }
    }

    private fun appendDictation(text: String) {
        val addition = text.trim()
        if (addition.isEmpty()) return
        val field = replyFlow.instruction
        val separator = if (field.text.isEmpty() || field.text.endsWith(" ")) "" else " "
        field.set(field.text + separator + addition)
        focus = PanelFocus.INSTRUCTION
    }

    private fun cancelSpeech() {
        speech?.cancel()
        voiceState = VoiceState.Idle
    }

    private fun releaseSpeech() {
        voiceJob?.cancel()
        voiceJob = null
        speech?.release()
        speech = null
        voiceState = VoiceState.Idle
    }

    // ----------------------------------------------------------- configuration

    /**
     * PERFORMANCE. Profile and templates are read ONCE per appearance, off the
     * main thread, and never during a key press. The store additionally skips
     * parsing when the file has not changed, so a keyboard that opens and closes
     * repeatedly inside one messenger session pays a `stat` rather than a JSON
     * parse.
     */
    private fun loadConfigurationIfNeeded() {
        val now = SystemClock.uptimeMillis()
        if (now - configurationLoadedAt < CONFIG_RELOAD_MS) return
        configurationLoadedAt = now

        scope.launch {
            val loaded = withContext(Dispatchers.IO) {
                services.configuration.reload()
                services.configuration.current
            }
            replyFlow.configuration = loaded
            chips = loaded.visibleTemplates.map { template ->
                TemplateSummary(
                    id = template.id,
                    names = AppLanguage.entries.associate { language ->
                        language.code to TemplateNaming.displayName(
                            services.localized(language),
                            template
                        )
                    }
                )
            }
        }
    }

    /** The chip row as the app last saved it, or the defaults on a fresh install. */
    private fun cachedChips(): List<TemplateSummary> =
        services.settings.templateSummaries
            ?: ReplyConfiguration.INITIAL.visibleTemplates.map { template ->
                TemplateSummary(
                    id = template.id,
                    names = AppLanguage.entries.associate { language ->
                        language.code to TemplateNaming.displayName(
                            services.localized(language),
                            template
                        )
                    }
                )
            }

    /** Picks up a language or appearance the user changed in the app while this was off screen. */
    private fun refreshLanguages() {
        val language = services.settings.effectiveAppLanguage
        if (language != uiLanguage) {
            uiLanguage = language
            replyFlow.uiLanguage = language
            replyFlow.describeError = { error -> services.strings(language).message(error) }
            chips = cachedChips()
        }
        appearance = services.settings.appearance
        val storedLayout = services.settings.keyboardLanguage
        if (storedLayout != layout) layout = storedLayout
    }

    // -------------------------------------------------------- system keyboards

    private fun refreshGlobeKey() {
        showsGlobeKey = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            shouldOfferSwitchingToNextInputMethod()
        } else {
            @Suppress("DEPRECATION")
            val token = window?.window?.attributes?.token
            val manager = getSystemService(INPUT_METHOD_SERVICE) as? InputMethodManager
            token != null && manager?.shouldOfferSwitchingToNextInputMethod(token) == true
        }
    }

    private fun switchToNextKeyboard() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            switchToNextInputMethod(false)
        } else {
            @Suppress("DEPRECATION")
            val token = window?.window?.attributes?.token ?: return
            val manager = getSystemService(INPUT_METHOD_SERVICE) as? InputMethodManager
            manager?.switchToNextInputMethod(token, false)
        }
    }

    private fun showKeyboardPicker() {
        val manager = getSystemService(INPUT_METHOD_SERVICE) as? InputMethodManager
        runCatching { manager?.showInputMethodPicker() }
    }

    /**
     * The "+" chip opens the template editor in the app.
     *
     * iOS shows a hint here instead, because a keyboard extension cannot present
     * an editor or reliably open its containing app. An Android IME can start an
     * Activity, so it does.
     */
    private fun openTemplateEditor() {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra(MainActivity.EXTRA_ROUTE, MainActivity.ROUTE_TEMPLATES)
        runCatching { startActivity(intent) }
            .onFailure { ReplyLog.warn(it) { "could not open the template editor" } }
    }

    private companion object {
        const val DOUBLE_TAP_MS = 350L
        const val TOAST_MS = 3_200L
        const val CONFIG_RELOAD_MS = 1_000L
    }
}

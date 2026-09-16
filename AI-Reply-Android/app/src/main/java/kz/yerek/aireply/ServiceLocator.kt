package kz.yerek.aireply

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Dispatchers
import kz.yerek.aireply.ai.AIConfiguration
import kz.yerek.aireply.ai.AIReplyService
import kz.yerek.aireply.ai.AppStrings
import kz.yerek.aireply.ai.ReplyDraftNormalizer
import kz.yerek.aireply.core.lang.AppLanguage
import kz.yerek.aireply.core.lang.KeyboardLanguage
import kz.yerek.aireply.core.lang.LocalizedContext
import kz.yerek.aireply.core.lang.TemplateNaming
import kz.yerek.aireply.data.profile.ConfigurationRepository
import kz.yerek.aireply.data.profile.ProfileStore
import kz.yerek.aireply.data.secure.SecureCredentialStore
import kz.yerek.aireply.data.settings.SettingsStore

/**
 * The object graph, by hand.
 *
 * WHY NOT Hilt. Half of this app is an input method, and an input method is
 * started at the moment the user has just switched keyboards and is looking at
 * a blank strip waiting for keys. Hilt would add a generated component, a
 * reflective entry point and several hundred classes to the critical path in
 * order to construct seven objects, five of which are lazy anyway. The iOS
 * project uses plain singletons for the same reason.
 *
 * Everything here holds the APPLICATION context. Nothing holds an Activity, a
 * Service or a View, so nothing here can leak one.
 */
class ServiceLocator(context: Context) {

    private val appContext: Context = context.applicationContext

    /**
     * Application-scoped work that must outlive any one screen or keyboard
     * appearance — currently only refreshing the chip-row cache after a save.
     */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    val settings: SettingsStore by lazy { SettingsStore(appContext) }

    val credentials: SecureCredentialStore by lazy { SecureCredentialStore(appContext) }

    private val profileStore: ProfileStore by lazy { ProfileStore(appContext) }

    val configuration: ConfigurationRepository by lazy {
        ConfigurationRepository(appContext, profileStore, settings, scope)
    }

    val aiConfiguration: AIConfiguration by lazy { AIConfiguration(settings, credentials) }

    val draftNormalizer: ReplyDraftNormalizer by lazy { ReplyDraftNormalizer() }

    val replyService: AIReplyService by lazy {
        AIReplyService(
            configuration = aiConfiguration,
            credentials = credentials,
            nameTemplate = { template, language ->
                TemplateNaming.displayName(localized(language), template)
            }
        )
    }

    /**
     * A Context whose resources resolve in [language].
     *
     * Cached: building one is a Configuration copy and a resource-table lookup,
     * and the keyboard asks for the same two languages over and over.
     */
    fun localized(language: AppLanguage): Context =
        appLanguageContexts.getOrPut(language) { LocalizedContext.wrap(appContext, language) }

    fun localized(language: KeyboardLanguage): Context =
        keyboardLanguageContexts.getOrPut(language) { LocalizedContext.wrap(appContext, language) }

    /** Product strings in the app's chosen language. */
    fun strings(language: AppLanguage): AppStrings =
        stringsCache.getOrPut(language) { AppStrings(localized(language)) }

    private val appLanguageContexts = HashMap<AppLanguage, Context>()
    private val keyboardLanguageContexts = HashMap<KeyboardLanguage, Context>()
    private val stringsCache = HashMap<AppLanguage, AppStrings>()
}

import Foundation

/// Every user-visible string the AI reply flow needs, keyed by the APP's
/// interface language.
///
/// WHICH LANGUAGE, AND WHY. There are two languages in this product and they
/// answer different questions:
///
/// * the KEYBOARD LAYOUT decides what the character keys type, and what the
///   space and return keys are called - that is `KeyboardStrings`;
/// * the APP LANGUAGE decides what the PRODUCT says - template chips, Insert,
///   Regenerate, statuses and errors - which is this type.
///
/// They are deliberately not the same. A Kazakh user typing on the English
/// layout to write a Russian reply must still see "Кірістіру", because the
/// product is theirs and the layout is just a keyboard. Keying these strings to
/// the layout is exactly the bug this file used to have: the app was in Kazakh
/// and the chips read Friend / Client / Business / Work.
///
/// Resolved from a table rather than `NSLocalizedString` because the keyboard
/// extension has to show the language the user PICKED IN THE APP, which iOS
/// bundle lookup knows nothing about.
struct AIReplyStrings: Sendable {

    // Actions
    let generate: String
    let regenerate: String
    let insert: String
    let cancel: String
    let addTemplate: String
    /// Shown when the "+" chip is tapped. A keyboard extension cannot present
    /// an editor or reliably open its containing app, so this says where
    /// templates are made rather than pretending to make one.
    let addTemplateHint: String
    let replaceExisting: String
    let appendToExisting: String
    let keepTyping: String

    // Status
    let generating: String
    let draftTitle: String
    let sourceTitle: String
    let chooseTemplate: String

    // Errors
    let noSourceMessage: String
    let messageTooLong: String
    let fullAccessRequired: String
    let notConfigured: String
    let offline: String
    let timedOut: String
    let authenticationFailed: String
    let rateLimited: String
    let emptyResponse: String
    let serviceUnavailable: String
    /// Backend mode only: the session is gone, and a keyboard extension cannot
    /// sign anybody in, so it says where to do it.
    let signInRequired: String
    /// Backend mode only: the plan's daily generations are spent.
    let quotaExhausted: String

    // Host-field conflict
    let hostFieldNotEmpty: String

    static func forLanguage(_ language: AppLanguage) -> AIReplyStrings {
        switch language {
        case .english: return .english
        case .russian: return .russian
        case .kazakh:  return .kazakh
        }
    }

    /// Maps an error onto the sentence the user actually sees. Short, plain,
    /// actionable, and free of status codes, JSON and provider names.
    ///
    /// The transport mode matters for exactly two cases. In direct mode a
    /// rejected credential is the user's own API key; in backend mode it is
    /// their session, and telling them to check a key they never entered would
    /// send them looking for something that does not exist.
    func message(for error: AIReplyError, mode: AITransportMode = .direct) -> String {
        switch error {
        case .noSourceMessage:      return noSourceMessage
        case .messageTooLong:       return messageTooLong
        case .fullAccessRequired:   return fullAccessRequired
        case .notConfigured:        return notConfigured
        case .offline:              return offline
        case .timedOut:             return timedOut
        case .cancelled:            return ""
        case .authenticationFailed: return mode == .backend ? signInRequired : authenticationFailed
        case .rateLimited:          return mode == .backend ? quotaExhausted : rateLimited
        case .emptyResponse:        return emptyResponse
        case .serviceUnavailable:   return serviceUnavailable
        }
    }

    private static let english = AIReplyStrings(
        generate: "Reply",
        regenerate: "Regenerate",
        insert: "Insert",
        cancel: "Cancel",
        addTemplate: "Add template",
        addTemplateHint: "Create templates in the AI Reply app.",
        replaceExisting: "Replace",
        appendToExisting: "Add",
        keepTyping: "Cancel",
        generating: "Generating…",
        draftTitle: "Your reply",
        sourceTitle: "Reply to",
        chooseTemplate: "Choose who you are replying to",
        noSourceMessage: "Copy a message first",
        // Wording taken from the brief, verbatim.
        messageTooLong: "Message is too long. Please select or copy up to 300 characters.",
        fullAccessRequired: "Turn on Allow Full Access for this keyboard in iOS Settings to use a copied message.",
        notConfigured: "Open the AI Reply app and finish setup first.",
        offline: "No internet connection.",
        timedOut: "That took too long. Try again.",
        authenticationFailed: "Your API key was rejected. Check it in the AI Reply app.",
        rateLimited: "Too many requests. Wait a moment and try again.",
        emptyResponse: "No reply came back. Try again.",
        serviceUnavailable: "The service is unavailable right now. Try again.",
        signInRequired: "Open the AI Reply app and sign in to keep replying.",
        quotaExhausted: "You have used today's replies. They come back tomorrow, or change your plan in the app.",
        hostFieldNotEmpty: "There is already text in this field."
    )

    private static let russian = AIReplyStrings(
        generate: "Ответить",
        regenerate: "Сгенерировать заново",
        insert: "Вставить",
        cancel: "Отмена",
        addTemplate: "Добавить шаблон",
        addTemplateHint: "Шаблоны создаются в приложении AI Reply.",
        replaceExisting: "Заменить",
        appendToExisting: "Добавить",
        keepTyping: "Отмена",
        generating: "Создаю ответ…",
        draftTitle: "Ваш ответ",
        sourceTitle: "Ответ на",
        chooseTemplate: "Выберите, кому вы отвечаете",
        noSourceMessage: "Сначала скопируйте сообщение",
        messageTooLong: "Сообщение слишком длинное. Скопируйте не более 300 символов.",
        fullAccessRequired: "Чтобы использовать скопированное сообщение, включите полный доступ для клавиатуры в настройках iOS.",
        notConfigured: "Откройте приложение AI Reply и завершите настройку.",
        offline: "Нет подключения к интернету.",
        timedOut: "Слишком долго. Попробуйте ещё раз.",
        authenticationFailed: "Ключ API отклонён. Проверьте его в приложении AI Reply.",
        rateLimited: "Слишком много запросов. Подождите немного.",
        emptyResponse: "Ответ не получен. Попробуйте ещё раз.",
        serviceUnavailable: "Сервис сейчас недоступен. Попробуйте позже.",
        signInRequired: "Откройте приложение AI Reply и войдите, чтобы продолжить.",
        quotaExhausted: "Ответы на сегодня закончились. Они обновятся завтра — или смените тариф в приложении.",
        hostFieldNotEmpty: "В этом поле уже есть текст."
    )

    private static let kazakh = AIReplyStrings(
        generate: "Жауап беру",
        regenerate: "Қайта жасау",
        insert: "Кірістіру",
        cancel: "Бас тарту",
        addTemplate: "Үлгі қосу",
        addTemplateHint: "Үлгілер AI Reply қолданбасында жасалады.",
        replaceExisting: "Ауыстыру",
        appendToExisting: "Қосу",
        keepTyping: "Бас тарту",
        generating: "Жауап дайындалуда…",
        draftTitle: "Сіздің жауабыңыз",
        sourceTitle: "Хабарламаға жауап",
        chooseTemplate: "Кімге жауап беретініңізді таңдаңыз",
        noSourceMessage: "Алдымен хабарламаны көшіріңіз",
        messageTooLong: "Хабарлама тым ұзын. 300 таңбаға дейінгі мәтінді көшіріңіз.",
        fullAccessRequired: "Көшірілген хабарламаны пайдалану үшін iOS баптауларында пернетақтаға толық рұқсат беріңіз.",
        notConfigured: "AI Reply қолданбасын ашып, баптауды аяқтаңыз.",
        offline: "Интернет байланысы жоқ.",
        timedOut: "Тым ұзаққа созылды. Қайталап көріңіз.",
        authenticationFailed: "API кілті қабылданбады. AI Reply қолданбасынан тексеріңіз.",
        rateLimited: "Сұраныс тым көп. Сәл күте тұрыңыз.",
        emptyResponse: "Жауап келмеді. Қайталап көріңіз.",
        serviceUnavailable: "Қызмет қазір қолжетімсіз. Кейінірек көріңіз.",
        signInRequired: "Жалғастыру үшін AI Reply қолданбасын ашып, кіріңіз.",
        quotaExhausted: "Бүгінгі жауаптар бітті. Ертең жаңарады немесе қолданбадан тарифті ауыстырыңыз.",
        hostFieldNotEmpty: "Бұл өрісте мәтін бар."
    )
}

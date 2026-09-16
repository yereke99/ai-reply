package kz.yerek.aireply.data.settings

/** How the app resolves light and dark mode. */
enum class AppearancePreference(val raw: String) {
    SYSTEM("system"),
    LIGHT("light"),
    DARK("dark");

    companion object {
        fun fromRaw(raw: String?): AppearancePreference =
            entries.firstOrNull { it.raw == raw } ?: SYSTEM
    }
}

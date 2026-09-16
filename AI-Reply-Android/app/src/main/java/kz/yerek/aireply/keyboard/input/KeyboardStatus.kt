package kz.yerek.aireply.keyboard.input

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.inputmethod.InputMethodManager

/**
 * Whether AI Reply's keyboard is enabled, and whether it is the one currently
 * in use.
 *
 * THIS IS WHERE ANDROID IS SIMPLY BETTER THAN iOS. The iOS project has a long
 * comment explaining that no public API tells a containing app whether its own
 * keyboard extension has been added, so the keyboard has to write a timestamp
 * into a shared container and the setup screen has to show "not known yet" as a
 * real state. Android answers both questions directly, so the checklist here is
 * a fact rather than an inference, and there is no third state to design for.
 */
object KeyboardStatus {

    data class Snapshot(val isEnabled: Boolean, val isSelected: Boolean) {
        val isReady: Boolean get() = isEnabled && isSelected
    }

    fun current(context: Context): Snapshot =
        Snapshot(isEnabled = isEnabled(context), isSelected = isSelected(context))

    /** Present in the system's list of enabled input methods. */
    fun isEnabled(context: Context): Boolean {
        val manager = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            ?: return false
        return manager.enabledInputMethodList.any { it.packageName == context.packageName }
    }

    /**
     * Currently the active input method.
     *
     * `Settings.Secure.DEFAULT_INPUT_METHOD` is readable without any permission
     * and is the value the system itself uses, so this needs no heuristic.
     */
    fun isSelected(context: Context): Boolean {
        val current = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.DEFAULT_INPUT_METHOD
        ) ?: return false
        return current.substringBefore('/') == context.packageName
    }

    /**
     * Opens the system's keyboard list so the user can switch AI Reply on.
     *
     * Unlike iOS, which can only open an app's own settings page, Android has a
     * public intent that lands exactly where the user needs to be.
     */
    fun openKeyboardSettings(context: Context) {
        val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
    }

    /** Opens the "choose input method" picker. */
    fun showKeyboardPicker(context: Context) {
        val manager = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        runCatching { manager?.showInputMethodPicker() }
    }

    fun openAppSettings(context: Context) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(android.net.Uri.fromParts("package", context.packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
    }
}

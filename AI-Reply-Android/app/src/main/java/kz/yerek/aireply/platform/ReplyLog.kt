package kz.yerek.aireply.platform

import android.util.Log
import kz.yerek.aireply.BuildConfig

/**
 * Diagnostics that never reach the UI and never carry message content, profile
 * text or draft text — only lengths and outcomes, and only in a debug build.
 *
 * The rule this enforces is the product's central privacy promise: a copied
 * message is private, and a log file that survives the keyboard closing would
 * be the one place it stopped being private.
 */
object ReplyLog {

    private const val TAG = "ReplyKeyboard"

    fun event(message: () -> String) {
        if (BuildConfig.DEBUG) Log.d(TAG, message())
    }

    fun warn(throwable: Throwable? = null, message: () -> String) {
        if (BuildConfig.DEBUG) Log.w(TAG, message(), throwable)
    }
}

package kz.yerek.aireply.voice

import android.Manifest
import android.app.Activity
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts

/**
 * Asks for the microphone on the keyboard's behalf, and does nothing else.
 *
 * It draws no UI of its own — the theme is fully transparent — so what the user
 * sees is the system permission dialog appearing over whatever app they were
 * typing in, and then their keyboard again. It is `noHistory` and
 * `excludeFromRecents` so it never shows up as a screen the user can navigate
 * back to.
 *
 * This is the supported way for an input method to obtain a runtime permission.
 * There is no alternative: `requestPermissions` lives on Activity, and an IME is
 * a Service.
 */
class VoicePermissionActivity : ComponentActivity() {

    private val launcher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        val outcome = when {
            granted -> MicPermission.Outcome.GRANTED
            // After a refusal, the system stops offering a rationale once the
            // user has chosen "don't ask again". That is the only signal Android
            // gives for "permanently denied", and it is what decides whether the
            // keyboard offers to retry or points at Settings.
            shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) ->
                MicPermission.Outcome.DENIED
            else -> MicPermission.Outcome.PERMANENTLY_DENIED
        }
        MicPermission.publish(outcome)
        setResult(if (granted) Activity.RESULT_OK else Activity.RESULT_CANCELED)
        finish()
        overridePendingTransition(0, 0)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            launcher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
}

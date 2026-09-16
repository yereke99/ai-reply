package kz.yerek.aireply.keyboard

import android.content.Context
import android.view.View
import androidx.compose.ui.platform.ComposeView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner

/**
 * Makes a [ComposeView] usable inside an [android.inputmethodservice.InputMethodService].
 *
 * WHY THIS CLASS HAS TO EXIST. Compose resolves its lifecycle, ViewModel store
 * and saved-state registry from the view tree. An Activity provides all three;
 * a Service provides none, so a bare `ComposeView` returned from
 * `onCreateInputView` throws the moment it tries to compose. There is no
 * official IME-flavoured ComposeView, so the owners are supplied here and driven
 * by the service's own callbacks.
 *
 * The lifecycle is driven deliberately rather than pinned at RESUMED: an input
 * method can be constructed long before it is shown and can sit hidden for
 * hours, and animations, effects and coroutines launched in the composition
 * should stop when it is not on screen. That is most of what keeps a keyboard
 * from quietly costing battery in the background.
 */
class KeyboardViewHost(context: Context) : LifecycleOwner, ViewModelStoreOwner, SavedStateRegistryOwner {

    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateController = SavedStateRegistryController.create(this)

    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val viewModelStore: ViewModelStore = ViewModelStore()
    override val savedStateRegistry: SavedStateRegistry get() = savedStateController.savedStateRegistry

    init {
        savedStateController.performAttach()
        savedStateController.performRestore(null)
        lifecycleRegistry.currentState = Lifecycle.State.INITIALIZED
    }

    /** Attaches the owners to a view tree. Call before the view is composed. */
    fun attachTo(view: View) {
        view.setViewTreeLifecycleOwner(this)
        view.setViewTreeViewModelStoreOwner(this)
        view.setViewTreeSavedStateRegistryOwner(this)
    }

    fun onCreate() {
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
    }

    fun onShown() {
        lifecycleRegistry.currentState = Lifecycle.State.RESUMED
    }

    fun onHidden() {
        // CREATED rather than DESTROYED: the view is reused the next time the
        // keyboard appears, and destroying the composition on every hide would
        // mean rebuilding the whole key grid each time the user switches apps —
        // which is exactly the lag the iOS build fought with its page cache.
        if (lifecycleRegistry.currentState.isAtLeast(Lifecycle.State.CREATED)) {
            lifecycleRegistry.currentState = Lifecycle.State.CREATED
        }
    }

    fun onDestroy() {
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
        viewModelStore.clear()
    }
}

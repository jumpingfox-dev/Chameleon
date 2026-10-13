package dev.jumpingfox.chameleon

import android.os.Build
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onPostResume() {
        super.onPostResume()
        // With a D-pad or keyboard, Android outlines the focused view, which here is the whole
        // Flutter view (a green frame around the screen). The app draws its own focus instead.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) window.decorView.hideFocusHighlight()
    }

    private fun View.hideFocusHighlight() {
        defaultFocusHighlightEnabled = false
        if (this is ViewGroup) for (i in 0 until childCount) getChildAt(i).hideFocusHighlight()
    }
}

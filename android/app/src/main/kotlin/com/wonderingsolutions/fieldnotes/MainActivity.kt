package com.wonderingsolutions.fieldnotes

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Build
import android.os.Bundle
import android.text.InputFilter
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Space
import android.widget.TextView
import kotlin.math.max
import kotlin.math.roundToInt

// The pen widths the width button steps through, in sheet units.
private val WIDTHS = floatArrayOf(1.5f, 2.5f, 4f, 7f)

class MainActivity : Activity() {
    private lateinit var sheetView: SheetView
    private val tools = HashMap<Tool, View>()
    private lateinit var width: TextView
    private lateinit var sheets: TextView
    private val needsLive = ArrayList<View>() // enabled while the desktop can take drawing
    private lateinit var previous: View
    private lateinit var next: View
    private lateinit var show: View

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= 28) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        saveToken(intent)

        val dp = resources.displayMetrics.density
        fun px(value: Int) = (value * dp).roundToInt()
        sheetView = SheetView(this)
        sheetView.onTitle = { ask("Sheet title", sheetView.current.title, false, 60) { text -> Link.send { titleLine(it, text.trim()) } } }
        sheetView.onNote = { x, y ->
            ask("New note", "", true, 4096) { text ->
                // The desktop puts a note's corner 4 left of and 12 above where it was clicked.
                val sheet = sheetView.current
                val left = ((x - 4) * 10).roundToInt().coerceIn(0, sheet.width * 10)
                val top = ((y - 12) * 10).roundToInt().coerceIn(0, sheet.height * 10)
                if (text.isNotBlank()) Link.send { noteLine(it, left, top, text.trim()) }
            }
        }

        val toolbar = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(4), px(4), px(4), px(4))
            background = GradientDrawable().apply {
                setColor(0xF02B2925.toInt())
                setStroke(px(1), 0x5A6F695D)
                cornerRadius = 13 * dp
            }
        }
        val tint = ColorStateList(
            arrayOf(intArrayOf(android.R.attr.state_selected), intArrayOf(android.R.attr.state_pressed), intArrayOf(-android.R.attr.state_enabled), intArrayOf()),
            intArrayOf(0xFFF0E9D8.toInt(), 0xFFF0E9D8.toInt(), 0x4DA9A291, 0xFFA9A291.toInt()),
        )
        // An icon over a caption; the tool in use stays lit.
        fun button(icon: Int, caption: String, live: Boolean = true, onClick: () -> Unit): View {
            val image = ImageView(this).apply {
                setImageResource(icon) // Material Icons and Symbols, Apache License 2.0 (see res/drawable)
                imageTintList = tint
                isDuplicateParentStateEnabled = true
            }
            val text = TextView(this).apply {
                this.text = caption
                textSize = 10f
                gravity = Gravity.CENTER
                maxLines = 2
                setTextColor(tint)
                isDuplicateParentStateEnabled = true
            }
            val lit = StateListDrawable().apply {
                val round = { color: Int -> GradientDrawable().apply { setColor(color); cornerRadius = 9 * dp } }
                addState(intArrayOf(android.R.attr.state_selected), round(0x33F0E9D8))
                addState(intArrayOf(android.R.attr.state_pressed), round(0x22F0E9D8))
            }
            return LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                background = lit
                contentDescription = caption
                setOnClickListener { onClick() }
                addView(image, LinearLayout.LayoutParams(px(24), px(24)))
                addView(text, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
                toolbar.addView(this, LinearLayout.LayoutParams(px(64), px(56)))
                if (live) needsLive.add(this)
            }
        }
        fun gap() = toolbar.addView(Space(this), LinearLayout.LayoutParams(px(8), px(8)))
        fun choose(tool: Tool, icon: Int, caption: String) {
            tools[tool] = button(icon, caption) {
                sheetView.tool = tool
                updateButtons()
            }
        }

        choose(Tool.PEN, R.drawable.pen, "Pen")
        choose(Tool.ERASER, R.drawable.eraser, "Eraser")
        choose(Tool.TEXT, R.drawable.text, "Text")
        val widthButton = button(R.drawable.width, "Width") {
            val now = sheetView.current.penWidth
            val larger = WIDTHS.firstOrNull { it > now + 0.01f } ?: WIDTHS[0]
            Link.send { widthLine(it, (larger * 10).roundToInt()) }
        }
        width = (widthButton as ViewGroup).getChildAt(1) as TextView
        gap()
        button(R.drawable.undo, "Undo") {
            sheetView.undoPending()
            Link.send { commandLine("undo", it) }
        }
        button(R.drawable.redo, "Redo") { Link.send { commandLine("redo", it) } }
        button(R.drawable.clear, "Clear sheet") {
            AlertDialog.Builder(this)
                .setTitle("Clear this sheet?")
                .setMessage("Undo on the desktop brings it back.")
                .setPositiveButton("Clear") { _, _ ->
                    sheetView.clearPending()
                    Link.send { commandLine("clear", it) }
                }
                .setNegativeButton(android.R.string.cancel, null)
                .show()
        }
        gap()
        previous = button(R.drawable.previous, "Previous", live = false) { Link.send { selectLine(it, sheetView.current.number - 1) } }
        sheets = TextView(this).apply {
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(0xFFF0E9D8.toInt())
            toolbar.addView(this, LinearLayout.LayoutParams(px(64), px(24)))
        }
        next = button(R.drawable.next, "Next", live = false) { Link.send { selectLine(it, sheetView.current.number + 1) } }
        button(R.drawable.new_sheet, "New sheet") { Link.send { commandLine("new", it) } }
        gap()
        show = button(R.drawable.show_on_desktop, "Show on desktop", live = false) { Link.send { commandLine("show", it) } }

        // The toolbar goes on the right of a wide screen and at the bottom of a tall one, and
        // scrolls when the screen is too small to show all of it.
        val scrollTall = ScrollView(this).apply { isVerticalScrollBarEnabled = false }
        val scrollWide = HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled = false }
        val root = object : LinearLayout(this) {
            override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
                super.onSizeChanged(w, h, oldw, oldh)
                // Not inside the layout pass that called this: a view added now would stay unmeasured.
                post {
                    val wide = w >= h
                    val scroller = if (wide) scrollTall else scrollWide
                    if (toolbar.parent !== scroller) {
                        orientation = if (wide) HORIZONTAL else VERTICAL
                        toolbar.orientation = if (wide) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
                        (toolbar.parent as? ViewGroup)?.removeView(toolbar)
                        scroller.addView(toolbar)
                        if (childCount > 1) removeViewAt(1)
                        sheetView.layoutParams = if (wide) LayoutParams(0, LayoutParams.MATCH_PARENT, 1f) else LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f)
                        addView(scroller, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { setMargins(px(8), px(8), px(8), px(8)) })
                    }
                }
            }
        }
        root.gravity = Gravity.CENTER
        root.addView(sheetView, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f))
        // Clear of the cutout, the caption bar and any system bar on screen. This runs on every
        // dispatch, so a 180° turn, which changes no configuration, moves the padding across.
        root.setOnApplyWindowInsetsListener { view, insets ->
            if (Build.VERSION.SDK_INT >= 30) {
                val safe = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout() or WindowInsets.Type.captionBar())
                view.setPadding(safe.left, safe.top, safe.right, safe.bottom)
            } else {
                @Suppress("DEPRECATION")
                view.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
                if (Build.VERSION.SDK_INT >= 28) {
                    val cutout = insets.displayCutout
                    if (cutout != null) {
                        view.setPadding(
                            max(view.paddingLeft, cutout.safeInsetLeft),
                            max(view.paddingTop, cutout.safeInsetTop),
                            max(view.paddingRight, cutout.safeInsetRight),
                            max(view.paddingBottom, cutout.safeInsetBottom),
                        )
                    }
                }
            }
            insets
        }
        setContentView(root)
        hideSystemBars()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (saveToken(intent) && Link.running) startLink()
    }

    override fun onStart() {
        super.onStart()
        sheetView.stylusSeen = false
        startLink()
    }

    override fun onStop() {
        super.onStop()
        Link.stop()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    /** `make run` pairs the phone: it starts the app with the desktop's token in the `token` extra. */
    private fun saveToken(intent: Intent): Boolean {
        val token = intent.getStringExtra("token")
        if (token != null) getSharedPreferences("pairing", MODE_PRIVATE).edit().putString("token", token).apply()
        return token != null
    }

    private fun startLink() {
        val token = getSharedPreferences("pairing", MODE_PRIVATE).getString("token", "") ?: ""
        sheetView.onMessage(Offline) // no sheet has come on the new connection yet
        updateButtons()
        Link.start(token) { message ->
            sheetView.onMessage(message)
            updateButtons()
        }
    }

    private fun updateButtons() {
        val sheet = sheetView.current
        for ((tool, view) in tools) view.isSelected = tool == sheetView.tool
        for (view in needsLive) view.isEnabled = sheetView.drawingAllowed
        previous.isEnabled = sheetView.drawingAllowed && sheet.number > 1
        next.isEnabled = sheetView.drawingAllowed && sheet.number < sheet.count
        show.isEnabled = sheetView.live
        width.text = "Width " + sheet.penWidth.toString().removeSuffix(".0")
        sheets.text = "${sheet.number}/${sheet.count}"
        for (view in needsLive + listOf(previous, next, show)) view.alpha = if (view.isEnabled) 1f else 0.35f
    }

    /** A dialog with a text field and the keyboard, for the title and for notes. */
    private fun ask(title: String, initial: String, multiline: Boolean, max: Int, done: (String) -> Unit) {
        val dp = resources.displayMetrics.density
        val field = EditText(this).apply {
            setText(initial)
            selectAll()
            filters = arrayOf(InputFilter.LengthFilter(max))
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or (if (multiline) InputType.TYPE_TEXT_FLAG_MULTI_LINE else 0)
            if (!multiline) {
                setSingleLine()
                imeOptions = EditorInfo.IME_ACTION_DONE
            }
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(title)
            .setView(FrameLayout(this).apply {
                val side = (20 * dp).roundToInt()
                setPadding(side, 0, side, 0)
                addView(field)
            })
            .setPositiveButton("OK") { _, _ -> done(field.text.toString()) }
            .setNegativeButton(android.R.string.cancel, null)
            .create()
        field.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_DONE) dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
            action == EditorInfo.IME_ACTION_DONE
        }
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)
        dialog.show()
        field.requestFocus()
        field.post { getSystemService(InputMethodManager::class.java).showSoftInput(field, InputMethodManager.SHOW_IMPLICIT) }
    }

    // Immersive: a swipe from an edge brings the bars back for a moment.
    private fun hideSystemBars() {
        if (Build.VERSION.SDK_INT >= 30) {
            // Deprecated because Android 15 makes it the default for this target; 11 to 14 need it.
            @Suppress("DEPRECATION")
            window.setDecorFitsSystemWindows(false)
            window.decorView.windowInsetsController?.run {
                hide(WindowInsets.Type.systemBars())
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        }
    }
}

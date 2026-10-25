package com.wonderingsolutions.fieldnotes

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.os.SystemClock
import android.text.TextPaint
import android.text.TextUtils
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import kotlin.math.hypot
import kotlin.math.min

private const val DESK = 0xFF2B2925.toInt()
private const val PAPER = 0xFFDED7C5.toInt()
private const val BORDER = 0xFFB8AD96.toInt()
private const val INK = 0xFF423E38.toInt()
private const val UNTITLED = 0x59423E38 // ink at 35 %
private const val LABEL = 0x805B5349.toInt()
private const val ERROR = 0xFFC0736A.toInt()

// MotionEvent.FLAG_CANCELED is API 33, but the value is safe to test on any version.
private const val FLAG_CANCELED = 0x20

// The desktop's medium eraser, in sheet units (Field Notes' own setting decides the real one).
private const val ERASER_RADIUS = 10f

// How often the pen's new points go to the desktop to show live, in ms.
private const val LIVE_EVERY = 50L

enum class Tool { PEN, ERASER, TEXT }

/** The open sheet drawn as the desktop draws it, and the pen that adds strokes to it. */
class SheetView(context: Context) : View(context) {
    /** What a touch on the page does. */
    var tool = Tool.PEN

    /** A tap on the page with the text tool: where, in sheet units. */
    var onNote: (Float, Float) -> Unit = { _, _ -> }

    /** A tap on the title. */
    var onTitle: () -> Unit = {}

    val current get() = sheet

    /** After a stylus touches the sheet, fingers no longer draw (a resting palm); reset in onStart. */
    var stylusSeen = false

    /** A sheet has arrived on this connection: a connect alone means nothing, adbd accepts it anyway. */
    var live = false
        private set
    val drawingAllowed get() = live && desk.ok && desk.saved != "LOADING" && desk.saved != "NOT SAVED"

    private var unpaired = false
    private var desk = Desk(false, false, "", "")
    private var sheet = Sheet.BLANK
    private var paths = emptyList<Path>()
    private val pending = Pending()
    private var notice = ""
    private var noticeUntil = 0L

    // The page in view pixels; a sheet unit is `scale` pixels.
    private val page = RectF()
    private var scale = 1f

    // The ruling, built once per sheet: lines (x0 y0 x1 y1 …), or points on dots paper.
    private var fine = FloatArray(0)
    private var bold = FloatArray(0)
    private var title = ""
    private var label = ""

    // Where a tap opens the title field: the header left of the label, in sheet units.
    private val titleZone = RectF()

    // The stroke being drawn: its pointer, its samples in sheet units, and the sheet and page it began on.
    private var activeId = -1
    private var samples = FloatArray(1024)
    private var sampleCount = 0
    private var strokeSheet = sheet
    private var strokeLeft = 0f
    private var strokeTop = 0f
    private var strokeScale = 1f
    private var strokeTool = Tool.PEN
    private val stream = Stream()
    private var streamedAt = 0L
    private val livePath = Path()

    // A tap in progress (the title, or a note with the text tool): its pointer, where it began, and what it is.
    private var tapId = -1
    private var tapX = 0f
    private var tapY = 0f
    private var tapsTitle = false
    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private val pendingPath = Path()

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND // round dots from drawPoints; line ends fall outside the clip
    }
    private val ink = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = INK
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val titlePaint = textPaint(16f, true, 0.1625f, INK)
    private val labelPaint = textPaint(9f, false, 0.122f, LABEL).apply { textAlign = Paint.Align.RIGHT }
    private val footerPaint = textPaint(9f, true, 0.178f, LABEL)
    private val notePaint = textPaint(16f, false, 0f, INK)
    private val overlayPaint = textPaint(14f, false, 0f, INK).apply { textAlign = Paint.Align.CENTER }

    // The title and label are centred on the header's middle line, y = 23.
    private val titleBaseline = 23 - (titlePaint.ascent() + titlePaint.descent()) / 2
    private val labelBaseline = 23 - (labelPaint.ascent() + labelPaint.descent()) / 2

    fun onMessage(message: Message) {
        when (message) {
            is SheetMessage -> {
                val next = message.sheet
                val resized = next.width != sheet.width || next.height != sheet.height
                sheet = next
                live = true
                unpaired = false
                pending.settle(message.settled)
                paths = next.strokes.map { stroke -> Path().also { trace(it, stroke.points, stroke.points.size, stroke.width) } }

                // Ruled as the desktop rules it: inside the 1-unit border, lines on half units.
                val w = next.width - 2
                val h = next.height - 2
                val fineList = ArrayList<Float>()
                val boldList = ArrayList<Float>()
                when (next.paper) {
                    "graph" -> for ((every, list) in listOf(16 to fineList, 80 to boldList)) {
                        for (x in every until w step every) list += listOf(x + 0.5f, 0f, x + 0.5f, h.toFloat())
                        for (y in every until h step every) list += listOf(0f, y + 0.5f, w.toFloat(), y + 0.5f)
                    }
                    "dots" -> for (x in 16 until w step 16) {
                        for (y in 16 until h step 16) {
                            val list = if (x % 80 == 0 && y % 80 == 0) boldList else fineList
                            list += listOf(x.toFloat(), y.toFloat())
                        }
                    }
                    "ruled" -> {
                        for (y in 70 until h - 20 step 24) fineList += listOf(0f, y + 0.5f, w.toFloat(), y + 0.5f)
                        boldList += listOf(64.5f, 0f, 64.5f, h.toFloat())
                    }
                }
                fine = fineList.toFloatArray()
                bold = boldList.toFloatArray()

                val paper = when (next.paper) {
                    "dots" -> "DOTS 16"
                    "ruled" -> "RULED 24"
                    "plain" -> "PLAIN"
                    else -> "GRAPH 16"
                }
                val size = when (next.width) {
                    520 -> "SMALL"
                    1040 -> "LARGE"
                    else -> "MEDIUM"
                }
                label = "SHEET ${next.number.toString().padStart(2, '0')} OF ${next.count.toString().padStart(2, '0')}  /  $paper  /  $size"
                // The title stops short of the label, with the desktop's gaps: 28 before it, 24 after.
                val room = next.width - 25 - labelPaint.measureText(label) - 24 - 28
                titlePaint.color = if (next.title.isEmpty()) UNTITLED else INK
                title = TextUtils.ellipsize(next.title.uppercase().ifEmpty { "UNTITLED" }, titlePaint, room, TextUtils.TruncateAt.END).toString()
                titleZone.set(0f, 0f, 28 + maxOf(room, 60f), 46f)
                if (resized) place()
            }
            is Desk -> desk = message
            is Failure -> {
                message.id?.let { pending.fail(it) }
                flash(message.message)
            }
            Unpaired, Offline -> {
                live = false
                unpaired = message === Unpaired
                pending.clear()
            }
            Other -> {}
        }
        invalidate()
    }

    /** Clear empties the sheet, so strokes still on their way to it have nothing to wait for. */
    fun clearPending() {
        pending.clear()
        invalidate()
    }

    /** Undo shows at once: the newest stroke still on its way to the desktop goes now. */
    fun undoPending() {
        pending.undo(sheet.number)
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        place()
    }

    override fun onDraw(canvas: Canvas) {
        val w = sheet.width.toFloat()
        val h = sheet.height.toFloat()
        canvas.drawColor(DESK)
        canvas.save()
        canvas.translate(page.left, page.top)
        canvas.scale(scale, scale)

        fill.color = PAPER
        canvas.drawRoundRect(0f, 0f, w, h, 3f, 3f, fill)
        canvas.drawRoundRect(0.5f, 0.5f, w - 0.5f, h - 0.5f, 2.5f, 2.5f, line(1f, BORDER))
        canvas.save()
        canvas.translate(1f, 1f)
        canvas.clipRect(0f, 0f, w - 2, h - 2)
        when (sheet.paper) {
            "graph" -> {
                canvas.drawLines(fine, line(1f, 0x337898A8))
                canvas.drawLines(bold, line(1.15f, 0x4F5F8394))
            }
            "dots" -> {
                canvas.drawPoints(fine, line(2.2f, 0x6B5F8394))
                canvas.drawPoints(bold, line(3f, 0x9E5F8394.toInt()))
            }
            "ruled" -> {
                canvas.drawLines(fine, line(1f, 0x737898A8))
                canvas.drawLines(bold, line(1f, 0x80C0736A.toInt()))
            }
        }
        canvas.restore()

        for (i in paths.indices) drawInk(canvas, paths[i], sheet.strokes[i].width, sheet.strokes[i].points.size)
        for (stroke in pending.visible(sheet.number)) {
            trace(pendingPath, stroke.points, stroke.points.size, stroke.width)
            drawInk(canvas, pendingPath, stroke.width, stroke.points.size)
        }
        if (activeId >= 0 && strokeTool == Tool.PEN) {
            trace(livePath, samples, sampleCount, sheet.penWidth)
            drawInk(canvas, livePath, sheet.penWidth, sampleCount)
        }

        // Ink lies under the header and the notes, as on the desktop.
        fill.color = 0x17FFFFFF
        canvas.drawRect(0f, 0f, w, 46f, fill)
        canvas.drawLine(0f, 45.5f, w, 45.5f, line(1f, 0x375B5349))

        val noticing = SystemClock.uptimeMillis() < noticeUntil
        val status = when {
            noticing -> notice
            unpaired -> "NOT PAIRED"
            !live -> "OFFLINE"
            !desk.ok -> "FIELD NOTES NOT RUNNING"
            desk.saved == "LOADING" -> "DESKTOP LOADING"
            desk.saved == "NOT SAVED" -> "DESKTOP NOT SAVING"
            !desk.open -> "LIVE · NOTES PUT AWAY"
            else -> "LIVE"
        }
        footerPaint.textAlign = Paint.Align.LEFT
        footerPaint.color = LABEL
        canvas.drawText("FIELD NOTES", 28f, h - 15, footerPaint)
        footerPaint.textAlign = Paint.Align.RIGHT
        footerPaint.color = if (noticing || unpaired || live && !drawingAllowed) ERROR else LABEL
        canvas.drawText(status, w - 24, h - 15, footerPaint)

        for (note in sheet.notes) {
            notePaint.textSize = note.size
            for (i in note.lines.indices) {
                canvas.drawText(note.lines[i], note.x + 4, note.y + 4 + 1.02f * note.size + i * 1.32f * note.size, notePaint)
            }
        }
        canvas.drawText(title, 28f, titleBaseline, titlePaint)
        canvas.drawLine(28f, titleBaseline + 4, 28 + titlePaint.measureText(title), titleBaseline + 4, line(1f, 0x40423E38)) // it is a button
        canvas.drawText(label, w - 25, labelBaseline, labelPaint)

        if (!live) {
            val first = if (unpaired) "Not paired with this desktop" else "Turn on Draw from a phone in Field Notes settings"
            val second = if (unpaired) "run make run on the desktop once" else "then connect this phone by USB or Wireless debugging"
            canvas.drawText(first, w / 2, h / 2 - 6, overlayPaint)
            canvas.drawText(second, w / 2, h / 2 + 14, overlayPaint)
        }
        if (activeId >= 0 && strokeTool == Tool.ERASER) {
            canvas.drawCircle(samples[sampleCount - 2], samples[sampleCount - 1], ERASER_RADIUS, line(1f, INK))
        }
        canvas.restore()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                    requestUnbufferedDispatch(event) // every pen sample as it comes, not one per frame
                    dropStroke()
                    tapId = -1
                }
                val i = event.actionIndex
                val tool = event.getToolType(i)
                if (tool == MotionEvent.TOOL_TYPE_STYLUS) {
                    stylusSeen = true
                    dropStroke() // a finger stroke in progress was the palm
                    tapId = -1
                }
                val starts = tool == MotionEvent.TOOL_TYPE_STYLUS || tool != MotionEvent.TOOL_TYPE_ERASER && activeId < 0 && tapId < 0 && !stylusSeen
                // Only on the page: the edge swipes that bring back the hidden system bars never draw.
                if (starts && drawingAllowed && page.contains(event.getX(i), event.getY(i))) {
                    val onTitle = titleZone.contains((event.getX(i) - page.left) / scale, (event.getY(i) - page.top) / scale)
                    if (onTitle || this.tool == Tool.TEXT) {
                        tapId = event.getPointerId(i)
                        tapX = event.getX(i)
                        tapY = event.getY(i)
                        tapsTitle = onTitle
                    } else {
                        activeId = event.getPointerId(i)
                        strokeTool = this.tool
                        strokeSheet = sheet
                        strokeLeft = page.left
                        strokeTop = page.top
                        strokeScale = scale
                        sampleCount = 0
                        stream.reset()
                        addSample(event.getX(i), event.getY(i))
                    }
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val j = event.findPointerIndex(activeId)
                if (j >= 0) {
                    for (h in 0 until event.historySize) addSample(event.getHistoricalX(j, h), event.getHistoricalY(j, h))
                    addSample(event.getX(j), event.getY(j))
                    sendLive(false)
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val i = event.actionIndex
                val pointer = event.getPointerId(i)
                if (pointer == tapId) {
                    tapId = -1
                    val canceled = (event.flags and FLAG_CANCELED) != 0
                    if (!canceled && drawingAllowed && hypot(event.getX(i) - tapX, event.getY(i) - tapY) < slop) {
                        if (tapsTitle) onTitle() else onNote((tapX - page.left) / scale, (tapY - page.top) / scale)
                    }
                } else if (pointer == activeId) {
                    val shown = sheet
                    if ((event.flags and FLAG_CANCELED) != 0) {
                        dropStroke() // the system took the touch back (palm rejection): no stroke
                    } else if (shown.number != strokeSheet.number || shown.width != strokeSheet.width || shown.height != strokeSheet.height) {
                        dropStroke()
                        flash("sheet changed")
                    } else if (drawingAllowed) {
                        finishStroke(shown)
                    } else {
                        dropStroke() // the desktop stopped taking strokes meanwhile: clear its live ink
                    }
                    activeId = -1
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                dropStroke()
                tapId = -1
            }
        }
        invalidate()
        return true
    }

    private fun finishStroke(shown: Sheet) {
        if (strokeTool == Tool.PEN) {
            val tenths = encodeStroke(samples, sampleCount, shown.width, shown.height)
            val id = Link.send { strokeLine(it, tenths) }
            Log.i(TAG, "stroke $id sent, ${tenths.size / 2} points")
            pending.add(id, shown.number, Stroke(shown.penWidth, FloatArray(tenths.size) { tenths[it] / 10f }))
        } else {
            val rest = stream.next(samples, sampleCount, shown.width, shown.height)
            Link.send { eraseLine(it, rest, true) }
        }
    }

    /** The new points go to the desktop at most every LIVE_EVERY ms, so it shows the stroke or the erasing as it happens. */
    private fun sendLive(force: Boolean) {
        val now = SystemClock.uptimeMillis()
        if (force || now - streamedAt >= LIVE_EVERY) {
            val chunk = stream.next(samples, sampleCount, strokeSheet.width, strokeSheet.height)
            if (chunk.isNotEmpty()) {
                streamedAt = now
                Link.sendLoose(if (strokeTool == Tool.PEN) inkLine(chunk) else eraseLine(null, chunk, false))
            }
        }
    }

    /** Ends the stroke in progress without adding it: the desktop clears its live ink, or keeps what the eraser did. */
    private fun dropStroke() {
        if (activeId >= 0 && stream.points > 0) {
            if (strokeTool == Tool.PEN) Link.sendLoose(inkLine(IntArray(0))) else Link.send { eraseLine(it, IntArray(0), true) }
        }
        activeId = -1
    }

    // Fits the page into the view with a 12 dp margin, centred.
    private fun place() {
        val margin = 12 * resources.displayMetrics.density
        scale = min((width - 2 * margin) / sheet.width, (height - 2 * margin) / sheet.height)
        val left = (width - sheet.width * scale) / 2
        val top = (height - sheet.height * scale) / 2
        page.set(left, top, left + sheet.width * scale, top + sheet.height * scale)
        if (Build.VERSION.SDK_INT >= 29) {
            // The back gesture must not take strokes that start near a side of the screen.
            systemGestureExclusionRects = listOf(Rect().also { page.roundOut(it) })
        }
    }

    private fun addSample(x: Float, y: Float) {
        if (sampleCount + 2 > samples.size) samples = samples.copyOf(2 * samples.size)
        samples[sampleCount] = (x - strokeLeft) / strokeScale
        samples[sampleCount + 1] = (y - strokeTop) / strokeScale
        sampleCount += 2
    }

    // The desktop's traceStroke: quadratic curves through the segment midpoints; one point is a dot.
    private fun trace(path: Path, p: FloatArray, count: Int, width: Float) {
        path.reset()
        if (count == 2) {
            path.addCircle(p[0], p[1], width / 2, Path.Direction.CW)
        } else {
            path.moveTo(p[0], p[1])
            for (i in 2 until count - 2 step 2) path.quadTo(p[i], p[i + 1], (p[i] + p[i + 2]) / 2, (p[i + 1] + p[i + 3]) / 2)
            path.lineTo(p[count - 2], p[count - 1])
        }
    }

    private fun drawInk(canvas: Canvas, path: Path, width: Float, count: Int) {
        ink.strokeWidth = width
        ink.style = if (count == 2) Paint.Style.FILL else Paint.Style.STROKE
        canvas.drawPath(path, ink)
    }

    private fun line(width: Float, color: Int): Paint {
        linePaint.strokeWidth = width
        linePaint.color = color
        return linePaint
    }

    private fun flash(text: String) {
        notice = text.uppercase()
        noticeUntil = SystemClock.uptimeMillis() + 2500
        postInvalidateDelayed(2500)
    }

    private fun textPaint(size: Float, bold: Boolean, spacing: Float, color: Int) =
        TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG or Paint.LINEAR_TEXT_FLAG).apply {
            typeface = if (bold) Typeface.create(Typeface.MONOSPACE, Typeface.BOLD) else Typeface.MONOSPACE
            textSize = size
            letterSpacing = spacing
            this.color = color
        }
}

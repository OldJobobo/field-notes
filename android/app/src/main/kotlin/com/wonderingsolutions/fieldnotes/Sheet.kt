package com.wonderingsolutions.fieldnotes

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

// The open sheet and protocol v1 (NDJSON) with the desktop bridge. Pure Kotlin and org.json, so
// the JVM tests run it as the phone does. Sheet coordinates are in sheet units throughout.

class Stroke(val width: Float, val points: FloatArray)

class Note(val x: Float, val y: Float, val width: Float, val height: Float, val text: String, val size: Float) {
    /** Laid out like the desktop's notes: JetBrains Mono advances 0.6 em, wrapped within width − 8. */
    val lines = wrapNote(text, max(1, floor((width - 8.0) / (0.6 * size)).toInt()))
}

class Sheet(
    val number: Int,
    val count: Int,
    val title: String,
    val paper: String,
    val width: Int,
    val height: Int,
    val penWidth: Float,
    val strokes: List<Stroke>,
    val notes: List<Note>,
) {
    companion object {
        val BLANK = Sheet(1, 1, "", "graph", 760, 560, 2.5f, emptyList(), emptyList())
    }
}

sealed interface Message
class SheetMessage(val sheet: Sheet, val settled: Long) : Message
class Desk(val ok: Boolean, val open: Boolean, val saved: String, val message: String) : Message
class Failure(val id: Long?, val message: String) : Message
object Unpaired : Message
object Other : Message

/** Never sent by the bridge: Link posts it when a connection ends or can't be made. */
object Offline : Message

/**
 * One line from the bridge. Every field is read with an explicit type check: Android's org.json
 * and the JVM jar the tests use coerce nulls and numbers differently.
 */
fun parseMessage(line: String): Message {
    val o = try {
        JSONObject(line)
    } catch (e: JSONException) {
        JSONObject()
    }
    return when (o.opt("t") as? String) {
        "sheet" -> {
            val strokes = ArrayList<Stroke>()
            val notes = ArrayList<Note>()
            val objects = o.opt("objects") as? JSONArray ?: JSONArray()
            for (i in 0 until objects.length()) {
                val item = objects.opt(i)
                if (item is JSONObject) {
                    val points = item.opt("points")
                    when (item.opt("type") as? String) {
                        "stroke" -> if (points is JSONArray && points.length() >= 2 && points.length() % 2 == 0) {
                            val values = FloatArray(points.length()) { (points.opt(it) as? Number)?.toFloat() ?: Float.NaN }
                            if (values.all { it.isFinite() }) strokes.add(Stroke(number(item, "width", 2.5).toFloat(), values))
                        }
                        "text" -> notes.add(
                            Note(
                                number(item, "x", 0.0).toFloat(),
                                number(item, "y", 0.0).toFloat(),
                                number(item, "width", 0.0).toFloat(),
                                number(item, "height", 0.0).toFloat(),
                                text(item, "text"),
                                number(item, "size", 16.0).toFloat(),
                            ),
                        )
                    }
                }
            }
            val sheet = Sheet(
                number = number(o, "sheet", 1.0).toInt(),
                count = number(o, "sheets", 1.0).toInt(),
                title = text(o, "title"),
                paper = text(o, "paper"),
                width = number(o, "width", 760.0).toInt(),
                height = number(o, "height", 560.0).toInt(),
                penWidth = number(o, "penWidth", 2.5).toFloat(),
                strokes = strokes,
                notes = notes,
            )
            SheetMessage(sheet, number(o, "settled", 0.0).toLong())
        }
        "desk" -> Desk(o.opt("ok") == true, o.opt("open") == true, text(o, "saved"), text(o, "message"))
        "error" -> Failure((o.opt("id") as? Number)?.toLong(), text(o, "message"))
        "unpaired" -> Unpaired
        else -> Other
    }
}

private fun number(o: JSONObject, key: String, default: Double): Double {
    val value = o.opt(key)
    return if (value is Number && value.toDouble().isFinite()) value.toDouble() else default
}

private fun text(o: JSONObject, key: String): String = o.opt(key) as? String ?: ""

/** A sample in integer tenths of a sheet unit, half up like JS Math.round (kotlin.math.round is half-even), clamped to the page. */
private fun toTenths(value: Float, limit: Int) = floor(value * 10.0 + 0.5).toInt().coerceIn(0, limit * 10)

/**
 * Pen samples (the first `count` values of [x0, y0, x1, y1, …]) as the desktop would store the
 * stroke, in integer tenths of a sheet unit, so that what the phone shows is what the sheet gets.
 */
fun encodeStroke(samples: FloatArray, count: Int, width: Int, height: Int): IntArray {
    // Repeats dropped.
    val tenths = IntArray(count + 2)
    var n = 0
    for (p in 0 until count / 2) {
        val x = toTenths(samples[2 * p], width)
        val y = toTenths(samples[2 * p + 1], height)
        if (n == 0 || x != tenths[n - 2] || y != tenths[n - 1]) {
            tenths[n] = x
            tenths[n + 1] = y
            n += 2
        }
    }
    // A tap still makes a stroke, as on the desktop, which adds a point 0.1 away.
    if (n == 2) {
        tenths[2] = min(tenths[0] + 1, width * 10)
        tenths[3] = min(tenths[1] + 1, height * 10)
        n = 4
    }
    // Ramer–Douglas–Peucker as the desktop simplifies its own pen (Geometry.js): a point stays if it
    // lies more than 3.5 tenths from the segment (not the line) between the points kept around it.
    val points = n / 2
    val keep = BooleanArray(points) { it == 0 || it == points - 1 }
    val ranges = if (points > 2) arrayListOf(0, points - 1) else arrayListOf()
    while (ranges.isNotEmpty()) {
        val last = ranges.removeAt(ranges.size - 1)
        val first = ranges.removeAt(ranges.size - 1)
        val sx = tenths[2 * first].toDouble()
        val sy = tenths[2 * first + 1].toDouble()
        val vx = tenths[2 * last] - sx
        val vy = tenths[2 * last + 1] - sy
        val lengthSquared = vx * vx + vy * vy
        var farthest = -1
        var farthestDistance = 3.5
        for (i in first + 1 until last) {
            val px = tenths[2 * i] - sx
            val py = tenths[2 * i + 1] - sy
            val t = if (lengthSquared == 0.0) 0.0 else ((px * vx + py * vy) / lengthSquared).coerceIn(0.0, 1.0)
            val distance = sqrt((px - t * vx) * (px - t * vx) + (py - t * vy) * (py - t * vy))
            if (distance > farthestDistance) {
                farthest = i
                farthestDistance = distance
            }
        }
        if (farthest >= 0) {
            keep[farthest] = true
            ranges += listOf(first, farthest, farthest, last)
        }
    }
    // The desktop takes at most 8192 points in a stroke.
    val stroke = IntArray(2 * min(keep.count { it }, 8192))
    var j = 0
    for (i in 0 until points) {
        if (keep[i] && j < stroke.size) {
            stroke[j] = tenths[2 * i]
            stroke[j + 1] = tenths[2 * i + 1]
            j += 2
        }
    }
    return stroke
}

/** Tenths printed with a decimal point: 900 is 90.0 and 406 is 40.6. */
private fun printTenths(line: StringBuilder, tenths: Int) {
    line.append(tenths / 10).append('.').append(tenths % 10)
}

private fun pointsJson(tenths: IntArray) = StringBuilder("[").also {
    for (i in tenths.indices) {
        if (i > 0) it.append(',')
        printTenths(it, tenths[i])
    }
}.append(']')

/** The `stroke` line, each value printed from its tenths. */
fun strokeLine(id: Long, tenths: IntArray) = """{"t":"stroke","id":$id,"points":${pointsJson(tenths)}}"""

/** The new points of the stroke being drawn, so the desktop shows it live; no points clears it. */
fun inkLine(tenths: IntArray) = """{"t":"ink","points":${pointsJson(tenths)}}"""

/** The new points of an eraser drag. The last chunk (`end`) is a command and has an id. */
fun eraseLine(id: Long?, tenths: IntArray, end: Boolean) =
    """{"t":"erase",${if (id != null) "\"id\":$id," else ""}"points":${pointsJson(tenths)},"end":$end}"""

/** The pen width, in tenths. */
fun widthLine(id: Long, tenths: Int) = """{"t":"width","id":$id,"value":${StringBuilder().also { printTenths(it, tenths) }}}"""

fun selectLine(id: Long, sheet: Int) = """{"t":"select","id":$id,"sheet":$sheet}"""

fun titleLine(id: Long, text: String) = """{"t":"title","id":$id,"text":${JSONObject.quote(text)}}"""

/** A typed note with its top-left at (x, y), in tenths of a sheet unit. */
fun noteLine(id: Long, x: Int, y: Int, text: String) =
    """{"t":"note","id":$id,"x":${StringBuilder().also { printTenths(it, x) }},"y":${StringBuilder().also { printTenths(it, y) }},"text":${JSONObject.quote(text)}}"""

fun helloLine(token: String) = """{"t":"hello","v":1,"token":${JSONObject.quote(token)}}"""

/** `undo`, `redo`, `show`, `clear` and `new`. */
fun commandLine(type: String, id: Long) = """{"t":"$type","id":$id}"""

/**
 * A note's lines as Qt wraps them on the desktop (WrapAtWordBoundaryOrAnywhere): `\n` breaks,
 * then a line longer than `maxChars` breaks at its last space that fits, or mid-word if none does.
 * Spaces at a break hang off the end of the line, so the next line starts at the next word.
 */
fun wrapNote(text: String, maxChars: Int): List<String> {
    val lines = ArrayList<String>()
    for (paragraph in text.split('\n')) {
        var start = 0
        while (paragraph.length - start > maxChars) {
            val space = paragraph.lastIndexOf(' ', start + maxChars)
            if (space > start) {
                lines.add(paragraph.substring(start, space))
                start = space + 1
                while (start < paragraph.length && paragraph[start] == ' ') start++
            } else {
                lines.add(paragraph.substring(start, start + maxChars))
                start += maxChars
            }
        }
        lines.add(paragraph.substring(start))
    }
    return lines
}

/**
 * What a pen drag has not yet told the desktop, in tenths like encodeStroke's first step (repeats
 * dropped). Past MAX_LIVE_POINTS it says nothing more: the stroke still arrives whole when the pen lifts.
 */
class Stream {
    private var read = 0 // values of the samples already looked at
    private var lastX = -1
    private var lastY = -1
    var points = 0
        private set

    fun reset() {
        read = 0
        lastX = -1
        lastY = -1
        points = 0
    }

    fun next(samples: FloatArray, count: Int, width: Int, height: Int): IntArray {
        val chunk = ArrayList<Int>()
        while (read + 1 < count && points < MAX_LIVE_POINTS) {
            val x = toTenths(samples[read], width)
            val y = toTenths(samples[read + 1], height)
            if (x != lastX || y != lastY) {
                chunk.add(x)
                chunk.add(y)
                points++
                lastX = x
                lastY = y
            }
            read += 2
        }
        return chunk.toIntArray()
    }

    companion object {
        const val MAX_LIVE_POINTS = 8000
    }
}

class PendingStroke(val id: Long, val sheet: Int, val stroke: Stroke)

/**
 * Strokes sent to the desktop that no sheet has shown yet, drawn meanwhile so the pen feels
 * immediate. A sheet reflects every command of its connection up to its `settled` id (or that
 * command failed with an error), so those strokes are in it now and drop out of here.
 */
class Pending {
    private val strokes = ArrayList<PendingStroke>()

    fun add(id: Long, sheet: Int, stroke: Stroke) {
        strokes.add(PendingStroke(id, sheet, stroke))
    }

    fun settle(settled: Long) {
        strokes.removeAll { it.id <= settled }
    }

    fun fail(id: Long) {
        strokes.removeAll { it.id == id }
    }

    /** Each shows only on the sheet it was drawn on: the desktop may switch sheets meanwhile. */
    fun visible(sheet: Int): List<Stroke> = strokes.filter { it.sheet == sheet }.map { it.stroke }

    /** Undo takes the newest visible stroke back at once; the next sheet confirms it. */
    fun undo(sheet: Int) {
        strokes.lastOrNull { it.sheet == sheet }?.let { strokes.remove(it) }
    }

    fun clear() {
        strokes.clear()
    }
}

package com.wonderingsolutions.fieldnotes

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.json.JSONArray
import org.junit.Test
import java.io.File

class SheetTest {
    private fun encode(vararg samples: Float, width: Int = 760, height: Int = 560) = encodeStroke(samples, samples.size, width, height)

    @Test
    fun parsesTheSheetFixture() {
        val message = parseMessage(File("../../bridge/testdata/sheet.json").readText()) as SheetMessage
        assertEquals(0L, message.settled)
        val sheet = message.sheet
        assertEquals(2, sheet.number)
        assertEquals(2, sheet.count)
        assertEquals("Meeting notes", sheet.title)
        assertEquals("ruled", sheet.paper)
        assertEquals(1040, sheet.width)
        assertEquals(760, sheet.height)
        assertEquals(4f, sheet.penWidth, 0f)

        assertEquals(2, sheet.strokes.size)
        assertEquals(2.5f, sheet.strokes[0].width, 0f)
        assertArrayEquals(floatArrayOf(90f, 140f, 200.5f, 110.3f, 262f, 40.6f), sheet.strokes[0].points, 0f)
        assertEquals(7f, sheet.strokes[1].width, 0f)
        assertArrayEquals(floatArrayOf(500.1f, 600.9f), sheet.strokes[1].points, 0f)

        assertEquals(2, sheet.notes.size)
        val first = sheet.notes[0]
        assertEquals(90f, first.x, 0f)
        assertEquals(200f, first.y, 0f)
        assertEquals(220f, first.width, 0f)
        assertEquals(40f, first.height, 0f)
        assertEquals("Call back\nÁgua — 5 €", first.text)
        assertEquals(16f, first.size, 0f)
        assertEquals(listOf("Call back", "Água — 5 €"), first.lines)
        val second = sheet.notes[1]
        assertEquals(300f, second.x, 0f)
        assertEquals(400f, second.y, 0f)
        assertEquals(220f, second.width, 0f)
        assertEquals(28f, second.height, 0f)
        assertEquals("no size given", second.text)
        assertEquals(16f, second.size, 0f)
    }

    @Test
    fun parsesDeskErrorAndUnpaired() {
        val desk = parseMessage("""{"t":"desk","ok":true,"open":false,"saved":"SAVED","message":""}""") as Desk
        assertTrue(desk.ok)
        assertFalse(desk.open)
        assertEquals("SAVED", desk.saved)
        assertEquals("", desk.message)
        val down = parseMessage("""{"t":"desk","ok":false,"open":false,"saved":"","message":"omarchy-shell is not running"}""") as Desk
        assertFalse(down.ok)
        assertEquals("omarchy-shell is not running", down.message)

        val failure = parseMessage("""{"t":"error","id":7,"message":"the notebook is full"}""") as Failure
        assertEquals(7L, failure.id)
        assertEquals("the notebook is full", failure.message)
        assertNull((parseMessage("""{"t":"error","id":null,"message":"not JSON"}""") as Failure).id)

        assertSame(Unpaired, parseMessage("""{"t":"unpaired"}"""))
        assertSame(Other, parseMessage("""{"t":"later","x":1}"""))
        assertSame(Other, parseMessage("not json"))
        assertSame(Other, parseMessage("[1, 2]"))
    }

    @Test
    fun readsFieldsOnlyWhenTheirTypeIsRight() {
        val message = parseMessage(
            """{"t":"sheet","settled":"3","sheet":true,"sheets":null,"title":5,"paper":"dots","width":520,"height":380,
            "penWidth":"4","objects":[{"type":"stroke","width":3,"points":[1,2,"3",4]},{"type":"stroke","width":3,"points":[1,2,3]},
            {"type":"text","x":1,"y":2,"width":30,"height":20,"text":"hi","size":false},{"type":"sticker"},7]}""",
        ) as SheetMessage
        assertEquals(0L, message.settled)
        val sheet = message.sheet
        assertEquals(1, sheet.number)
        assertEquals(1, sheet.count)
        assertEquals("", sheet.title)
        assertEquals("dots", sheet.paper)
        assertEquals(520, sheet.width)
        assertEquals(380, sheet.height)
        assertEquals(2.5f, sheet.penWidth, 0f)
        assertTrue(sheet.strokes.isEmpty())
        assertEquals(1, sheet.notes.size)
        assertEquals(16f, sheet.notes[0].size, 0f)

        assertNull((parseMessage("""{"t":"error","id":"7","message":"x"}""") as Failure).id)
        assertFalse((parseMessage("""{"t":"desk","ok":"true","open":1,"saved":null,"message":false}""") as Desk).ok)
    }

    @Test
    fun writesTheStrokeFixtureLine() {
        assertEquals(File("../../bridge/testdata/stroke.json").readText(), strokeLine(7, intArrayOf(900, 1400, 2005, 1103, 2620, 406)) + "\n")
    }

    @Test
    fun writesHelloAndCommands() {
        assertEquals("""{"t":"hello","v":1,"token":"k3y_-A9"}""", helloLine("k3y_-A9"))
        assertEquals("""{"t":"hello","v":1,"token":""}""", helloLine(""))
        assertEquals("""{"t":"undo","id":8}""", commandLine("undo", 8))
        assertEquals("""{"t":"show","id":12}""", commandLine("show", 12))
    }

    @Test
    fun writesEveryLineOfTheCommandsFixture() {
        val none = IntArray(0)
        val expected = JSONArray(File("../../bridge/testdata/commands.json").readText())
        val written = mapOf(
            "ink" to inkLine(intArrayOf(900, 1400, 2005, 1103)),
            "ink-more" to inkLine(intArrayOf(2620, 406)),
            "ink-clear" to inkLine(none),
            "erase" to eraseLine(null, intArrayOf(100, 200, 305, 400), false),
            "erase-end" to eraseLine(8, intArrayOf(500, 600), true),
            "width" to widthLine(9, 40),
            "clear" to commandLine("clear", 10),
            "select" to selectLine(11, 2),
            "new" to commandLine("new", 12),
            "title" to titleLine(13, "Meeting notes"),
            "note" to noteLine(14, 900, 2000, "Call back\nÁgua"),
            "undo" to commandLine("undo", 15),
            "redo" to commandLine("redo", 16),
            "show" to commandLine("show", 17),
        )
        assertEquals(written.size, expected.length())
        for (i in 0 until expected.length()) {
            val entry = expected.getJSONObject(i)
            assertEquals(entry.getString("name"), entry.getString("line"), written[entry.getString("name")])
        }
    }

    @Test
    fun streamsOnlyThePointsNotYetSent() {
        val stream = Stream()
        val samples = floatArrayOf(90f, 140f, 90.01f, 140.01f, 200.5f, 110.3f, 262f, 40.6f)
        assertArrayEquals(intArrayOf(900, 1400, 2005, 1103), stream.next(samples, 6, 760, 560)) // the repeat at 90.01 is dropped
        assertArrayEquals(intArrayOf(), stream.next(samples, 6, 760, 560))
        assertArrayEquals(intArrayOf(2620, 406), stream.next(samples, 8, 760, 560))
        assertEquals(3, stream.points)
        stream.reset()
        assertArrayEquals(intArrayOf(900, 1400), stream.next(samples, 2, 760, 560))
    }

    @Test
    fun streamsAtMost8000Points() {
        val stream = Stream()
        val samples = FloatArray(2 * 9000) { it / 2 * 0.1f }
        assertEquals(2 * Stream.MAX_LIVE_POINTS, stream.next(samples, samples.size, 1040, 760).size)
        assertEquals(0, stream.next(samples, samples.size, 1040, 760).size)
    }

    @Test
    fun roundsHalfUpLikeTheDesktop() {
        // kotlin.math.round would give 102, 2, 508, 402: half to even.
        assertArrayEquals(intArrayOf(103, 3, 508, 403), encode(10.25f, 0.25f, 50.75f, 40.25f))
    }

    @Test
    fun clampsToThePage() {
        assertArrayEquals(intArrayOf(0, 0, 7600, 5600), encode(-5f, -0.04f, 800f, 600f))
        assertArrayEquals(intArrayOf(100, 100, 5200, 3800), encode(10f, 10f, 600f, 400f, width = 520, height = 380))
    }

    @Test
    fun dropsRepeatedPoints() {
        assertArrayEquals(intArrayOf(100, 100, 200, 200), encode(10f, 10f, 10.01f, 10.02f, 10f, 10f, 20f, 20f, 20.04f, 19.96f))
    }

    @Test
    fun readsOnlyTheSamplesCounted() {
        assertArrayEquals(intArrayOf(100, 200, 300, 400), encodeStroke(floatArrayOf(10f, 20f, 30f, 40f, 99f, 99f), 4, 760, 560))
    }

    @Test
    fun aStillTapMakesTwoPoints() {
        assertArrayEquals(intArrayOf(100, 200, 101, 201), encode(10f, 20f))
        assertArrayEquals(intArrayOf(100, 200, 101, 201), encode(10f, 20f, 10.02f, 19.98f, 10f, 20f))
        // At the page's right edge the second point is clamped back onto it.
        assertArrayEquals(intArrayOf(7600, 3000, 7600, 3001), encode(760f, 300f))
    }

    // The expected points in the next three tests come from the desktop's own Geometry.simplifyStroke,
    // run once with node on the same points in sheet units with tolerance 0.35.

    @Test
    fun simplifiesAClosedLoop() {
        val loop = encode(
            100f, 100f, 110f, 100.1f, 120f, 99.9f, 130f, 100.5f, 140f, 100f, 150f, 100.2f, 160f, 100f,
            160.1f, 110f, 159.9f, 120f, 160f, 130f, 150f, 130.1f, 140f, 129.8f, 130f, 130f, 120f, 130.1f,
            110f, 130f, 100f, 130f, 99.9f, 120f, 100.2f, 110f, 100f, 100f,
        )
        assertArrayEquals(intArrayOf(1000, 1000, 1200, 999, 1300, 1005, 1600, 1000, 1600, 1300, 1000, 1300, 1000, 1000), loop)
    }

    @Test
    fun keepsTheTipOfAHook() {
        // (140, 100) is 0.32 from the line through the ends, but 15 from the segment between them.
        val hook = encode(100f, 100f, 110f, 100f, 120f, 100f, 130f, 100f, 140f, 100f, 135f, 100.1f, 130f, 100.2f, 125f, 100.2f)
        assertArrayEquals(intArrayOf(1000, 1000, 1400, 1000, 1250, 1002), hook)
    }

    @Test
    fun keepsAtMost8192Points() {
        // A zigzag of 9000 points, 10 wide and 1 down a step, in columns of 500: none simplifies away.
        val zigzag = FloatArray(18000) { i ->
            val p = i / 2
            if (i % 2 == 0) 10f + 30 * (p / 500) + 10 * (p % 2) else 10f + p % 500
        }
        val stroke = encodeStroke(zigzag, zigzag.size, 760, 560)
        assertArrayEquals(IntArray(16384) { (zigzag[it] * 10).toInt() }, stroke)
    }

    @Test
    fun wrapsNotesLikeTheDesktop() {
        assertEquals(listOf("the quick", "brown fox", "jumps"), wrapNote("the quick brown fox jumps", 10))
        assertEquals(listOf("exactly 10"), wrapNote("exactly 10", 10))
        assertEquals(listOf("abcde", "fghij", "kl"), wrapNote("abcdefghijkl", 5))
        assertEquals(listOf("hi", "abcde", "fghij", "kl"), wrapNote("hi abcdefghijkl", 5))
        assertEquals(listOf("abcde", "fg"), wrapNote("abcde   fg", 5))
        assertEquals(listOf("a", "", "b", ""), wrapNote("a\n\nb\n", 5))
        // (104 − 8) / (0.6 × 16) is exactly 10 characters; and a sliver of a note still fits one.
        assertEquals(listOf("0123456789", "abc"), Note(0f, 0f, 104f, 28f, "0123456789abc", 16f).lines)
        assertEquals(listOf("a", "b"), Note(0f, 0f, 8f, 28f, "ab", 16f).lines)
    }

    @Test
    fun reconcilesPendingStrokes() {
        val pending = Pending()
        val a = Stroke(2.5f, floatArrayOf(1f, 1f, 2f, 2f))
        val b = Stroke(2.5f, floatArrayOf(3f, 3f, 4f, 4f))
        val c = Stroke(4f, floatArrayOf(5f, 5f, 6f, 6f))
        pending.add(1, 1, a)
        pending.add(2, 1, b)
        pending.add(4, 2, c)
        assertEquals(listOf(a, b), pending.visible(1))
        assertEquals(listOf(c), pending.visible(2))

        pending.settle(1)
        assertEquals(listOf(b), pending.visible(1))
        pending.fail(4)
        assertTrue(pending.visible(2).isEmpty())

        val d = Stroke(2.5f, floatArrayOf(7f, 7f, 8f, 8f))
        val e = Stroke(2.5f, floatArrayOf(9f, 9f, 10f, 10f))
        pending.add(5, 2, d)
        pending.add(6, 1, e)
        pending.undo(2) // the newest visible stroke on sheet 2, not the newer one on sheet 1
        assertTrue(pending.visible(2).isEmpty())
        assertEquals(listOf(b, e), pending.visible(1))

        pending.settle(6)
        assertTrue(pending.visible(1).isEmpty())
        pending.add(7, 1, a)
        pending.clear()
        assertTrue(pending.visible(1).isEmpty())
    }
}

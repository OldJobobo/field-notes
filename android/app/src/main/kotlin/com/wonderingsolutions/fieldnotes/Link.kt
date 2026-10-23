package com.wonderingsolutions.fieldnotes

import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.EOFException
import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.Executors

const val TAG = "FieldNotes"

/**
 * The connection to the desktop bridge, through the abstract socket @fieldnotes-bridge that
 * `adb reverse` forwards to the desktop: nothing listens on the phone's network. Called on the
 * main thread; each session reads and writes on threads of its own.
 */
object Link {
    private var current: Session? = null

    // One counter for the app's whole life: strokes and commands share it, reconnects don't reset it.
    private var lastId = 0L

    val running get() = current != null

    /** (Re)connects with `token`, handing every message to `onMessage` on the main thread. */
    fun start(token: String, onMessage: (Message) -> Unit) {
        stop()
        current = Session(token, onMessage).also { it.start() }
    }

    fun stop() {
        val session = current
        current = null
        session?.close()
    }

    /** Sends the line `line` makes for a fresh id, and returns the id. Dropped while not connected. */
    fun send(line: (Long) -> String): Long {
        lastId += 1
        current?.send(line(lastId))
        return lastId
    }

    /** Sends a line that is no command, so it takes no id (live ink). Dropped while not connected. */
    fun sendLoose(line: String) {
        current?.send(line)
    }

    private class Session(private val token: String, private val onMessage: (Message) -> Unit) : Thread("FieldNotes reader") {
        @Volatile private var closed = false
        @Volatile private var socket: LocalSocket? = null

        // Set only once hello is queued, so hello is the first line on every connection.
        @Volatile private var output: OutputStream? = null
        private val writer = Executors.newSingleThreadExecutor { Thread(it, "FieldNotes writer") }
        private val main = Handler(Looper.getMainLooper())

        fun send(line: String) {
            val out = output
            if (!closed && out != null) write(out, line)
        }

        fun close() {
            closed = true
            socket?.close() // unblocks connect and read
            interrupt() // cuts the retry sleep short
            writer.shutdownNow()
        }

        override fun run() {
            while (!closed) {
                var unpaired = false
                try {
                    LocalSocket().use { connection ->
                        socket = connection
                        // The abstract namespace is the default; the connect overload with a timeout
                        // throws UnsupportedOperationException.
                        connection.connect(LocalSocketAddress("fieldnotes-bridge"))
                        // The bridge sends desk every 2 s, so 6 s of silence is a dead connection.
                        connection.soTimeout = 6000
                        Log.i(TAG, "connected")
                        val out = connection.outputStream
                        write(out, helloLine(token))
                        output = out
                        val lines = connection.inputStream.bufferedReader()
                        while (!closed && !unpaired) {
                            val message = parseMessage(lines.readLine() ?: throw EOFException("the bridge closed the connection"))
                            when (message) {
                                is SheetMessage -> Log.i(TAG, "sheet ${message.sheet.number} received, ${message.sheet.strokes.size + message.sheet.notes.size} objects")
                                is Failure -> Log.w(TAG, "error for command ${message.id}: ${message.message}")
                                Unpaired -> Log.w(TAG, "not paired with this desktop")
                                else -> {}
                            }
                            unpaired = message === Unpaired
                            post(message)
                        }
                    }
                } catch (e: Exception) {
                    Log.i(TAG, "disconnected: $e")
                    post(Offline)
                }
                output = null
                // Pairing takes `make run` on the desktop, so an unpaired phone asks again less often.
                try {
                    sleep(if (unpaired) 5000L else 1000L)
                } catch (e: InterruptedException) {
                    // stop(): the loop ends.
                }
            }
        }

        private fun write(out: OutputStream, line: String) {
            writer.execute {
                try {
                    out.write("$line\n".toByteArray())
                } catch (e: IOException) {
                    Log.w(TAG, "send failed: $e") // the reader sees the connection end and reconnects
                }
            }
        }

        private fun post(message: Message) {
            main.post { if (current === this) onMessage(message) }
        }
    }
}

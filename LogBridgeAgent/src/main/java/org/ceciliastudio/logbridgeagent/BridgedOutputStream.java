package org.ceciliastudio.logbridgeagent;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.channels.SocketChannel;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.TimeUnit;

public class BridgedOutputStream extends OutputStream {
    private static final int DEFAULT_QUEUE_CAPACITY = 4096;

    private final SocketChannel channel;
    private final OutputStream standardOutputStream;
    private final boolean isError;

    private final Object lock;
    private final ByteArrayOutputStream lineBuffer;

    private final BlockingQueue<byte[]> outbound;

    private volatile boolean degraded;

    public BridgedOutputStream(SocketChannel channel, OutputStream standardOutputStream, boolean isError) throws IOException {
        this.channel = channel;
        this.standardOutputStream = standardOutputStream;
        this.isError = isError;

        this.lock = new Object();

        this.lineBuffer = new ByteArrayOutputStream(256);

        ArrayBlockingQueue<byte[]> outbound = new ArrayBlockingQueue<>(DEFAULT_QUEUE_CAPACITY);
        this.outbound = outbound;

        this.channel.configureBlocking(true);

        Thread writer = new Thread(() -> runWriter(outbound), "logbridge-writer-" + (isError ? "err" : "out"));
        writer.setDaemon(true);
        writer.start();
    }

    @Override
    public void write(int b) throws IOException {
        int v = b & 0xFF;
        byte[] one = new byte[] { (byte) v };
        this.write(one, 0, 1);
    }

    @Override
    public void write(byte[] b, int off, int len) throws IOException {
        this.standardOutputStream.write(b, off, len);

        if (degraded) return;
        synchronized (this.lock) {
            int index = off;
            int end = off + len;

            while (index < end) {
                int lfIndex = indexOfLf(b, index, end);
                if (lfIndex < 0) {
                    this.lineBuffer.write(b, index, end - index);
                    break;
                }

                int segmentLen = (lfIndex - index) + 1;
                this.lineBuffer.write(b, index, segmentLen);

                byte[] line = this.lineBuffer.toByteArray();
                this.lineBuffer.reset();
                offerOrDrop(frame(line, this.isError));

                index = lfIndex + 1;
            }
        }
    }

    @Override
    public void flush() throws IOException {
        this.standardOutputStream.flush();
        if (this.degraded) {
            return;
        }

        synchronized (this.lock) {
            byte[] pending = this.lineBuffer.toByteArray();
            if (pending.length > 0) {
                this.lineBuffer.reset();
                offerOrDrop(frame(pending, this.isError));
            }
        }
    }

    @Override
    public void close() throws IOException {
        try {
            this.flush();
        } catch (IOException ignored) {}

        this.standardOutputStream.close();
        this.channel.close();
    }

    @SuppressWarnings("ResultOfMethodCallIgnored")
    private void offerOrDrop(byte[] framed) {
        this.outbound.offer(framed);
    }

    private void runWriter(BlockingQueue<byte[]> queue) {
        while (true) {
            if (this.degraded) {
                drain(queue);
                return;
            }

            try {
                byte[] payload = queue.poll(200, TimeUnit.MILLISECONDS);
                if (payload == null) {
                    continue;
                }
                writeFully(this.channel, payload);
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
                return;
            } catch (Exception ignored) {
                degrade();
                return;
            }
        }
    }

    private void degrade() {
        this.degraded = true;
        try {
            this.channel.close();
        } catch (IOException ignored) {}
    }

    private static void drain(BlockingQueue<byte[]> queue) {
        while (queue.poll() != null);
    }

    private static void writeFully(SocketChannel channel, byte[] payload) throws IOException {
        ByteBuffer buf = ByteBuffer.wrap(payload);
        while (buf.hasRemaining()) {
            channel.write(buf);
        }
    }

    private static byte[] frame(byte[] lineBytes, boolean isError) {
        byte[] framed = new byte[lineBytes.length + 1];
        framed[0] = (byte) (isError ? 0x01 : 0x00);
        System.arraycopy(lineBytes, 0, framed, 1, lineBytes.length);
        return framed;
    }

    private static int indexOfLf(byte[] b, int from, int to) {
        for (int i = from; i < to; i++) {
            if (b[i] == (byte) '\n') {
                return i;
            }
        }
        return -1;
    }
}
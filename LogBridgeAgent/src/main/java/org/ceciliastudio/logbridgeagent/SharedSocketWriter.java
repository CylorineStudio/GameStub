package org.ceciliastudio.logbridgeagent;

import java.io.Closeable;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.SocketChannel;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;

public class SharedSocketWriter implements Closeable {
    private static final int DEFAULT_QUEUE_CAPACITY = 4096;

    private final SocketChannel channel;
    private final BlockingQueue<byte[]> payloadQueue;

    private final Thread writerThread;

    private volatile boolean degraded;

    public SharedSocketWriter(SocketChannel channel) throws IOException {
        this.channel = channel;
        this.payloadQueue = new ArrayBlockingQueue<>(DEFAULT_QUEUE_CAPACITY);
        this.channel.configureBlocking(true);

        Thread thread = new Thread(this::runWriter, "logbridge-writer");
        thread.start();
        this.writerThread = thread;
    }

    public void write(byte[] bytes) {
        if (degraded) return;
        offer(bytes);
    }

    private void runWriter() {
        while (true) {
            if (this.degraded) {
                while (this.payloadQueue.poll() != null) ;
                return;
            }
            
            try {
                byte[] payload = this.payloadQueue.take();
                if (payload.length == 1 && payload[0] == (byte) 0xFC) {
                    return;
                }

                synchronized (this.channel) {
                    ByteBuffer buf = ByteBuffer.wrap(payload);
                    while (buf.hasRemaining()) {
                        this.channel.write(buf);
                    }
                }
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
                return;
            } catch (IOException e) {
                this.degraded = true;
                return;
            }
        }
    }

    @Override
    public void close() throws IOException {
        offer(new byte[] { (byte) 0xFC });
        try {
            if (this.writerThread != null) {
                this.writerThread.join(100);
            }
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        }
        this.channel.close();
    }

    public boolean isDegraded() {
        return this.degraded;
    }

    @SuppressWarnings("ResultOfMethodCallIgnored")
    private void offer(byte[] payload) {
        this.payloadQueue.offer(payload);
    }
}

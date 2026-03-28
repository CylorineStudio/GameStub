package org.ceciliastudio.logbridgeagent;

import java.io.IOException;
import java.io.OutputStream;

public class BridgedOutputStream extends OutputStream {
    private final SharedSocketWriter writer;
    private final OutputStream standardOutputStream;
    private final boolean isError;

    public BridgedOutputStream(SharedSocketWriter writer, OutputStream standardOutputStream, boolean isError) throws IOException {
        this.writer = writer;
        this.standardOutputStream = standardOutputStream;
        this.isError = isError;
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

        byte[] content = new byte[len];
        System.arraycopy(b, off, content, 0, len);
        this.writer.write(payload(content, this.isError));
    }

    @Override
    public void flush() throws IOException {
        this.standardOutputStream.flush();
    }

    private static byte[] payload(byte[] lineBytes, boolean isError) {
        byte[] framed = new byte[lineBytes.length + 1];
        framed[0] = (byte) (isError ? 0x01 : 0x00);
        System.arraycopy(lineBytes, 0, framed, 1, lineBytes.length);
        return framed;
    }
}

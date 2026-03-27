package org.ceciliastudio.logbridgeagent;

import java.io.IOException;
import java.io.PrintStream;
import java.lang.instrument.Instrumentation;
import java.net.StandardProtocolFamily;
import java.net.UnixDomainSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.SocketChannel;
import java.nio.file.Files;
import java.nio.file.Path;

public class Agent {
    public static void premain(String agentArgs, Instrumentation inst) {
        System.out.println("[GameStub LogBridge] Premain loaded. agentArgs: " + agentArgs);
        Path socketPath = Path.of(agentArgs);
        if (!Files.exists(socketPath)) {
            System.err.println("[GameStub LogBridge] the socket file does not exists: " + socketPath);
            System.exit(40);
        }

        try {
            SocketChannel channel = createSocketChannel(socketPath);
            System.setOut(new PrintStream(new BridgedOutputStream(channel, System.out, false), true));
            System.setErr(new PrintStream(new BridgedOutputStream(channel, System.err, true), true));
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                synchronized (channel) {
                    try {
                        channel.write(ByteBuffer.wrap(new byte[] {(byte) 0xFF}));
                    } catch (IOException ignored) {}
                }
            }));
        } catch (IOException e) {
            System.err.println("[GameStub LogBridge] Failed to create socket: " + e.getMessage());
        }
    }

    private static SocketChannel createSocketChannel(Path path) throws IOException {
        UnixDomainSocketAddress address = UnixDomainSocketAddress.of(path);
        SocketChannel socketChannel = SocketChannel.open(StandardProtocolFamily.UNIX);
        socketChannel.configureBlocking(false);
        socketChannel.connect(address);
        return socketChannel;
    }
}

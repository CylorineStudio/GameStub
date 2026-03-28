package org.ceciliastudio.logbridgeagent;

import java.io.IOException;
import java.io.PrintStream;
import java.lang.instrument.Instrumentation;
import java.net.StandardProtocolFamily;
import java.net.UnixDomainSocketAddress;
import java.nio.channels.SocketChannel;
import java.nio.file.Files;
import java.nio.file.Path;

public class Agent {
    public static void premain(String agentArgs, Instrumentation inst) {
        System.out.println("[GameStub LogBridge] Premain loaded. agentArgs: " + agentArgs);
        if (agentArgs == null) {
            System.err.println("[GameStub LogBridge] agentArgs is null");
            return;
        }
        Path socketPath = Path.of(agentArgs);
        if (!Files.exists(socketPath)) {
            System.err.println("[GameStub LogBridge] The socket file does not exist: " + socketPath);
            System.exit(40);
        }

        try {
            SocketChannel channel = createSocketChannel(socketPath);
            SharedSocketWriter writer = new SharedSocketWriter(channel);
            System.setOut(new PrintStream(new BridgedOutputStream(writer, System.out, false), true));
            System.setErr(new PrintStream(new BridgedOutputStream(writer, System.err, true), true));
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                try {
                    System.out.close();
                    System.err.close();
                    writer.write(new byte[] { (byte) 0xFF });
                    writer.close();
                } catch (IOException ignored) {}
            }));
        } catch (IOException e) {
            System.err.println("[GameStub LogBridge] Failed to create socket: " + e.getMessage());
        }
    }

    private static SocketChannel createSocketChannel(Path path) throws IOException {
        UnixDomainSocketAddress address = UnixDomainSocketAddress.of(path);
        SocketChannel socketChannel = SocketChannel.open(StandardProtocolFamily.UNIX);
        socketChannel.configureBlocking(true);
        socketChannel.connect(address);
        return socketChannel;
    }
}

package org.ceciliastudio.logbridgeagent;

import java.lang.instrument.Instrumentation;

public class Agent {
    public static void premain(String args, Instrumentation inst) {
        System.out.println("[GameStub LogBridge] Premain loaded. args: " + args);
    }
}

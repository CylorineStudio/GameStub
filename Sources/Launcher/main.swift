//
//  main.swift
//  GameStub
//
//  Created by AnemoFlower on 2026/3/6.
//

import Foundation
import AppKit

func log(_ message: String, error: Bool = false) {
    fputs("[GameStub Launcher] \(message)\n", error ? stderr : stdout)
    fflush(error ? stderr : stdout)
}

func makeServerSocket() -> (String, Int32) {
    let dateFormatter: DateFormatter = .init()
    dateFormatter.dateFormat = "yyyy_MM_dd-HH-mm-ss"
    let socketPath: String = "/tmp/gamestub-\(dateFormatter.string(from: .now)).sock"
    unlink(socketPath)
    
    let serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
    if serverSocket < 0 {
        perror("socket")
        log("Unable to relay logs and detect process termination, exiting", error: true)
        exit(1)
    }
    
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    strcpy(&addr.sun_path.0, socketPath)
    let bindResult: Int32 = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    if bindResult != 0 {
        perror("socket")
        log("Unable to relay logs and detect process termination, exiting", error: true)
        close(serverSocket)
        exit(1)
    }
    
    return (socketPath, serverSocket)
}

func acceptWithTimeout(serverSocket: Int32, timeoutMilliseconds: Int32) -> Int32? {
    var pfd: pollfd = .init()
    pfd.fd = serverSocket
    pfd.events = Int16(POLLIN)
    pfd.revents = 0
    
    let rc: Int32 = poll(&pfd, 1, timeoutMilliseconds)
    if rc == 0 {
        return nil // timeout
    }
    if rc < 0 {
        perror("poll")
        return nil
    }
    
    let clientSocket: Int32 = accept(serverSocket, nil, nil)
    if clientSocket < 0 {
        perror("accept")
        return nil
    }
    return clientSocket
}

let (socketPath, serverSocket) = makeServerSocket()

log("Listening for UDS connections: \(socketPath)")
listen(serverSocket, 1)

func startSocket() {
    defer {
        close(serverSocket)
        unlink(socketPath)
    }
    
    guard let clientSocket: Int32 = acceptWithTimeout(serverSocket: serverSocket, timeoutMilliseconds: 10_000) else {
        log("UDS accept timed out after 10s", error: true)
        log("Unable to relay logs and detect process termination, exiting", error: true)
        exit(0)
    }
    log("UDS connection accepted")
    defer { close(clientSocket) }
    
    var lastMessages: [String] = []
    var javaQuitReceived: Bool = false
    
    while true {
        var buffer: [UInt8] = .init(repeating: 0, count: 16384)
        let bytesRead = read(clientSocket, &buffer, buffer.count)
        if bytesRead > 0 {
            if buffer[0] <= 1 {
                if let message: String = .init(bytes: buffer[1..<bytesRead], encoding: .utf8) {
                    if lastMessages.count >= 10 {
                        lastMessages.removeFirst()
                    }
                    lastMessages.append(message)
                    let stream: UnsafeMutablePointer<FILE> = buffer[0] == 0 ? stdout : stderr
                    fputs(message, stream)
                    fflush(stream)
                } else {
                    log("Failed to decode UTF-8 message (bytesRead=\(bytesRead))", error: true)
                }
            } else if buffer[0] == 0xFF {
                javaQuitReceived = true
            }
        } else if bytesRead == 0 {
            if lastMessages.contains(where: { $0.contains("#@!@# Game crashed!") }) {
                log("Game crashed (Minecraft crash log marker detected)")
                exit(1)
            } else if !javaQuitReceived {
                log("JVM terminated unexpectedly (unexpected socket EOF)")
                exit(1)
            }
            exit(0)
        } else {
            perror("read")
            exit(1)
        }
    }
}

let arguments: [String] = ProcessInfo.processInfo.arguments

var appBundleURL: URL = .init(fileURLWithPath: arguments[0])
guard FileManager.default.fileExists(atPath: appBundleURL.path) else {
    log("Executable does not exist: \(arguments[0])", error: true)
    exit(EXIT_FAILURE)
}
while true {
    if appBundleURL.pathComponents.count <= 1 {
        log("App bundle not found (failed to locate a .app bundle in parent directories)", error: true)
        exit(EXIT_FAILURE)
    }
    appBundleURL = appBundleURL.deletingLastPathComponent()
    if appBundleURL.pathExtension == "app" {
        break
    }
}

var runnerArguments: [String] = Array(arguments.dropFirst())
runnerArguments.insert(FileManager.default.currentDirectoryPath, at: 0)
runnerArguments.insert(
    "-javaagent:\(appBundleURL.appending(path: "Contents/Resources/log-bridge-agent.jar").path)=\(socketPath)",
    at: 2
)

let configuration: NSWorkspace.OpenConfiguration = .init()
configuration.createsNewApplicationInstance = true
configuration.activates = false
configuration.arguments = runnerArguments

NSWorkspace.shared.openApplication(at: appBundleURL, configuration: configuration) { application, error in
    if let error {
        log("Failed to launch application: \(error.localizedDescription)", error: true)
        exit(EXIT_FAILURE)
    }
    if let application {
        let pid: Int32 = application.processIdentifier
        log("Application launched successfully (pid=\(pid))")
        
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        
        let termSource: DispatchSourceSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource.setEventHandler {
            log("Received SIGTERM, exiting")
            kill(pid, SIGTERM)
            exit(0)
        }
        termSource.resume()
        
        let intSource: DispatchSourceSignal = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSource.setEventHandler {
            log("Received SIGINT, exiting")
            kill(pid, SIGTERM)
            exit(0)
        }
        intSource.resume()
        log("SIGTERM/SIGINT handlers registered")
        
        DispatchQueue.global(qos: .background).async {
            startSocket()
        }
    }
}
dispatchMain()

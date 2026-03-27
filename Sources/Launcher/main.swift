//
//  main.swift
//  GameStub
//
//  Created by AnemoFlower on 2026/3/6.
//

import Foundation
import AppKit

let dateFormatter: DateFormatter = .init()
dateFormatter.dateFormat = "yyyy_MM_dd-HH-mm-ss"
let socketPath: String = "/tmp/gamestub-\(dateFormatter.string(from: .now)).sock"

unlink(socketPath)

let serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
strcpy(&addr.sun_path.0, socketPath)
withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        _ = bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}

print("[GameStub Launcher] Listening UDS")
listen(serverSocket, 1)

func startSocket() {
    let clientSocket = accept(serverSocket, nil, nil)
    print("[GameStub Launcher] UDS connected")
    while true {
        var buffer: [UInt8] = .init(repeating: 0, count: 1024)
        let bytesRead = read(clientSocket, &buffer, buffer.count)
        if bytesRead > 0 {
            if buffer[0] <= 1 {
                if let message: String = .init(bytes: buffer[1..<bytesRead], encoding: .utf8) {
                    fputs(message, buffer[0] == 0 ? stdout : stderr)
                }
            }
        } else if bytesRead == 0 {
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
    print("[GameStub Launcher] Error: The executable file '\(arguments[0])' not exists")
    exit(EXIT_FAILURE)
}
while true {
    if appBundleURL.pathComponents.count <= 1 {
        print("[GameStub Launcher] Error: App bundle not found")
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

print(runnerArguments)

let configuration: NSWorkspace.OpenConfiguration = .init()
configuration.createsNewApplicationInstance = true
configuration.activates = false
configuration.arguments = runnerArguments

//let process: Process = .init()
//process.executableURL = URL(fileURLWithPath: runnerArguments[0])
//process.arguments = Array(runnerArguments.dropFirst())
//try process.run()

NSWorkspace.shared.openApplication(at: appBundleURL, configuration: configuration) { application, error in
    if let error {
        print("[GameStub Launcher] Error: Application launch failed: \n\(error)")
        exit(EXIT_FAILURE)
    }
    if let application {
        let pid: Int32 = application.processIdentifier
        print("[GameStub Launcher] Application launch successed, PID: \(pid)")
        startSocket()
    }
}
dispatchMain()

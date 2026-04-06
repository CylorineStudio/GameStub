//
//  main.swift
//  GameStub
//
//  Created by AnemoFlower on 2026/3/6.
//

import Foundation
import AppKit

if CommandLine.arguments.count == 1 {
    let alert: NSAlert = .init()
    alert.messageText = "You can't open this app directly."
    alert.alertStyle = .warning
    alert.runModal()
    exit(1)
}

let arguments: [String] = Array(CommandLine.arguments.dropFirst())

var holder: Bool = false
var workingDirectory: String?
var socketPath: String?
var javaArguments: [String]?

for (index, arg) in arguments.enumerated() {
    if arg == "-h" || arg == "--holder" {
        holder = true
    } else if arg == "-w" || arg == "--working-directory" {
        workingDirectory = arguments[index + 1]
    } else if arg == "--socket-path" {
        socketPath = arguments[index + 1]
    } else if arg == "--args" {
        javaArguments = Array(arguments.dropFirst(index + 1))
        break
    }
}

@MainActor
func launch() {
    guard let javaArguments else { exit(1) }
    let executablePath: String = javaArguments[0]
    let argv: [UnsafeMutablePointer<CChar>?] = javaArguments.map { strdup($0) } + [nil]
    argv.withUnsafeBufferPointer { buffer in
        execv(executablePath, buffer.baseAddress)
        perror("execv")
    }
    exit(1)
}

func connectSocket(at path: String) -> Int32? {
    let sockfd: Int32 = socket(AF_UNIX, SOCK_STREAM, 0)
    if sockfd < 0 {
        perror("socket")
        return nil
    }
    
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    
    let bytes = path.utf8CString
    let sunPathCapacity: Int = MemoryLayout.size(ofValue: addr.sun_path)
    
    guard bytes.count <= sunPathCapacity else {
        fputs("socket path too long (len=\(bytes.count), cap=\(sunPathCapacity))\n", stderr)
        close(sockfd)
        return nil
    }
    
    withUnsafeMutablePointer(to: &addr.sun_path) { sunptr in
        let dst = UnsafeMutableRawPointer(sunptr).assumingMemoryBound(to: CChar.self)
        _ = bytes.withUnsafeBufferPointer { src in
            memcpy(dst, src.baseAddress, bytes.count)
        }
    }
    let len = socklen_t(MemoryLayout<sa_family_t>.size + bytes.count)
    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(sockfd, $0, len)
        }
    }
    if result != 0 {
        perror("connect")
        close(sockfd)
        return nil
    }
    return sockfd
}

func send(data: Data, to sockfd: Int32, type: UInt8, queue: DispatchQueue, completion: (@Sendable () -> Void)? = nil) {
    let payload: Data = [type] + data
    queue.async {
        payload.withUnsafeBytes {
            let base = $0.baseAddress?.assumingMemoryBound(to: UInt8.self)
            var written: Int = 0
            while written < payload.count {
                let rc = write(sockfd, base! + written, payload.count - written)
                if rc <= 0 { break }
                written += rc
            }
            completion?()
        }
    }
}

func handlePipe(_ pipe: Pipe, to sockfd: Int32, error: Bool, queue: DispatchQueue) {
    let handle: FileHandle = pipe.fileHandleForReading
    DispatchQueue.global().async {
        while true {
            let data: Data = handle.availableData
            if data.isEmpty { break }
            send(data: data, to: sockfd, type: error ? 1 : 0, queue: queue)
        }
    }
}

class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        launch()
    }
}

guard let javaArguments, javaArguments.count > 2 else {
    exit(1)
}

if holder {
    guard let workingDirectory, let socketPath else {
        exit(1)
    }
    
    guard let sockfd: Int32 = connectSocket(at: socketPath) else {
        exit(1)
    }
    let socketQueue: DispatchQueue = .init(label: "socket_write_queue")
    
    let process: Process = .init()
    process.executableURL = Bundle.main.executableURL
    process.arguments = ["--args"] + javaArguments
    process.currentDirectoryURL = .init(filePath: workingDirectory)
    
    let outputPipe: Pipe = .init()
    let errorPipe: Pipe = .init()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    
    process.terminationHandler = { process in
        let data: Data = withUnsafeBytes(of: process.terminationStatus) { Data($0) }
        send(data: data, to: sockfd, type: 0xFF, queue: socketQueue) {
            exit(process.terminationStatus)
        }
    }
    
    try process.run()
    
    handlePipe(outputPipe, to: sockfd, error: false, queue: socketQueue)
    handlePipe(errorPipe, to: sockfd, error: true, queue: socketQueue)
    
    dispatchMain()
} else {
    let delegate: ApplicationDelegate = .init()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}

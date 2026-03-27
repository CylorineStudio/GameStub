//
//  main.swift
//  GameStub
//
//  Created by AnemoFlower on 2026/3/6.
//

import Foundation
import AppKit

func launch() {
//    var pid: pid_t = 0
    let workingDirectory: String = ProcessInfo.processInfo.arguments[1]
    chdir(workingDirectory)
    let arguments: [String] = Array(ProcessInfo.processInfo.arguments.dropFirst(2))
    let executablePath: String = arguments[0]
    let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
    argv.withUnsafeBufferPointer { buffer in
//        posix_spawn(&pid, executablePath, nil, nil, buffer.baseAddress, nil)
        execv(executablePath, buffer.baseAddress)
        perror("execv")
    }
    exit(EXIT_FAILURE)
}

class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
//        CFRunLoopRunInMode(.defaultMode, 1, true)
//        CFRunLoopRunInMode(.defaultMode, 1, true)
        launch()
    }
}

let delegate: ApplicationDelegate = .init()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()

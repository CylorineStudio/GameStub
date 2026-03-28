//
//  main.swift
//  GameStub
//
//  Created by AnemoFlower on 2026/3/6.
//

import Foundation
import AppKit

func launch() {
    let workingDirectory: String = ProcessInfo.processInfo.arguments[1]
    if chdir(workingDirectory) != 0 {
        perror("chdir")
        exit(EXIT_FAILURE)
    }
    let arguments: [String] = Array(ProcessInfo.processInfo.arguments.dropFirst(2))
    let executablePath: String = arguments[0]
    let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
    argv.withUnsafeBufferPointer { buffer in
        execv(executablePath, buffer.baseAddress)
        perror("execv")
    }
    exit(EXIT_FAILURE)
}

class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        launch()
    }
}

let delegate: ApplicationDelegate = .init()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()

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
var workingDirectory: String!
var javaArguments: [String]!

for (index, arg) in arguments.enumerated() {
    if arg == "-h" || arg == "--holder" {
        holder = true
    } else if arg == "-w" || arg == "--working-directory" {
        workingDirectory = arguments[index + 1]
    } else if arg == "--args" {
        javaArguments = Array(arguments.dropFirst(index + 1))
        break
    }
}

@MainActor
func launch() {
    let executablePath: String = javaArguments[0]
    let argv: [UnsafeMutablePointer<CChar>?] = javaArguments.map { strdup($0) } + [nil]
    argv.withUnsafeBufferPointer { buffer in
        execv(executablePath, buffer.baseAddress)
        perror("execv")
    }
    exit(1)
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
    guard let workingDirectory else {
        exit(1)
    }
    let process: Process = .init()
    process.executableURL = Bundle.main.executableURL
    process.arguments = ["--args"] + javaArguments
    process.currentDirectoryURL = .init(filePath: workingDirectory)
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
} else {
    let delegate: ApplicationDelegate = .init()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}

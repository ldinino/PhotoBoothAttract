//
//  ErrorLog.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import Foundation
import Combine
import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ErrorLog: ObservableObject {
    static let shared = ErrorLog()

    private static let maxLogFileSize = 1 * 1024 * 1024  // 1 MB
    private static let maxEntriesInMemory = 3000
    private static let logFileName = "PhotoBoothAttract.log"

    private let fileQueue = DispatchQueue(label: "PhotoBoothAttract.ErrorLog.file")
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private var logFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PhotoBoothAttract", isDirectory: true)
        return dir.appendingPathComponent(Self.logFileName, isDirectory: false)
    }

    @Published private(set) var entries: [Entry] = []

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    init() {
        fileQueue.async { [weak self] in
            guard let self else { return }
            let loaded = self.loadEntriesFromFile()
            DispatchQueue.main.async {
                self.entries = loaded + self.entries
            }
        }
    }

    func log(_ message: String) {
        let entry = Entry(timestamp: Date(), message: message)
        if Thread.isMainThread {
            appendEntry(entry)
        } else {
            DispatchQueue.main.async { self.appendEntry(entry) }
        }
        let line = formatLine(entry)
        fileQueue.async { [weak self] in
            self?.appendToFile(line: line)
        }
    }

    private func appendEntry(_ entry: Entry) {
        entries.append(entry)
        if entries.count > Self.maxEntriesInMemory {
            entries.removeFirst(entries.count - Self.maxEntriesInMemory)
        }
    }

    private func formatLine(_ entry: Entry) -> String {
        "[\(dateFormatter.string(from: entry.timestamp))] \(entry.message)\n"
    }

    private func ensureLogDirectory() {
        let dir = logFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func appendToFile(line: String) {
        ensureLogDirectory()
        guard let data = line.data(using: .utf8) else { return }
        let url = logFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.synchronize()
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size > Self.maxLogFileSize {
                trimFileToMaxSize(url: url)
            }
        } else {
            try? data.write(to: url)
        }
    }

    private func trimFileToMaxSize(url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        var lines = content.components(separatedBy: .newlines)
        if lines.last == "" { lines.removeLast() }
        while !lines.isEmpty {
            let joined = lines.joined(separator: "\n")
            if joined.utf8.count <= Self.maxLogFileSize { break }
            lines.removeFirst()
        }
        let trimmed = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadEntriesFromFile() -> [Entry] {
        let url = logFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var result: [Entry] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            guard line.hasPrefix("["), let closeBracket = line.firstIndex(of: "]") else { continue }
            let timestampStr = String(line[line.index(after: line.startIndex)..<closeBracket])
            let messageStart = line.index(closeBracket, offsetBy: 1)
            if messageStart < line.endIndex, line[messageStart] == " " {
                let message = String(line[line.index(after: messageStart)...])
                if let date = dateFormatter.date(from: timestampStr) {
                    result.append(Entry(timestamp: date, message: message))
                }
            }
        }
        if result.count > Self.maxEntriesInMemory {
            result = Array(result.suffix(Self.maxEntriesInMemory))
        }
        return result
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entries.removeAll()
        }
        fileQueue.async { [weak self] in
            guard let self else { return }
            let url = self.logFileURL
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func exportText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return entries.map { "[\(formatter.string(from: $0.timestamp))] \($0.message)" }
            .joined(separator: "\n")
    }

    func exportToDesktop(completion: @escaping (Bool) -> Void) {
        let url = logFileURL
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let dateStr = dateFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: " ", with: "_")
        let exportURL = desktop.appendingPathComponent("PhotoBoothAttract_ErrorLog_\(dateStr).txt", isDirectory: false)

        fileQueue.async { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.copyItem(at: url, to: exportURL)
                    DispatchQueue.main.async { completion(true) }
                } catch {
                    DispatchQueue.main.async {
                        self.log("Failed to export log to Desktop: \(error.localizedDescription)")
                        completion(false)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    let content = self.exportText()
                    self.fileQueue.async {
                        do {
                            try content.write(to: exportURL, atomically: true, encoding: .utf8)
                            DispatchQueue.main.async { completion(true) }
                        } catch {
                            DispatchQueue.main.async {
                                self.log("Failed to export log to Desktop: \(error.localizedDescription)")
                                completion(false)
                            }
                        }
                    }
                }
            }
        }
    }
}


struct ErrorLogView: View {
    @ObservedObject var errorLog = ErrorLog.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Error Log")
                    .font(.headline)
                Spacer()
                Text("\(errorLog.entries.count) entries")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if errorLog.entries.isEmpty {
                Spacer()
                Text("No errors recorded.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(errorLog.entries) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(entry.message)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .id(entry.id)
                    }
                    .onChange(of: errorLog.entries.count) { _, _ in
                        if let last = errorLog.entries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Clear") { errorLog.clear() }
                Spacer()
                Button("Export") {
                    errorLog.exportToDesktop { success in
                        if success {
                            errorLog.log("Exported log to Desktop")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(8)
        }
        .frame(width: 600, height: 400)
    }
}

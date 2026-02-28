//
//  ErrorLog.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import Foundation
import AppKit
import SwiftUI

final class ErrorLog: ObservableObject {
    static let shared = ErrorLog()

    @Published private(set) var entries: [Entry] = []

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    func log(_ message: String) {
        let entry = Entry(timestamp: Date(), message: message)
        if Thread.isMainThread {
            entries.append(entry)
        } else {
            DispatchQueue.main.async { self.entries.append(entry) }
        }
    }

    func clear() {
        entries.removeAll()
    }

    func exportText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return entries.map { "[\(formatter.string(from: $0.timestamp))] \($0.message)" }
            .joined(separator: "\n")
    }

    func saveToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PhotoBoothAttract_ErrorLog.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exportText().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            log("Failed to save error log: \(error.localizedDescription)")
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
                    .onChange(of: errorLog.entries.count) { _ in
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
                Button("Save to File...") { errorLog.saveToFile() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(8)
        }
        .frame(width: 600, height: 400)
    }
}

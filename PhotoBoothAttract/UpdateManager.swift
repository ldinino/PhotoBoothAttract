//
//  UpdateManager.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 3/1/26.
//

import Foundation
import AppKit

final class UpdateManager {
    static let shared = UpdateManager()

    private let repoOwner = "ldinino"
    private let repoName = "PhotoBoothAttract"
    private var isChecking = false

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    }

    // MARK: - Public

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true

        let alert = NSAlert()
        alert.messageText = "Checking for Updates..."
        alert.informativeText = "Contacting GitHub for the latest release."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Cancel")

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.sizeToFit()
        spinner.startAnimation(nil)
        alert.accessoryView = spinner

        var responseData: Data?
        var responseObj: URLResponse?
        var responseError: Error?

        let request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                responseData = data
                responseObj = response
                responseError = error
                NSApp.stopModal()
                alert.window.close()
            }
        }
        task.resume()

        let modalResponse = alert.runModal()
        isChecking = false
        if modalResponse == .alertFirstButtonReturn {
            task.cancel()
            return
        }

        handleResponse(data: responseData, response: responseObj, error: responseError)
    }

    // MARK: - Response handling

    private func handleResponse(data: Data?, response: URLResponse?, error: Error?) {
        if let error {
            showError("Could not check for updates.\n\n\(error.localizedDescription)")
            return
        }

        guard let http = response as? HTTPURLResponse else {
            showError("Unexpected response from GitHub.")
            return
        }

        guard http.statusCode == 200, let data else {
            showError("GitHub returned status \(http.statusCode).")
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            showError("Could not parse release info from GitHub.")
            return
        }

        let remoteVersion = tagName.trimmingCharacters(in: .init(charactersIn: "vV"))
        let releaseNotes = json["body"] as? String ?? ""
        let htmlURL = json["html_url"] as? String ?? ""

        guard let assets = json["assets"] as? [[String: Any]],
              let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
              let downloadURLString = zipAsset["browser_download_url"] as? String,
              let downloadURL = URL(string: downloadURLString) else {
            if isNewerVersion(remoteVersion, than: currentVersion) {
                showUpdateAvailableNoAsset(version: remoteVersion, htmlURL: htmlURL)
            } else {
                showUpToDate()
            }
            return
        }

        ErrorLog.shared.log("Update check: current=v\(currentVersion) remote=v\(remoteVersion) bundlePath=\(Bundle.main.bundlePath)")

        if isNewerVersion(remoteVersion, than: currentVersion) {
            showUpdateAvailable(version: remoteVersion, notes: releaseNotes, downloadURL: downloadURL)
        } else {
            showUpToDate()
        }
    }

    // MARK: - Version comparison

    /// Returns true if `remote` is strictly newer than `local`.
    private func isNewerVersion(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    // MARK: - Alerts

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "PhotoBoothAttract v\(currentVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUpdateAvailable(version: String, notes: String, downloadURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "A new version (v\(version)) is available. You are currently running v\(currentVersion)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "Cancel")

        if !notes.isEmpty {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
            let textView = NSTextView(frame: scroll.bounds)
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            textView.string = notes
            textView.autoresizingMask = [.width, .height]
            scroll.documentView = textView
            scroll.hasVerticalScroller = true
            alert.accessoryView = scroll
        }

        if alert.runModal() == .alertFirstButtonReturn {
            downloadAndInstall(url: downloadURL, version: version)
        }
    }

    private func showUpdateAvailableNoAsset(version: String, htmlURL: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "A new version (v\(version)) is available, but no downloadable zip was found in the release assets.\n\nPlease download it manually from GitHub."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open in Browser")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: htmlURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func showError(_ message: String) {
        ErrorLog.shared.log("Update check failed: \(message)")
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Download & Install

    private func downloadAndInstall(url: URL, version: String) {
        let alert = NSAlert()
        alert.messageText = "Downloading Update..."
        alert.informativeText = "Downloading v\(version)..."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Cancel")

        let progress = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 300, height: 20))
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        alert.accessoryView = progress

        var tempURL: URL?
        var downloadError: Error?

        let task = URLSession.shared.downloadTask(with: url) { location, _, error in
            var downloadedURL: URL?
            if let location {
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("PhotoBoothAttract-update-\(UUID().uuidString).zip")
                try? FileManager.default.moveItem(at: location, to: dest)
                downloadedURL = dest
            }
            DispatchQueue.main.async {
                tempURL = downloadedURL
                downloadError = error
                NSApp.stopModal()
                alert.window.close()
            }
        }
        task.resume()

        let modalResponse = alert.runModal()
        if modalResponse == .alertFirstButtonReturn {
            task.cancel()
            return
        }

        if let downloadError {
            showError("Download failed.\n\n\(downloadError.localizedDescription)")
            return
        }
        guard let zipPath = tempURL else {
            showError("Download failed: no file received.")
            return
        }

        ErrorLog.shared.log("Update v\(version) downloaded to \(zipPath.path)")
        extractAndRelaunch(zipPath: zipPath)
    }

    private func extractAndRelaunch(zipPath: URL) {
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoBoothAttract-extracted-\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        } catch {
            showError("Failed to create temp directory.\n\n\(error.localizedDescription)")
            return
        }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipPath.path, extractDir.path]

        do {
            try ditto.run()
            ditto.waitUntilExit()
        } catch {
            showError("Failed to extract update.\n\n\(error.localizedDescription)")
            return
        }

        guard ditto.terminationStatus == 0 else {
            showError("Extraction failed (ditto exit code \(ditto.terminationStatus)).")
            return
        }

        guard let appBundle = findAppBundle(in: extractDir) else {
            showError("Could not find .app bundle in extracted update.")
            cleanup(zipPath, extractDir)
            return
        }

        let currentAppPath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier

        ErrorLog.shared.log("Update: replacing \(currentAppPath) with \(appBundle.path)")

        let script = """
            #!/bin/bash
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            rm -rf "\(currentAppPath)"
            cp -R "\(appBundle.path)" "\(currentAppPath)"
            open "\(currentAppPath)"
            rm -rf "\(extractDir.path)"
            rm -f "\(zipPath.path)"
            rm -f "$0"
            """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("photobooth_update_\(UUID().uuidString).sh")

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            showError("Failed to prepare update script.\n\n\(error.localizedDescription)")
            cleanup(zipPath, extractDir)
            return
        }

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [scriptURL.path]
        launcher.standardOutput = nil
        launcher.standardError = nil

        do {
            try launcher.run()
        } catch {
            showError("Failed to launch updater.\n\n\(error.localizedDescription)")
            cleanup(zipPath, extractDir)
            return
        }

        ErrorLog.shared.log("Update downloaded. Relaunching...")
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func findAppBundle(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "app" {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
                    return fileURL
                }
            }
        }
        return nil
    }

    private func cleanup(_ paths: URL...) {
        for path in paths {
            try? FileManager.default.removeItem(at: path)
        }
    }
}

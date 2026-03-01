//
//  PhotoManager.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//


import Foundation
import Combine
import AppKit
import ImageIO

class PhotoManager: ObservableObject {
    @Published var photos: [PhotoModel] = []
    @Published var watchedFolderURL: URL?
    @Published var isRefreshing = false
    
    private var stream: FSEventStreamRef?
    private var processingFiles: Set<URL> = []
    private let queue = DispatchQueue(label: "com.photobooth.fsevents", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "com.photobooth.processing")
    
    private static let bookmarkKey = "watchedFolderBookmark"
    static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png"]
    
    // MARK: - Configuration
    
    init() {
        restoreSavedFolder()
    }
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.message = "Select the folder where Sony Image Desktop saves photos."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            setWatchedFolder(url)
        }
    }
    
    func refreshWatcher() {
        guard let url = watchedFolderURL else { return }
        isRefreshing = true
        stopWatching()
        processingQueue.sync { processingFiles.removeAll() }
        photos.removeAll()

        startWatching()

        DispatchQueue.global(qos: .userInitiated).async {
            self.scanExistingFilesSync(at: url)
            DispatchQueue.main.async {
                self.isRefreshing = false
            }
        }
    }

    private func scanExistingFilesSync(at url: URL) {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            let group = DispatchGroup()
            for file in files {
                group.enter()
                processNewFile(at: file)
                group.leave()
            }
            group.wait()
        } catch {
            ErrorLog.shared.log("Refresh scan failed: \(error)")
        }
    }

    private func setWatchedFolder(_ url: URL) {
        self.watchedFolderURL = url
        saveBookmark(for: url)
        startWatching()
        scanExistingFiles()
    }
    
    private func saveBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        } catch {
            ErrorLog.shared.log("Failed to save folder bookmark: \(error)")
        }
    }
    
    private func restoreSavedFolder() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                saveBookmark(for: url)
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                ErrorLog.shared.log("Previously watched folder no longer exists: \(url.path)")
                return
            }
            setWatchedFolder(url)
        } catch {
            ErrorLog.shared.log("Failed to restore folder bookmark: \(error)")
        }
    }
    
    // MARK: - File Ingestion & Race Condition Handling
    
    func processNewFile(at url: URL, retries: Int = 0) {
        let isFirstAttempt = retries == 0
        if isFirstAttempt {
            let alreadyProcessing: Bool = processingQueue.sync {
                if processingFiles.contains(url) { return true }
                processingFiles.insert(url)
                return false
            }
            guard !alreadyProcessing else { return }
        }
        
        let ext = url.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else {
            removeFromProcessing(url)
            return
        }
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete else {
            if retries < 5 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    self.processNewFile(at: url, retries: retries + 1)
                }
            } else {
                removeFromProcessing(url)
                ErrorLog.shared.log("Failed to read file after multiple attempts: \(url.lastPathComponent)")
            }
            return
        }
        
        if let photo = PhotoModel(url: url) {
            DispatchQueue.main.async {
                if !self.photos.contains(where: { $0.url == url }) {
                    self.photos.append(photo)
                    self.photos.sort { $0.timestamp > $1.timestamp }
                }
            }
        }
        
        removeFromProcessing(url)
    }
    
    private func removeFromProcessing(_ url: URL) {
        processingQueue.async {
            self.processingFiles.remove(url)
        }
    }
    
    private func scanExistingFiles() {
        guard let url = watchedFolderURL else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            for file in files {
                processNewFile(at: file)
            }
        } catch {
            ErrorLog.shared.log("Failed to scan directory: \(error)")
        }
    }
    
    // MARK: - FSEvents Wrapper
    
    private func startWatching() {
        guard let folderURL = watchedFolderURL else { return }
        stopWatching()
        
        let path = [folderURL.path] as CFArray
        
        // The C-callback function
        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let manager = Unmanaged<PhotoManager>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] else { return }
            
            for i in 0..<numEvents {
                let url = URL(fileURLWithPath: paths[i])
                let flags = eventFlags[i]
                
                // Trigger only on new file creations or modifications
                let isCreatedOrModified = (flags & UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified)) != 0
                if isCreatedOrModified {
                    manager.processNewFile(at: url)
                }
            }
        }
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            path,
            FSEventsGetCurrentEventId(),
            0.5, // Latency in seconds
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )
        
        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            ErrorLog.shared.log("Now watching folder: \(folderURL.path)")
        }
    }
    
    private func stopWatching() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            self.stream = nil
        }
    }
    
    deinit {
        stopWatching()
    }
}
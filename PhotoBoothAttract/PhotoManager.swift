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
    
    private var stream: FSEventStreamRef?
    private var processingFiles: Set<URL> = []
    private let queue = DispatchQueue(label: "com.photobooth.fsevents", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "com.photobooth.processing")
    
    private static let bookmarkKey = "watchedFolderBookmark"
    
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
            print("Failed to save folder bookmark: \(error)")
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
                print("Previously watched folder no longer exists: \(url.path)")
                return
            }
            setWatchedFolder(url)
        } catch {
            print("Failed to restore folder bookmark: \(error)")
        }
    }
    
    // MARK: - File Ingestion & Race Condition Handling
    
    func processNewFile(at url: URL, retries: Int = 0) {
        let alreadyProcessing: Bool = processingQueue.sync {
            if processingFiles.contains(url) { return true }
            processingFiles.insert(url)
            return false
        }
        guard !alreadyProcessing else { return }
        
        // Ensure it's an image
        let ext = url.pathExtension.lowercased()
        guard ["jpg", "jpeg", "png"].contains(ext) else { 
            removeFromProcessing(url)
            return 
        }
        
        // RACE CONDITION FIX: Check if the file has finished writing to disk
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete else {
            
            // If the file is still writing, back off and try again up to 5 times
            if retries < 5 {
                removeFromProcessing(url)
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    self.processNewFile(at: url, retries: retries + 1)
                }
            } else {
                removeFromProcessing(url)
                print("⚠️ Failed to read file after multiple attempts: \(url.lastPathComponent)")
            }
            return
        }
        
        // File is safe to read! Create the model.
        if let photo = PhotoModel(url: url) {
            DispatchQueue.main.async {
                // Ensure no duplicates, then insert and sort reverse-chronological
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
            print("Failed to scan directory: \(error)")
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
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            
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
            print("👀 Now watching folder: \(folderURL.path)")
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
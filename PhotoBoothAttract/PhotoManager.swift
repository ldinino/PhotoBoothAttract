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

enum ClearFolderError: Error {
    case noFolder
    case folderNotSafe
    case enumerationFailed(Error)
    case deleteFailed(URL, Error)
}

/// Each folder selection or refresh starts a new generation; work tagged with an older one is stale.
nonisolated struct FolderLifecycle {
    private(set) var generation = 0
    private var claims: [URL: Int] = [:]
    private var changedWhileClaimed: Set<URL> = []
    private var lastSequence = 0

    mutating func begin() -> Int {
        generation += 1
        claims.removeAll()
        changedWhileClaimed.removeAll()
        return generation
    }

    mutating func nextSequence() -> Int {
        lastSequence += 1
        return lastSequence
    }

    func isCurrent(_ generation: Int) -> Bool {
        generation == self.generation
    }

    func owns(_ url: URL, generation: Int) -> Bool {
        isCurrent(generation) && claims[url] == generation
    }

    mutating func claim(_ url: URL, generation: Int) -> Bool {
        guard isCurrent(generation) else { return false }
        guard claims[url] == nil else {
            changedWhileClaimed.insert(url)
            return false
        }
        claims[url] = generation
        return true
    }

    /// Returns true when an event arrived while the URL was claimed, so it must be read again.
    @discardableResult
    mutating func release(_ url: URL, generation: Int) -> Bool {
        guard claims[url] == generation else { return false }
        claims[url] = nil
        return changedWhileClaimed.remove(url) != nil
    }
}

private final class StreamInfo {
    weak var manager: PhotoManager?
    let generation: Int
    init(manager: PhotoManager, generation: Int) {
        self.manager = manager
        self.generation = generation
    }
}

class PhotoManager: ObservableObject {
    @Published var photos: [PhotoModel] = []
    @Published var watchedFolderURL: URL?
    @Published var isRefreshing = false
    @Published var isClearing = false
    
    private var stream: FSEventStreamRef?
    private var lifecycle = FolderLifecycle()
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
    
    /// Starts a new lifecycle: stops the watcher and drops all state from the previous one.
    private func beginLifecycle() -> Int {
        stopWatching()
        photos.removeAll()
        isRefreshing = false
        isClearing = false
        return processingQueue.sync { lifecycle.begin() }
    }

    var generation: Int {
        processingQueue.sync { lifecycle.generation }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        processingQueue.sync { lifecycle.isCurrent(generation) }
    }

    func refreshWatcher() {
        guard let url = watchedFolderURL else { return }
        let generation = beginLifecycle()
        isRefreshing = true

        startWatching(url, generation: generation)

        DispatchQueue.global(qos: .userInitiated).async {
            self.scanExistingFilesSync(at: url, generation: generation)
            DispatchQueue.main.async {
                if self.isCurrent(generation) { self.isRefreshing = false }
            }
        }
    }

    private func scanExistingFilesSync(at url: URL, generation: Int) {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            let group = DispatchGroup()
            for file in files {
                group.enter()
                processNewFile(at: file, generation: generation)
                group.leave()
            }
            group.wait()
        } catch {
            ErrorLog.shared.log("Refresh scan failed: \(error)")
        }
    }

    func setWatchedFolder(_ url: URL) {
        let generation = beginLifecycle()
        self.watchedFolderURL = url
        saveBookmark(for: url)
        startWatching(url, generation: generation)
        scanExistingFiles(at: url, generation: generation)
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

    // MARK: - Clear Folder

    /// Returns the number of deletable image files in the watched folder, or nil if folder is missing/unsafe or enumeration failed.
    func deletablePhotoCountInWatchedFolder() -> Int? {
        switch listDeletablePhotoURLs() {
        case .success(let urls): return urls.count
        case .failure: return nil
        }
    }

    func clearWatchedFolder(completion: @escaping (Result<Int, ClearFolderError>) -> Void) {
        guard watchedFolderURL != nil else {
            completion(.failure(.noFolder))
            return
        }
        let result = listDeletablePhotoURLs()
        switch result {
        case .failure(let error):
            completion(.failure(error))
            return
        case .success(let urlsToDelete):
            let folderPath = watchedFolderURL!.standardized.path
            stopWatching()
            let generation = processingQueue.sync { lifecycle.begin() }
            startWatching(watchedFolderURL!, generation: generation)
            if urlsToDelete.isEmpty {
                ErrorLog.shared.log("Clear folder triggered: folder is empty (\(folderPath))")
                DispatchQueue.main.async {
                    if self.isCurrent(generation) { self.photos.removeAll() }
                    completion(.success(0))
                }
                return
            }
            ErrorLog.shared.log("Clear folder triggered: deleting \(urlsToDelete.count) photo(s) in \(folderPath)")
            isClearing = true
            DispatchQueue.global(qos: .userInitiated).async {
                var deletedCount = 0
                for url in urlsToDelete {
                    do {
                        try FileManager.default.removeItem(at: url)
                        deletedCount += 1
                    } catch {
                        ErrorLog.shared.log("Clear folder: failed to delete \(url.lastPathComponent): \(error)")
                    }
                }
                DispatchQueue.main.async {
                    if self.isCurrent(generation) {
                        self.isClearing = false
                        self.photos.removeAll()
                    }
                    completion(.success(deletedCount))
                }
            }
        }
    }

    /// Lists direct children of the watched folder that are regular files with allowed image extensions. Fails if no folder or path is unsafe (root or home).
    private func listDeletablePhotoURLs() -> Result<[URL], ClearFolderError> {
        guard let watched = watchedFolderURL else { return .failure(.noFolder) }
        let folderURL = watched.standardized
        let home = FileManager.default.homeDirectoryForCurrentUser.standardized.path
        if folderURL.path == "/" || folderURL.path == home {
            return .failure(.folderNotSafe)
        }
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: .skipsHiddenFiles
            )
            var toDelete: [URL] = []
            for url in contents {
                let ext = url.pathExtension.lowercased()
                guard Self.allowedExtensions.contains(ext) else { continue }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                toDelete.append(url)
            }
            return .success(toDelete)
        } catch {
            ErrorLog.shared.log("Clear folder: enumeration failed: \(error)")
            return .failure(.enumerationFailed(error))
        }
    }

    // MARK: - File Ingestion & Race Condition Handling
    
    func processNewFile(at url: URL, generation: Int, retries: Int = 0) {
        let proceed: Bool = processingQueue.sync {
            retries == 0
                ? lifecycle.claim(url, generation: generation)
                : lifecycle.owns(url, generation: generation)
        }
        guard proceed else { return }
        
        let ext = url.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else {
            removeFromProcessing(url, generation: generation)
            return
        }
        
        let sequence = processingQueue.sync { lifecycle.nextSequence() }
        guard let photo = PhotoModel(url: url, sequence: sequence) else {
            if retries < 5 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    self.processNewFile(at: url, generation: generation, retries: retries + 1)
                }
            } else {
                ErrorLog.shared.log("Failed to read file after multiple attempts: \(url.lastPathComponent)")
                DispatchQueue.main.async {
                    if self.isCurrent(generation) { self.photos.removeAll { $0.url == url } }
                }
                removeFromProcessing(url, generation: generation)
            }
            return
        }

        DispatchQueue.main.async { self.publish(photo, generation: generation) }
        removeFromProcessing(url, generation: generation)
    }

    /// One row per URL. A changed revision replaces the row; an unchanged or older one is ignored.
    func publish(_ photo: PhotoModel, generation: Int) {
        guard isCurrent(generation) else { return }
        if let index = photos.firstIndex(where: { $0.url == photo.url }) {
            let current = photos[index]
            guard photo.sequence > current.sequence else { return }
            if photo.digest == current.digest {
                photos[index].sequence = photo.sequence
                return
            }
            photos[index] = photo
        } else {
            photos.append(photo)
        }
        photos.sort { $0.timestamp > $1.timestamp }
    }
    
    func removeFromProcessing(_ url: URL, generation: Int) {
        processingQueue.async {
            if self.lifecycle.release(url, generation: generation) {
                DispatchQueue.global().async { self.processNewFile(at: url, generation: generation) }
            }
        }
    }
    
    private func scanExistingFiles(at url: URL, generation: Int) {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            for file in files {
                processNewFile(at: file, generation: generation)
            }
        } catch {
            ErrorLog.shared.log("Failed to scan directory: \(error)")
        }
    }
    
    // MARK: - FSEvents Wrapper
    
    private func startWatching(_ folderURL: URL, generation: Int) {
        let path = [folderURL.path] as CFArray
        
        // The C-callback function
        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let info = Unmanaged<StreamInfo>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            guard let manager = info.manager else { return }
            guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] else { return }
            
            for i in 0..<numEvents {
                let url = URL(fileURLWithPath: paths[i])
                let flags = eventFlags[i]
                
                // Trigger only on new file creations or modifications
                let isCreatedOrModified = (flags & UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified)) != 0
                if isCreatedOrModified {
                    manager.processNewFile(at: url, generation: info.generation)
                }
            }
        }
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(StreamInfo(manager: self, generation: generation)).toOpaque(),
            retain: nil,
            release: { Unmanaged<StreamInfo>.fromOpaque($0!).release() },
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
            queue.async { FSEventStreamRelease(stream) }
        }
    }
    
    deinit {
        stopWatching()
    }
}
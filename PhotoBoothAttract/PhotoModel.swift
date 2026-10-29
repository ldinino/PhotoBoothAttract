//
//  PhotoModel.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//


import SwiftUI
import ImageIO
import CryptoKit

enum PhotoSourceError: Error {
    /// The file no longer holds the bytes this photo was created from.
    case changed
    case unavailable
    /// The print sink reported failure; nothing was shared.
    case printFailed
}

/// Where a photo's bytes go. Injected so action preparation can be exercised without printing or Messages.
struct ActionSinks {
    var print: (Data, String) -> Bool
    var share: (Data, String, String?) -> Void

    static let live = ActionSinks(
        print: { data, name in
            var succeeded = false
            PrintManager.shared.printPhoto(imageData: data, name: name) { succeeded = $0 }
            return succeeded
        },
        share: { data, name, recipient in
            if let recipient {
                MessageManager.shared.prepareDraft(imageData: data, name: name, phoneNumber: recipient)
            } else {
                MessageManager.shared.prepareDraftWithoutRecipient(imageData: data, name: name)
            }
        }
    )
}

struct PhotoModel: Identifiable {
    let id = UUID()
    let url: URL
    let timestamp: Date
    let thumbnail: NSImage
    /// Hash of the exact bytes the thumbnail was decoded from.
    let digest: SHA256.Digest
    /// Orders revisions of one URL; a lower value never replaces a higher one.
    var sequence: Int

    /// Nil when the file is unreadable or not yet a complete image.
    init?(url: URL, sequence: Int = 0) {
        self.url = url
        self.sequence = sequence

        guard let data = try? Data(contentsOf: url) else { return nil }
        self.digest = SHA256.hash(data: data)

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            self.timestamp = attributes[.creationDate] as? Date ?? Date()
        } catch {
            self.timestamp = Date()
        }

        // 800px max dimension is more than enough for a 2x2 grid on a 1080p TV
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 800
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        self.thumbnail = NSImage(cgImage: cgImage, size: .zero)
    }

    /// Reads the source once and returns the bytes only if they are the ones this photo shows.
    func verifiedData(read: (URL) -> Data? = { try? Data(contentsOf: $0) }) -> Result<Data, PhotoSourceError> {
        guard let data = read(url) else { return .failure(.unavailable) }
        return SHA256.hash(data: data) == digest ? .success(data) : .failure(.changed)
    }

    /// Reads and verifies off the main thread, then runs the sinks on main with those same bytes; nothing reopens the URL.
    func perform(print: Bool, share: Bool, recipient: String? = nil, sinks: ActionSinks = .live,
                 read: @escaping (URL) -> Data? = { try? Data(contentsOf: $0) },
                 completion: @escaping (PhotoSourceError?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = verifiedData(read: read)
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    completion(error)
                case .success(let data):
                    let name = url.lastPathComponent
                    if print, !sinks.print(data, name) {
                        completion(.printFailed)
                        return
                    }
                    if share { sinks.share(data, name, recipient) }
                    completion(nil)
                }
            }
        }
    }
}

extension PhotoModel: Equatable {
    static func == (lhs: PhotoModel, rhs: PhotoModel) -> Bool {
        lhs.id == rhs.id
    }
}

extension PhotoModel: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

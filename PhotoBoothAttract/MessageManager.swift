//
//  MessageManager.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import AppKit
import ImageIO

class MessageManager: NSObject, NSSharingServiceDelegate {

    static let shared = MessageManager()

    private static let maxPixelSize = 3000
    /// Target size for MMS compatibility (1 MB); keeps one compression step and avoids carrier re-compression.
    private static let targetFileSizeBytes: Int64 = 1024 * 1024
    private static let initialQuality: CGFloat = 0.95
    private static let minQuality: CGFloat = 0.6
    private static let maxQualityIterations = 10
    /// Fallback quality if target-size search fails (e.g. encode errors).
    private static let fallbackQuality: CGFloat = 0.85
    static let messageTextKey = "messagesDraftText"
    static let stripGPSKey = "messagesStripGPS"
    static let defaultMessageText = "Thank you for choosing SD Photography. https://www.sd-photo.com/"

    /// Saved text, the default when unset or not a string; nil (photo only) when blank.
    static func draftText(defaults: UserDefaults = .standard) -> String? {
        let text = defaults.object(forKey: messageTextKey) as? String ?? defaultMessageText
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    /// Removing GPS is the default; only an explicit saved false keeps it.
    static func stripsGPS(defaults: UserDefaults = .standard) -> Bool {
        guard let value = defaults.object(forKey: stripGPSKey) as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return true }
        return value.boolValue
    }

    static func draftItems(text: String?, attachment: URL) -> [Any] {
        (text.map { [$0] } ?? []) + [attachment]
    }

    func prepareDraft(imageData: Data, name: String, phoneNumber: String) {
        let sanitized = phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard !sanitized.isEmpty else {
            ErrorLog.shared.log("MessageManager: Invalid phone number")
            return
        }
        openDraft(imageData: imageData, name: name, recipient: sanitized)
    }

    func prepareDraftWithoutRecipient(imageData: Data, name: String) {
        openDraft(imageData: imageData, name: name, recipient: nil)
    }

    private func openDraft(imageData: Data, name: String, recipient: String?) {
        guard let sendURL = attachmentURL(for: imageData, name: name, stripGPS: Self.stripsGPS()) else { return }

        guard let service = NSSharingService(named: .composeMessage) else {
            ErrorLog.shared.log("MessageManager: composeMessage service unavailable")
            removeRequestDirectory(of: sendURL)
            return
        }

        if let recipient { service.recipients = [recipient] }
        service.delegate = self
        service.perform(withItems: Self.draftItems(text: Self.draftText(), attachment: sendURL))
    }

    /// A file in its own per-request directory. Handed-off files are never deleted: when
    /// Messages finishes reading them is unverified, so the system temp cleanup reclaims them.
    private func attachmentURL(for data: Data, name: String, stripGPS: Bool) -> URL? {
        let fileName = (name as NSString).lastPathComponent
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoBoothAttract-messages", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            ErrorLog.shared.log("MessageManager: Could not create attachment folder: \(error)")
            return nil
        }
        if let url = compressedCopy(of: data, name: fileName, in: directory, stripGPS: stripGPS) { return url }
        guard !stripGPS else {
            ErrorLog.shared.log("MessageManager: Could not remove GPS from the attachment; not attaching the photo")
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            ErrorLog.shared.log("MessageManager: Could not write attachment: \(error)")
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
    }

    /// Only for a request whose attachment was never handed to Messages.
    private func removeRequestDirectory(of url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Image Compression

    /// Source metadata adjusted for a re-encoded copy of the given pixel size. Orientation is already
    /// baked into the pixels, so any stored tag becomes 1; stored dimensions follow the output.
    static func outputMetadata(from source: CGImageMetadata?, width: Int, height: Int, stripGPS: Bool) -> CGImageMetadata {
        let metadata = source.flatMap { CGImageMetadataCreateMutableCopy($0) } ?? CGImageMetadataCreateMutable()
        if stripGPS {
            for path in gpsPaths(in: metadata) { CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString) }
        }
        let values: [(String, Int)] = [("tiff:Orientation", 1), ("exif:PixelXDimension", width), ("exif:PixelYDimension", height),
                                       ("tiff:ImageWidth", width), ("tiff:ImageLength", height)]
        for (path, value) in values where CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString) != nil {
            CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, value as CFNumber)
        }
        return metadata
    }

    private static func gpsPaths(in metadata: CGImageMetadata) -> [String] {
        var paths: [String] = []
        let options = [kCGImageMetadataEnumerateRecursively: true] as CFDictionary
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, options) { path, _ in
            if (path as String).contains("GPS") { paths.append(path as String) }
            return true
        }
        return paths
    }

    /// True when the file has a GPS property dictionary or any GPS metadata tag.
    static func containsGPS(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return true }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        if props?[kCGImagePropertyGPSDictionary] != nil { return true }
        return CGImageSourceCopyMetadataAtIndex(source, 0, nil).map { !gpsPaths(in: $0).isEmpty } ?? false
    }

    /// Encodes image and metadata to JPEG at the given quality; returns file size in bytes, or nil on failure.
    private func encodeImage(_ image: CGImage, metadata: CGImageMetadata, to url: URL, quality: CGFloat) -> Int64? {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let sizeAny = attrs[.size] else {
            return nil
        }
        let size: Int64?
        if let n = sizeAny as? Int64 { size = n }
        else if let n = sizeAny as? Int { size = Int64(n) }
        else if let n = sizeAny as? NSNumber { size = n.int64Value }
        else { size = nil }
        return size
    }

    /// Produces a JPEG copy sized for MMS (≤ targetFileSizeBytes) at the highest quality that fits.
    private func compressedCopy(of data: Data, name: String, in directory: URL, stripGPS: Bool) -> URL? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = props[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = props[kCGImagePropertyPixelHeight] as? Int else {
            ErrorLog.shared.log("MessageManager: Could not read source image for compression")
            return nil
        }

        let destURL = directory
            .appendingPathComponent((name as NSString).deletingPathExtension + "_send")
            .appendingPathExtension("jpg")

        // The thumbnail bakes EXIF orientation into pixels (the encoder writes no tag); never upscales.
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(pixelWidth, pixelHeight), Self.maxPixelSize)
        ]
        guard let finalImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) else {
            ErrorLog.shared.log("MessageManager: Could not orient source image for compression")
            return nil
        }

        let metadata = Self.outputMetadata(from: CGImageSourceCopyMetadataAtIndex(source, 0, nil),
                                           width: finalImage.width, height: finalImage.height, stripGPS: stripGPS)
        guard let url = encodeBest(finalImage, metadata: metadata, to: destURL) else { return nil }
        if stripGPS && Self.containsGPS(at: url) {
            ErrorLog.shared.log("MessageManager: GPS metadata remained after re-encoding")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    private func encodeBest(_ finalImage: CGImage, metadata: CGImageMetadata, to destURL: URL) -> URL? {
        // Try initial quality; if already under target, we're done.
        if let size = encodeImage(finalImage, metadata: metadata, to: destURL, quality: Self.initialQuality),
           size <= Self.targetFileSizeBytes {
            return destURL
        }

        // Binary search for highest quality that stays under target file size.
        var bestQuality = Self.minQuality
        var low = Self.minQuality
        var high = Self.initialQuality
        var iterations = 0
        let qualityTolerance: CGFloat = 0.02

        while iterations < Self.maxQualityIterations && (high - low) > qualityTolerance {
            let mid = (low + high) / 2
            guard let size = encodeImage(finalImage, metadata: metadata, to: destURL, quality: mid) else {
                ErrorLog.shared.log("MessageManager: Encode failed during quality search at \(mid)")
                break
            }
            if size <= Self.targetFileSizeBytes {
                bestQuality = mid
                low = mid
            } else {
                high = mid
            }
            iterations += 1
        }

        // Final encode at best quality (ensures valid file; handles case where we never got under target).
        if encodeImage(finalImage, metadata: metadata, to: destURL, quality: bestQuality) != nil {
            return destURL
        }

        // Fallback: single encode at legacy quality so sharing still works.
        if encodeImage(finalImage, metadata: metadata, to: destURL, quality: Self.fallbackQuality) != nil {
            ErrorLog.shared.log("MessageManager: Using fallback quality after target-size search failed")
            return destURL
        }
        ErrorLog.shared.log("MessageManager: Failed to write compressed image")
        return nil
    }

    // MARK: - NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {}

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        ErrorLog.shared.log("MessageManager: Failed to share - \(error.localizedDescription)")
    }
}

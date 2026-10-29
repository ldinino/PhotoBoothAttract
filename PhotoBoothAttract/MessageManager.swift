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
    private static let messageBody = "Thank you for choosing SD Photography. https://www.sd-photo.com/"

    func prepareDraft(imageData: Data, name: String, phoneNumber: String) {
        let sanitized = phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard !sanitized.isEmpty else {
            ErrorLog.shared.log("MessageManager: Invalid phone number")
            return
        }

        guard let sendURL = attachmentURL(for: imageData, name: name) else { return }

        guard let service = NSSharingService(named: .composeMessage) else {
            ErrorLog.shared.log("MessageManager: composeMessage service unavailable")
            removeRequestDirectory(of: sendURL)
            return
        }

        service.recipients = [sanitized]
        service.delegate = self
        service.perform(withItems: [Self.messageBody, sendURL])
    }

    func prepareDraftWithoutRecipient(imageData: Data, name: String) {
        guard let sendURL = attachmentURL(for: imageData, name: name) else { return }

        guard let service = NSSharingService(named: .composeMessage) else {
            ErrorLog.shared.log("MessageManager: composeMessage service unavailable")
            removeRequestDirectory(of: sendURL)
            return
        }

        service.delegate = self
        service.perform(withItems: [Self.messageBody, sendURL])
    }

    /// A file in its own per-request directory. Handed-off files are never deleted: when
    /// Messages finishes reading them is unverified, so the system temp cleanup reclaims them.
    private func attachmentURL(for data: Data, name: String) -> URL? {
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
        if let url = compressedCopy(of: data, name: fileName, in: directory) { return url }
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

    /// Encodes image to JPEG at the given quality; returns file size in bytes, or nil on failure.
    private func encodeImage(_ image: CGImage, to url: URL, quality: CGFloat) -> Int64? {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
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
    private func compressedCopy(of data: Data, name: String, in directory: URL) -> URL? {
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

        // Try initial quality; if already under target, we're done.
        if let size = encodeImage(finalImage, to: destURL, quality: Self.initialQuality),
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
            guard let size = encodeImage(finalImage, to: destURL, quality: mid) else {
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
        if encodeImage(finalImage, to: destURL, quality: bestQuality) != nil {
            return destURL
        }

        // Fallback: single encode at legacy quality so sharing still works.
        if encodeImage(finalImage, to: destURL, quality: Self.fallbackQuality) != nil {
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

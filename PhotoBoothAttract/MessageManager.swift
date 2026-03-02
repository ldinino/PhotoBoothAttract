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

    func prepareDraft(imageURL: URL, phoneNumber: String) {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            ErrorLog.shared.log("MessageManager: Image not found at \(imageURL.path)")
            return
        }

        let sanitized = phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard !sanitized.isEmpty else {
            ErrorLog.shared.log("MessageManager: Invalid phone number")
            return
        }

        let sendURL = compressedCopy(of: imageURL) ?? imageURL

        guard let service = NSSharingService(named: .composeMessage) else {
            ErrorLog.shared.log("MessageManager: composeMessage service unavailable")
            return
        }

        service.recipients = [sanitized]
        service.delegate = self
        service.perform(withItems: [Self.messageBody, sendURL])
    }

    func prepareDraftWithoutRecipient(imageURL: URL) {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            ErrorLog.shared.log("MessageManager: Image not found at \(imageURL.path)")
            return
        }

        let sendURL = compressedCopy(of: imageURL) ?? imageURL

        guard let service = NSSharingService(named: .composeMessage) else {
            ErrorLog.shared.log("MessageManager: composeMessage service unavailable")
            return
        }

        service.delegate = self
        service.perform(withItems: [Self.messageBody, sendURL])
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
    private func compressedCopy(of sourceURL: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            ErrorLog.shared.log("MessageManager: Could not read source image for compression")
            return nil
        }

        let maxDim = Self.maxPixelSize
        let needsDownscale = cgImage.width > maxDim || cgImage.height > maxDim

        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + "_send")
            .appendingPathExtension("jpg")

        var finalImage: CGImage = cgImage
        if needsDownscale {
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDim
            ]
            if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) {
                finalImage = thumb
            }
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

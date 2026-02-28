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
    private static let jpegQuality: CGFloat = 0.85

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
        service.perform(withItems: [sendURL])
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
        service.perform(withItems: [sendURL])
    }

    // MARK: - Image Compression

    private func compressedCopy(of sourceURL: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            ErrorLog.shared.log("MessageManager: Could not read source image for compression")
            return nil
        }

        let originalWidth = cgImage.width
        let originalHeight = cgImage.height
        let maxDim = Self.maxPixelSize

        let needsDownscale = originalWidth > maxDim || originalHeight > maxDim

        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + "_send")
            .appendingPathExtension("jpg")

        guard let destination = CGImageDestinationCreateWithURL(destURL as CFURL, "public.jpeg" as CFString, 1, nil) else {
            ErrorLog.shared.log("MessageManager: Could not create image destination")
            return nil
        }

        var finalImage = cgImage

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

        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: Self.jpegQuality]
        CGImageDestinationAddImage(destination, finalImage, props as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            ErrorLog.shared.log("MessageManager: Failed to write compressed image")
            return nil
        }

        return destURL
    }

    // MARK: - NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        ErrorLog.shared.log("MessageManager: Message shared successfully")
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        ErrorLog.shared.log("MessageManager: Failed to share - \(error.localizedDescription)")
    }
}

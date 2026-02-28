//
//  MessageManager.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import AppKit

class MessageManager: NSObject, NSSharingServiceDelegate {

    static let shared = MessageManager()

    /// Opens Messages with a draft to the given phone number with the image attached.
    func prepareDraft(imageURL: URL, phoneNumber: String) {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            print("MessageManager: Image not found at \(imageURL.path)")
            return
        }

        let sanitized = phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard !sanitized.isEmpty else {
            print("MessageManager: Invalid phone number")
            return
        }

        guard let service = NSSharingService(named: .composeMessage) else {
            print("MessageManager: composeMessage service unavailable")
            return
        }

        service.recipients = [sanitized]
        service.delegate = self
        service.perform(withItems: [imageURL])
    }

    /// Opens Messages with just the image attached, no recipient pre-filled.
    func prepareDraftWithoutRecipient(imageURL: URL) {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            print("MessageManager: Image not found at \(imageURL.path)")
            return
        }

        guard let service = NSSharingService(named: .composeMessage) else {
            print("MessageManager: composeMessage service unavailable")
            return
        }

        service.delegate = self
        service.perform(withItems: [imageURL])
    }

    // MARK: - NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        print("MessageManager: Message shared successfully")
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        print("MessageManager: Failed to share - \(error.localizedDescription)")
    }
}

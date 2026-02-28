//
//  PhotoModel.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//


import SwiftUI
import ImageIO

struct PhotoModel: Identifiable {
    let id = UUID()
    let url: URL
    let timestamp: Date
    let thumbnail: NSImage

    init?(url: URL) {
        self.url = url
        
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
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        
        self.thumbnail = NSImage(cgImage: cgImage, size: .zero)
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
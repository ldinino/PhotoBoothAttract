//
//  AssistantView.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//


import SwiftUI

struct AssistantView: View {
    @EnvironmentObject var photoManager: PhotoManager
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Toolbar / Header
            HStack {
                Text("PhotoBooth Assistant")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                if let url = photoManager.watchedFolderURL {
                    Text("Watching: \(url.lastPathComponent)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                
                Button("Select Folder") {
                    photoManager.selectFolder()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // MARK: - Photo Stream
            ScrollView {
                LazyVStack(spacing: 12) {
                    if photoManager.photos.isEmpty {
                        Text("No photos yet. Select a folder to begin.")
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(Array(photoManager.photos.enumerated()), id: \.element.id) { index, photo in
                            AssistantPhotoRow(photo: photo, index: index)
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(NSColor.underPageBackgroundColor))
    }
}

struct AssistantPhotoRow: View {
    let photo: PhotoModel
    let index: Int
    
    var body: some View {
        HStack(spacing: 20) {
            // Thumbnail with optional badge
            ZStack(alignment: .topLeading) {
                Image(nsImage: photo.thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 120)
                    .cornerRadius(8)
                    .shadow(radius: 2)
                
                // Overlay badge for the active "Guest TV" top 4
                if index < 4 {
                    Text("\(index + 1)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .offset(x: -8, y: -8)
                        .shadow(radius: 2)
                }
            }
            
            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(photo.url.lastPathComponent)
                    .font(.headline)
                Text(photo.timestamp, style: .time)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // MARK: - Action Buttons
            HStack(spacing: 16) {
                Button(action: {
                    // TODO: Phase 4 & 5 - Print and Send
                    print("Initiating Print & Digital for: \(photo.url.lastPathComponent)")
                }) {
                    VStack {
                        Text("🖨️ + ✉️")
                            .font(.title)
                        Text("Print & Digital")
                            .font(.caption)
                    }
                    .frame(width: 100, height: 60)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                
                Button(action: {
                    // TODO: Phase 5 - Send Only
                    print("Initiating Digital Only for: \(photo.url.lastPathComponent)")
                }) {
                    VStack {
                        Text("✉️")
                            .font(.title)
                        Text("Digital Only")
                            .font(.caption)
                    }
                    .frame(width: 100, height: 60)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

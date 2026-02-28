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

    @State private var showingPhoneSheet = false
    @State private var phoneNumber = ""
    @State private var shouldPrint = false

    var body: some View {
        HStack(spacing: 20) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: photo.thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 120)
                    .cornerRadius(8)
                    .shadow(radius: 2)

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

            VStack(alignment: .leading, spacing: 4) {
                Text(photo.url.lastPathComponent)
                    .font(.headline)
                Text(photo.timestamp, style: .time)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // MARK: - Action Buttons
            HStack(spacing: 12) {
                Button(action: {
                    shouldPrint = true
                    phoneNumber = ""
                    showingPhoneSheet = true
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
                    PrintManager.shared.printPhoto(at: photo.url)
                }) {
                    VStack {
                        Text("🖨️")
                            .font(.title)
                        Text("Print Only")
                            .font(.caption)
                    }
                    .frame(width: 100, height: 60)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button(action: {
                    shouldPrint = false
                    phoneNumber = ""
                    showingPhoneSheet = true
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
        .sheet(isPresented: $showingPhoneSheet) {
            PhoneNumberSheet(
                photoURL: photo.url,
                shouldPrint: shouldPrint,
                phoneNumber: $phoneNumber,
                isPresented: $showingPhoneSheet
            )
        }
    }
}

struct PhoneNumberSheet: View {
    let photoURL: URL
    let shouldPrint: Bool
    @Binding var phoneNumber: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text(shouldPrint ? "Print & Send via iMessage" : "Send via iMessage")
                .font(.title2)
                .bold()

            Text(photoURL.lastPathComponent)
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Phone number (e.g. +15551234567)", text: $phoneNumber)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { send() }

            HStack(spacing: 16) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Send without number") {
                    if shouldPrint {
                        PrintManager.shared.printPhoto(at: photoURL)
                    }
                    MessageManager.shared.prepareDraftWithoutRecipient(imageURL: photoURL)
                    isPresented = false
                }

                Button("Send") {
                    send()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(30)
        .frame(width: 420)
    }

    private func send() {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if shouldPrint {
            PrintManager.shared.printPhoto(at: photoURL)
        }
        MessageManager.shared.prepareDraft(imageURL: photoURL, phoneNumber: trimmed)
        isPresented = false
    }
}

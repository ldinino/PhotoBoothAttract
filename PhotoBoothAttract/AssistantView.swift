//
//  AssistantView.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//


import SwiftUI

struct SheetRequest: Identifiable {
    let id = UUID()
    let photoURL: URL
    let shouldPrint: Bool
}

struct AssistantView: View {
    @EnvironmentObject var photoManager: PhotoManager

    @State private var sheetRequest: SheetRequest?
    @State private var phoneNumber = ""
    @State private var showClearConfirmation = false
    @State private var showClearResultAlert = false
    @State private var clearResultTitle = ""
    @State private var clearResultMessage = ""

    private var refreshButton: some View {
        Button {
            photoManager.refreshWatcher()
        } label: {
            if photoManager.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(photoManager.isRefreshing || photoManager.watchedFolderURL == nil)
        .help("Restart file watcher and re-scan folder")
    }

    var body: some View {
        GeometryReader { geo in
            let rowWidth = max(geo.size.width - 32, 200)

            VStack(spacing: 0) {
                // MARK: - Toolbar / Header
                ViewThatFits(in: .horizontal) {
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
                        refreshButton
                        Button("Clear Photo Queue") {
                            showClearConfirmation = true
                        }
                        .disabled(photoManager.watchedFolderURL == nil || photoManager.isClearing || photoManager.isRefreshing)
                        .help("Delete all photos in the watched folder")
                        Button("Select Folder") {
                            photoManager.selectFolder()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack {
                        Text("PhotoBooth Assistant")
                            .font(.headline)
                            .bold()
                            .lineLimit(1)
                        Spacer()
                        refreshButton
                        Button("Clear Photo Queue") {
                            showClearConfirmation = true
                        }
                        .disabled(photoManager.watchedFolderURL == nil || photoManager.isClearing || photoManager.isRefreshing)
                        .help("Delete all photos in the watched folder")
                        Button("Select Folder") {
                            photoManager.selectFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
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
                                AssistantPhotoRow(
                                    photo: photo,
                                    index: index,
                                    rowWidth: rowWidth,
                                    onRequestSheet: { url, wantsPrint in
                                        phoneNumber = ""
                                        sheetRequest = SheetRequest(photoURL: url, shouldPrint: wantsPrint)
                                    }
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .background(Color(NSColor.underPageBackgroundColor))
        .overlay(alignment: .top) {
            if photoManager.isRefreshing {
                ProgressView("Refreshing…")
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if photoManager.isClearing {
                ProgressView("Clearing…")
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: photoManager.isRefreshing)
        .animation(.easeInOut(duration: 0.25), value: photoManager.isClearing)
        .sheet(item: $sheetRequest) { request in
            PhoneNumberSheet(
                photoURL: request.photoURL,
                shouldPrint: request.shouldPrint,
                phoneNumber: $phoneNumber,
                sheetRequest: $sheetRequest
            )
        }
        .confirmationDialog("Clear folder?", isPresented: $showClearConfirmation) {
            Button("Delete All", role: .destructive) {
                performClearFolder()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let count = photoManager.photos.count
            let folderName = photoManager.watchedFolderURL?.lastPathComponent ?? "folder"
            Text("Permanently delete all \(count) photo\(count == 1 ? "" : "s") in \"\(folderName)\"? This cannot be undone.")
        }
        .alert(clearResultTitle, isPresented: $showClearResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(clearResultMessage)
        }
    }

    private func performClearFolder() {
        photoManager.clearWatchedFolder { result in
            switch result {
            case .success(let count):
                clearResultTitle = "Folder cleared"
                clearResultMessage = "Deleted \(count) photo\(count == 1 ? "" : "s")."
                showClearResultAlert = true
            case .failure(let error):
                clearResultTitle = "Clear folder failed"
                clearResultMessage = message(for: error)
                ErrorLog.shared.log("Clear folder: \(clearResultMessage)")
                showClearResultAlert = true
            }
        }
    }

    private func message(for error: ClearFolderError) -> String {
        switch error {
        case .noFolder:
            return "No folder is selected."
        case .folderNotSafe:
            return "This folder cannot be cleared for safety (root or home directory)."
        case .enumerationFailed(let underlying):
            return "Could not list folder contents: \(underlying.localizedDescription)"
        case .deleteFailed(let url, let underlying):
            return "Failed to delete \(url.lastPathComponent): \(underlying.localizedDescription)"
        }
    }
}

struct AssistantPhotoRow: View {
    let photo: PhotoModel
    let index: Int
    let rowWidth: CGFloat
    var onRequestSheet: (URL, Bool) -> Void

    private var isCompact: Bool { rowWidth < 460 }
    private var isWide: Bool { rowWidth >= 560 }

    private var thumbWidth: CGFloat {
        if isWide { return 140 }
        if !isCompact { return 110 }
        return 80
    }

    var body: some View {
        HStack(spacing: isCompact ? 8 : 14) {
            // MARK: Thumbnail
            ZStack(alignment: .topLeading) {
                Image(nsImage: photo.thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: thumbWidth)
                    .cornerRadius(8)
                    .shadow(radius: 2)

                if index < 4 {
                    Text("\(index + 1)")
                        .font(isCompact ? .subheadline : .headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, isCompact ? 6 : 10)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .offset(x: -8, y: -8)
                        .shadow(radius: 2)
                }
            }

            // MARK: File info (wide only)
            if isWide {
                VStack(alignment: .leading, spacing: 4) {
                    Text(photo.url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text(photo.timestamp, style: .time)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 40)
            }

            Spacer(minLength: 4)

            // MARK: Action Buttons
            actionButtons
        }
        .padding(.horizontal, isCompact ? 8 : 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var actionButtons: some View {
        let showLabels = !isCompact
        let btnHeight: CGFloat = showLabels ? 56 : 40

        return HStack(spacing: isCompact ? 4 : 8) {
            Button(action: { onRequestSheet(photo.url, true) }) {
                VStack(spacing: 2) {
                    Text("🖨️+✉️")
                        .font(showLabels ? .title3 : .body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if showLabels {
                        Text("Print & Digital")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: btnHeight)
            }
            .buttonStyle(.bordered)
            .tint(.blue)

            Button(action: { PrintManager.shared.printPhoto(at: photo.url) }) {
                VStack(spacing: 2) {
                    Text("🖨️")
                        .font(showLabels ? .title3 : .body)
                    if showLabels {
                        Text("Print Only")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: btnHeight)
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Button(action: { onRequestSheet(photo.url, false) }) {
                VStack(spacing: 2) {
                    Text("✉️")
                        .font(showLabels ? .title3 : .body)
                    if showLabels {
                        Text("Digital Only")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: btnHeight)
            }
            .buttonStyle(.bordered)
            .tint(.green)
        }
    }
}

struct PhoneNumberSheet: View {
    let photoURL: URL
    let shouldPrint: Bool
    @Binding var phoneNumber: String
    @Binding var sheetRequest: SheetRequest?

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
                    sheetRequest = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("Send without number") {
                    if shouldPrint {
                        PrintManager.shared.printPhoto(at: photoURL)
                    }
                    MessageManager.shared.prepareDraftWithoutRecipient(imageURL: photoURL)
                    sheetRequest = nil
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
        sheetRequest = nil
    }
}

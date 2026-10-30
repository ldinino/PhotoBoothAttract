//
//  AssistantView.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//


import SwiftUI

struct SheetRequest: Identifiable {
    let id = UUID()
    let photo: PhotoModel
    let shouldPrint: Bool
}

struct AssistantView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var sonyCameraManager: SonyCameraManager

    @State private var sheetRequest: SheetRequest?
    @State private var phoneNumber = ""
    @State private var showClearConfirmation = false
    @State private var showClearResultAlert = false
    @State private var clearResultTitle = ""
    @State private var clearResultMessage = ""
    @State private var showStaleAlert = false
    @State private var staleMessage = ""

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

    private var cameraStatusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(cameraStatusColor)
                .frame(width: 9, height: 9)
            Text(cameraStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(Capsule())
        .help(cameraStatusHelp)
    }

    private var cameraStatusColor: Color {
        if sonyCameraManager.mode == .cooperative { return .blue }
        switch sonyCameraManager.connectionStatus {
        case .connected:
            return .green
        case .failed:
            return .red
        case .notConnected:
            return .gray
        }
    }

    private var cameraStatusText: String {
        if sonyCameraManager.mode == .cooperative { return "Camera: Cooperative" }
        switch sonyCameraManager.connectionStatus {
        case .connected(let model):
            return "Camera (Native): \(model)"
        case .failed:
            return "Camera (Native): Connection failed"
        case .notConnected:
            return "Camera (Native): Not connected"
        }
    }

    private var cameraStatusHelp: String {
        if sonyCameraManager.mode == .cooperative {
            return "Cooperative mode: Imaging Edge Desktop or another tethering app controls the camera. PBA only watches the selected folder."
        }
        switch sonyCameraManager.connectionStatus {
        case .connected(let model):
            return "USB camera connected (\(model))"
        case .failed(let reason):
            return reason
        case .notConnected:
            return "No USB camera is currently connected"
        }
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
                        cameraStatusChip
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
                        cameraStatusChip
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
                                    onRequestSheet: { photo, wantsPrint in
                                        phoneNumber = ""
                                        sheetRequest = SheetRequest(photo: photo, shouldPrint: wantsPrint)
                                    },
                                    onFailure: reportFailure
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
                requestID: request.id,
                photo: request.photo,
                shouldPrint: request.shouldPrint,
                phoneNumber: $phoneNumber,
                sheetRequest: $sheetRequest,
                onFailure: reportFailure
            )
        }
        .alert("Photo not sent", isPresented: $showStaleAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(staleMessage)
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

    private func reportFailure(_ error: PhotoSourceError) {
        switch error {
        case .changed:
            staleMessage = "This photo was replaced after you selected it. Nothing was printed or sent. Select it again."
        case .unavailable:
            staleMessage = "This photo's file is no longer available. Nothing was printed or sent."
        case .printFailed:
            staleMessage = "The print could not be queued. Check the printer and try again."
        }
        showStaleAlert = true
    }

    private func performClearFolder() {
        photoManager.clearWatchedFolder { result in
            switch result {
            case .success(let count):
                clearResultTitle = "Folder cleared"
                clearResultMessage = "Deleted \(count) photo\(count == 1 ? "" : "s")."
                showClearResultAlert = true
            case .failure(let error):
                clearResultTitle = isPartial(error) ? "Folder partly cleared" : "Clear folder failed"
                clearResultMessage = message(for: error)
                ErrorLog.shared.log("Clear folder: \(clearResultMessage)")
                showClearResultAlert = true
            }
        }
    }

    private func isPartial(_ error: ClearFolderError) -> Bool {
        if case .deleteFailed(let deleted, _, _) = error { return deleted > 0 }
        return false
    }

    private func message(for error: ClearFolderError) -> String {
        switch error {
        case .noFolder:
            return "No folder is selected."
        case .folderNotSafe:
            return "This folder cannot be cleared for safety (root or home directory)."
        case .enumerationFailed(let underlying):
            return "Could not list folder contents: \(underlying.localizedDescription)"
        case .deleteFailed(let deleted, let failed, let underlying):
            return "Deleted \(deleted), but \(failed) photo\(failed == 1 ? "" : "s") could not be deleted and remain in the folder. First error: \(underlying.localizedDescription)"
        }
    }
}

struct AssistantPhotoRow: View {
    let photo: PhotoModel
    let index: Int
    let rowWidth: CGFloat
    var onRequestSheet: (PhotoModel, Bool) -> Void
    var onFailure: (PhotoSourceError) -> Void
    @State private var isPrinting = false

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
            Button(action: { onRequestSheet(photo, true) }) {
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

            Button(action: {
                isPrinting = true
                photo.perform(print: true, share: false) {
                    isPrinting = false
                    if let error = $0 { onFailure(error) }
                }
            }) {
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
            .disabled(isPrinting)

            Button(action: { onRequestSheet(photo, false) }) {
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
    let requestID: UUID
    let photo: PhotoModel
    let shouldPrint: Bool
    @Binding var phoneNumber: String
    @Binding var sheetRequest: SheetRequest?
    var onFailure: (PhotoSourceError) -> Void
    @State private var isPending = false
    @State private var printFailed = false

    var body: some View {
        VStack(spacing: 20) {
            Text(shouldPrint ? "Print & Send via iMessage" : "Send via iMessage")
                .font(.title2)
                .bold()

            Text(photo.url.lastPathComponent)
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Phone number (e.g. +15551234567)", text: $phoneNumber)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { send() }

            if printFailed {
                Text("The print could not be queued, so no message draft was opened. Check the printer, then retry or cancel.")
                    .font(.callout)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                Button("Cancel") {
                    sheetRequest = nil
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isPending)

                Button("Send without number") {
                    submit(recipient: nil)
                }
                .disabled(isPending)

                Button("Send") {
                    send()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isPending || phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(30)
        .frame(width: 420)
        .interactiveDismissDisabled(isPending)
    }

    private func send() {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        submit(recipient: trimmed)
    }

    private func submit(recipient: String?) {
        guard !isPending else { return }
        isPending = true
        printFailed = false
        photo.perform(print: shouldPrint, share: true, recipient: recipient) { error in
            isPending = false
            switch error {
            case nil:
                dismissIfCurrent()
            case .printFailed:
                printFailed = true
            case .some(let error):
                dismissIfCurrent()
                onFailure(error)
            }
        }
    }

    private func dismissIfCurrent() {
        if sheetRequest?.id == requestID { sheetRequest = nil }
    }
}

//
//  SettingsView.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import SwiftUI

struct SettingsView: View {
    @State private var printerName: String = PrintManager.shared.configuredPrinterName
    @State private var availablePrinters: [String] = []
    @State private var watermarkText: String = ""
    @State private var messageText = ""
    @State private var saved = false
    @State private var cameraMode = CameraMode.resolve()
    @State private var savedCameraMode = CameraMode.resolve()
    @State private var showingCameraHelp = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Printer Configuration") {
                    Picker("Printer", selection: $printerName) {
                        ForEach(availablePrinters, id: \.self) { name in
                            Text(name).tag(name)
                        }

                        if !availablePrinters.contains(printerName) {
                            Text("\(printerName) (not found)")
                                .foregroundColor(.red)
                                .tag(printerName)
                        }
                    }

                    TextField("Or type printer name manually", text: $printerName)
                        .textFieldStyle(.roundedBorder)

                    Button("Refresh Printers") {
                        availablePrinters = PrintManager.shared.availablePrinters()
                    }
                }

                Section("Camera") {
                    HStack {
                        Picker("Camera mode", selection: $cameraMode) {
                            ForEach(CameraMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        Button {
                            showingCameraHelp.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Explain camera modes")
                        .accessibilityLabel("Camera mode help")
                        .popover(isPresented: $showingCameraHelp) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("**Cooperative:** Imaging Edge Desktop or another tethering app controls the camera. PBA watches the selected folder without accessing the camera.")
                                Text("**Native:** PBA enables its experimental Sony SDK camera path. Quit Imaging Edge Desktop first. Native capture and transfer are not production-ready.")
                                Text("Mode changes take effect after quitting and reopening PBA.")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            .frame(width: 320)
                            .padding(12)
                        }
                    }
                    if savedCameraMode != CameraMode.launched {
                        Text("Restart required: PBA is running in \(CameraMode.launched.title) mode. \(savedCameraMode.title) takes effect after quitting and reopening PBA.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Guest grid") {
                    TextField("Watermark text", text: $watermarkText, prompt: Text("SAMPLE"))
                        .textFieldStyle(.roundedBorder)
                    Text("Shown diagonally on the guest TV to discourage photo copying. Leave empty for default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Messages") {
                    TextEditor(text: $messageText)
                        .frame(height: 60)
                    Text("Text added to each Messages draft with the photo. Leave blank to send the photo only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                if saved {
                    Text("Saved")
                        .foregroundColor(.green)
                        .font(.caption)
                }
                Button("Save") {
                    PrintManager.shared.configuredPrinterName = printerName
                    UserDefaults.standard.set(watermarkText, forKey: GuestGridConfig.watermarkKey)
                    UserDefaults.standard.set(messageText, forKey: MessageManager.messageTextKey)
                    UserDefaults.standard.set(cameraMode.rawValue, forKey: CameraMode.key)
                    savedCameraMode = cameraMode
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        saved = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(printerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 480, height: 540)
        .onAppear {
            availablePrinters = PrintManager.shared.availablePrinters()
            watermarkText = UserDefaults.standard.string(forKey: GuestGridConfig.watermarkKey) ?? ""
            messageText = MessageManager.draftText() ?? ""
        }
    }
}

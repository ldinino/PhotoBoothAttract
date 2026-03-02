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
    @State private var saved = false

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

                Section("Guest grid") {
                    TextField("Watermark text", text: $watermarkText, prompt: Text("SAMPLE"))
                        .textFieldStyle(.roundedBorder)
                    Text("Shown diagonally on the guest TV to discourage photo copying. Leave empty for default.")
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
        .frame(width: 480, height: 320)
        .onAppear {
            availablePrinters = PrintManager.shared.availablePrinters()
            watermarkText = UserDefaults.standard.string(forKey: GuestGridConfig.watermarkKey) ?? ""
        }
    }
}

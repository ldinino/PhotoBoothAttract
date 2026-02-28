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
    @State private var saved = false

    var body: some View {
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

                HStack {
                    Button("Refresh Printers") {
                        availablePrinters = PrintManager.shared.availablePrinters()
                    }

                    Spacer()

                    if saved {
                        Text("Saved")
                            .foregroundColor(.green)
                            .font(.caption)
                    }

                    Button("Save") {
                        PrintManager.shared.configuredPrinterName = printerName
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            saved = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(printerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 200)
        .onAppear {
            availablePrinters = PrintManager.shared.availablePrinters()
        }
    }
}

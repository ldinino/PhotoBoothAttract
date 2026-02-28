//
//  PrintManager.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import AppKit

class PrintManager: NSObject {

    static let shared = PrintManager()
    static let printerNameKey = "configuredPrinterName"
    static let defaultPrinterName = "Canon_Selphy_CP1500"

    // 4x6 inch photo paper in points (72 points per inch)
    private let paperWidth: CGFloat = 4.0 * 72.0   // 288pt
    private let paperHeight: CGFloat = 6.0 * 72.0   // 432pt

    var configuredPrinterName: String {
        get {
            UserDefaults.standard.string(forKey: Self.printerNameKey) ?? Self.defaultPrinterName
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.printerNameKey)
        }
    }

    func printPhoto(at url: URL, completion: ((Bool) -> Void)? = nil) {
        guard let image = NSImage(contentsOf: url) else {
            ErrorLog.shared.log("PrintManager: Could not load image at \(url.path)")
            completion?(false)
            return
        }

        guard let printer = NSPrinter(name: configuredPrinterName) else {
            ErrorLog.shared.log("PrintManager: Printer '\(configuredPrinterName)' not found. Available printers: \(NSPrinter.printerNames)")
            completion?(false)
            return
        }

        let printInfo = NSPrintInfo()
        printInfo.printer = printer
        printInfo.paperSize = NSSize(width: paperWidth, height: paperHeight)
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.jobDisposition = .spool

        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: paperWidth, height: paperHeight))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let printOperation = NSPrintOperation(view: imageView, printInfo: printInfo)
        printOperation.showsPrintPanel = false
        printOperation.showsProgressPanel = true
        printOperation.canSpawnSeparateThread = true

        printOperation.runModal(for: NSWindow(), delegate: self, didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: Unmanaged.passRetained(CallbackBox(url: url, completion: completion)).toOpaque())
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard let contextInfo = contextInfo else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(contextInfo).takeRetainedValue()
        if success {
            ErrorLog.shared.log("PrintManager: Print job sent for \(box.url.lastPathComponent)")
        } else {
            ErrorLog.shared.log("PrintManager: Print operation failed for \(box.url.lastPathComponent)")
        }
        box.completion?(success)
    }

    func availablePrinters() -> [String] {
        NSPrinter.printerNames
    }
}

private class CallbackBox {
    let url: URL
    let completion: ((Bool) -> Void)?
    init(url: URL, completion: ((Bool) -> Void)?) {
        self.url = url
        self.completion = completion
    }
}

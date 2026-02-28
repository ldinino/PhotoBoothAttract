//
//  PrintManager.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import AppKit

class PrintManager {

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

    func printPhoto(at url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url) else {
            print("PrintManager: Could not load image at \(url.path)")
            return false
        }

        guard let printer = NSPrinter(name: configuredPrinterName) else {
            print("PrintManager: Printer '\(configuredPrinterName)' not found. Available printers: \(NSPrinter.printerNames)")
            return false
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
        printInfo.dictionary().setObject(NSNumber(value: true),
                                         forKey: NSPrintInfo.AttributeKey.headerAndFooter as NSCopying)

        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: paperWidth, height: paperHeight))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let printOperation = NSPrintOperation(view: imageView, printInfo: printInfo)
        printOperation.showsPrintPanel = false
        printOperation.showsProgressPanel = true

        let success = printOperation.run()
        if success {
            print("PrintManager: Print job sent for \(url.lastPathComponent)")
        } else {
            print("PrintManager: Print operation failed for \(url.lastPathComponent)")
        }
        return success
    }

    func availablePrinters() -> [String] {
        NSPrinter.printerNames
    }
}

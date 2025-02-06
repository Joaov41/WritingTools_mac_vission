// NSPasteboard+Extensions.swift
import AppKit

extension NSPasteboard {
    func readPDF() -> Data? {
        let pdfTypes: [NSPasteboard.PasteboardType] = [
            .pdf,
            NSPasteboard.PasteboardType("com.adobe.pdf")
        ]
        
        for type in pdfTypes {
            if let pdfData = data(forType: type) {
                return pdfData
            }
        }
        
        // Check for PDF file URL
        if let urls = readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first,
           firstURL.pathExtension.lowercased() == "pdf",
           let pdfData = try? Data(contentsOf: firstURL) {
            return pdfData
        }
        
        return nil
    }
}

extension NSPasteboard.PasteboardType {
    static let pdf = NSPasteboard.PasteboardType("com.adobe.pdf")
}

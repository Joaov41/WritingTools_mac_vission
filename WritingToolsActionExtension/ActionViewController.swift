import Cocoa

class ActionViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        extractURLFromExtensionContext()
    }
    
    /// Extracts a URL from the extension’s input items.
    func extractURLFromExtensionContext() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            completeExtension()
            return
        }
        
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier("public.url") {
                provider.loadItem(forTypeIdentifier: "public.url", options: nil) { [weak self] (item, error) in
                    guard let self = self else { return }
                    if let url = item as? URL {
                        self.handleSharedURL(url)
                    } else {
                        self.completeExtension()
                    }
                }
                return
            }
        }
        completeExtension()
    }
    
    /// Downloads the content at the URL, extracts text, and sends it to the main app.
    func handleSharedURL(_ url: URL) {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                self.completeExtension()
                return
            }
            
            let extractedText = self.extractTextFromHTML(data: data)
            self.saveTextToSharedDefaults(extractedText)
            self.openMainApp()
            self.completeExtension()
        }
        task.resume()
    }
    
    /// Uses NSAttributedString to convert HTML data to plain text.
    func extractTextFromHTML(data: Data) -> String {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributedString.string
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    /// Saves the extracted text to shared UserDefaults (using the App Group).
    func saveTextToSharedDefaults(_ text: String) {
        let sharedDefaults = UserDefaults(suiteName: "group.com.yourcompany.writingtools")
        sharedDefaults?.set(text, forKey: "sharedContent")
    }
    
    /// Opens your main app using a custom URL scheme.
    func openMainApp() {
        // Make sure to define this URL scheme (e.g. "writingtools://") in your main app's Info.plist.
        if let url = URL(string: "writingtools://processSharedText") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Completes the extension’s request.
    func completeExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}


import SwiftUI

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var geminiProvider: GeminiProvider
    @Published var openAIProvider: OpenAIProvider
    
    @Published var customInstruction: String = ""
    @Published var selectedText: String = ""
    @Published var selectedImages: [Data] = []  // Store selected image data
    @Published var isPopupVisible: Bool = false
    @Published var isProcessing: Bool = false
    @Published var previousApplication: NSRunningApplication?
    @Published var selectedVideos: [Data] = []  
    
    // (Optional) Additional property if needed
    @Published var sharedContent: String? = nil

    // Current provider with UI binding support
    @Published private(set) var currentProvider: String
    
    var activeProvider: any AIProvider {
        currentProvider == "openai" ? openAIProvider : geminiProvider
    }
    
    // Update provider and persist to settings
    func setCurrentProvider(_ provider: String) {
        currentProvider = provider
        AppSettings.shared.currentProvider = provider
        objectWillChange.send()  // Explicitly notify observers
    }
    
    private init() {
        let asettings = AppSettings.shared
        self.currentProvider = asettings.currentProvider
        
        // Initialize Gemini
        let geminiConfig = GeminiConfig(apiKey: asettings.geminiApiKey,
                                        modelName: asettings.geminiModel.rawValue)
        self.geminiProvider = GeminiProvider(config: geminiConfig)
        
        // Initialize OpenAI
        let openAIConfig = OpenAIConfig(
            apiKey: asettings.openAIApiKey,
            baseURL: asettings.openAIBaseURL,
            organization: asettings.openAIOrganization,
            project: asettings.openAIProject,
            model: asettings.openAIModel
        )
        self.openAIProvider = OpenAIProvider(config: openAIConfig)
        
        if asettings.openAIApiKey.isEmpty && asettings.geminiApiKey.isEmpty {
            print("Warning: No API keys configured.")
        }
    }
    
    // For Gemini changes
    func saveGeminiConfig(apiKey: String, model: GeminiModel) {
        AppSettings.shared.geminiApiKey = apiKey
        AppSettings.shared.geminiModel = model
        
        let config = GeminiConfig(apiKey: apiKey, modelName: model.rawValue)
        geminiProvider = GeminiProvider(config: config)
    }
    
    // For OpenAI changes
    func saveOpenAIConfig(apiKey: String, baseURL: String, organization: String?, project: String?, model: String) {
        let asettings = AppSettings.shared
        asettings.openAIApiKey = apiKey
        asettings.openAIBaseURL = baseURL
        asettings.openAIOrganization = organization
        asettings.openAIProject = project
        asettings.openAIModel = model
        
        let config = OpenAIConfig(apiKey: apiKey, baseURL: baseURL,
                                  organization: organization, project: project,
                                  model: model)
        openAIProvider = OpenAIProvider(config: config)
    }
    
    // ─── NEW: Process URL from Clipboard ─────────────────────────────
    func processURLFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let clipboardString = pasteboard.string(forType: .string),
              let url = URL(string: clipboardString),
              (url.scheme == "http" || url.scheme == "https") else {
            print("No valid URL found in clipboard")
            return
        }
        
        isProcessing = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let extractedText = self.extractTextFromHTML(data: data)
                DispatchQueue.main.async {
                    self.selectedText = extractedText
                    self.isProcessing = false
                    print("Extracted text updated from clipboard URL")
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                print("Error processing URL: \(error.localizedDescription)")
            }
        }
    }
    
    /// ─── NEW: Helper to extract plain text from HTML data ─────────────
    func extractTextFromHTML(data: Data) -> String {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attrString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attrString.string
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
    // ─────────────────────────────────────────────────────────────────────
}

extension AppState {
    func handlePDFData(_ pdfData: Data) {
        let text = PDFHandler.extractText(from: pdfData)
        selectedText = text
    }
}

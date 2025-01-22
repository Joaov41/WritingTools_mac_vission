import Foundation

struct GeminiConfig: Codable {
    var apiKey: String
    var modelName: String
}

enum GeminiModel: String, CaseIterable {
    case oneflash8b = "gemini-1.5-flash-8b-latest"
    case oneflash = "gemini-1.5-flash-latest"
    case onepro = "gemini-1.5-pro-latest"
    case twoflash = "gemini-2.0-flash-exp"
    
    var displayName: String {
        switch self {
        case .oneflash8b: return "Gemini 1.5 Flash 8B (fast)"
        case .oneflash: return "Gemini 1.5 Flash (fast & more intelligent)"
        case .onepro: return "Gemini 1.5 Pro (very intelligent, but slower & lower rate limit)"
        case .twoflash: return "Gemini 2.0 Flash (extremely intelligent & fast, recommended)"
        }
    }
}

class GeminiProvider: ObservableObject, AIProvider {
    @Published var isProcessing = false
    private var config: GeminiConfig
    
    init(config: GeminiConfig) {
        self.config = config
    }
    
    func processText(systemPrompt: String? = "You are a helpful writing assistant.", userPrompt: String, images: [Data] = []) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        let finalPrompt = systemPrompt.map { "\($0)\n\n\(userPrompt)" } ?? userPrompt
        
        guard !config.apiKey.isEmpty else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }
        
        // Create parts array with text
        var parts: [[String: Any]] = []
        parts.append(["text": finalPrompt])
        
        // Add image parts if present
        for imageData in images {
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": imageData.base64EncodedString()
                ]
            ])
        }
        
        // Always use gemini-2.0-flash-exp
        let modelName = "gemini-2.0-flash-exp"
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(config.apiKey)") else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL."])
        }
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": parts
                ]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: .fragmentsAllowed)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type."])
        }
        
        if httpResponse.statusCode != 200 {
            // Try to parse error details from response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("API Error: \(message)")
                throw NSError(domain: "GeminiAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
            print("Response data: \(String(data: data, encoding: .utf8) ?? "no data")")
            throw NSError(domain: "GeminiAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned error \(httpResponse.statusCode)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            print("Failed to parse response: \(String(data: data, encoding: .utf8) ?? "no data")")
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON response."])
        }
        
        guard let candidates = json["candidates"] as? [[String: Any]], !candidates.isEmpty else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No candidates found in the response."])
        }
        
        if let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            return text
        }
        
        throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid content in response."])
    }
    
    func cancel() {
        isProcessing = false
    }
}

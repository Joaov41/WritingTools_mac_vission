import SwiftUI
import ApplicationServices

struct PopupView: View {
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var commandsManager = CustomCommandsManager()
    let closeAction: () -> Void
    @AppStorage("use_gradient_theme") private var useGradientTheme = false
    @State private var customText: String = ""
    @State private var loadingOptions: Set<String> = []
    @State private var isCustomLoading: Bool = false
    @State private var showingCustomCommands = false

    var body: some View {
        VStack(spacing: 16) {
            // Top bar with close and add buttons
            HStack {
                Button(action: closeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.leading, 8)

                Spacer()

                Button(action: { showingCustomCommands = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 8)
            }

            // Custom input with send button ("Describe your change")
            HStack(spacing: 8) {
                TextField(appState.selectedText.isEmpty ? "Describe your change..." : "Describe your change...", text: $customText)
                    .textFieldStyle(.plain)
                    .appleStyleTextField(text: customText, isLoading: isCustomLoading, onSubmit: processCustomChange)
            }
            .padding(.horizontal)

            // Built-in options grid – show if any content exists (text, images, or videos)
            if !appState.selectedText.isEmpty ||
               !appState.selectedImages.isEmpty ||
               !appState.selectedVideos.isEmpty
            {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(WritingOption.allCases) { option in
                            OptionButton(
                                option: option,
                                action: { processOption(option) },
                                isLoading: loadingOptions.contains(option.id)
                            )
                        }
                        ForEach(commandsManager.commands) { command in
                            CustomOptionButton(
                                command: command,
                                action: { processCustomCommand(command) },
                                isLoading: loadingOptions.contains(command.id.uuidString)
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                // Force a minimum height for the grid so it is visible even when text is empty
                .frame(minHeight: 200)
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 16)
        .windowBackground(useGradient: useGradientTheme)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
        // onAppear: if video data is already present, ignore pasteboard image data.
        .onAppear {
            if !appState.selectedVideos.isEmpty {
                print("AppState contains video data; ignoring pasteboard image data.")
                return
            }
            let pasteboard = NSPasteboard.general
            if pasteboard.hasPDF {
                print("Clipboard contains PDF data.")
            } else if pasteboard.hasVideo {
                print("Clipboard contains video data.")
            } else if pasteboard.hasImage {
                print("Clipboard contains image data.")
            } else if appState.selectedText.isEmpty {
                AppState.shared.processURLFromClipboard()
            }
        }
    }

    // MARK: - Helper Methods

    private func processCustomCommand(_ command: CustomCommand) {
        loadingOptions.insert(command.id.uuidString)
        appState.isProcessing = true
        Task {
            defer {
                loadingOptions.remove(command.id.uuidString)
                appState.isProcessing = false
            }
            do {
                // If video exists, force images to be empty.
                let imagesToSend: [Data] = appState.selectedVideos.isEmpty ? appState.selectedImages : []
                let result = try await appState.activeProvider.processText(
                    systemPrompt: command.prompt,
                    userPrompt: appState.selectedText,
                    images: imagesToSend,
                    videos: appState.selectedVideos
                )
                if command.useResponseWindow {
                    await MainActor.run {
                        let window = ResponseWindow(
                            title: command.name,
                            content: result,
                            selectedText: appState.selectedText,
                            option: .proofread
                        )
                        WindowManager.shared.addResponseWindow(window)
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        simulatePaste()
                    }
                }
                closeAction()
            } catch {
                print("Error processing custom command: \(error.localizedDescription)")
            }
        }
    }

    private func processCustomChange() {
        guard !customText.isEmpty else { return }
        isCustomLoading = true
        processCustomInstruction(customText)
    }

    private func processOption(_ option: WritingOption) {
        loadingOptions.insert(option.id)
        appState.isProcessing = true
        Task {
            defer {
                loadingOptions.remove(option.id)
                appState.isProcessing = false
            }
            do {
                // Build a tailored prompt when video data exists.
                var userPrompt: String = appState.selectedText
                if !appState.selectedVideos.isEmpty {
                    if appState.selectedText.isEmpty {
                        // Set default prompt based on the option.
                        switch option {
                        case .summary:
                            userPrompt = "Summarize the content of this video."
                        case .keyPoints:
                            userPrompt = "Extract the key points from this video."
                        case .table:
                            userPrompt = "Convert the content of this video into a table."
                        default:
                            userPrompt = "This is a video, consider its content."
                        }
                    } else {
                        // If text exists, append a note.
                        userPrompt = appState.selectedText + "\n\n(This video should be considered.)"
                    }
                }
                // If video exists, force imagesToSend to be empty.
                let imagesToSend: [Data] = appState.selectedVideos.isEmpty ? appState.selectedImages : []
                print("processOption: userPrompt = \(userPrompt)")
                print("processOption: imagesToSend count = \(imagesToSend.count)")
                print("processOption: videos count = \(appState.selectedVideos.count)")
                let result = try await appState.activeProvider.processText(
                    systemPrompt: option.systemPrompt,
                    userPrompt: userPrompt,
                    images: imagesToSend,
                    videos: appState.selectedVideos
                )
                if [.summary, .keyPoints, .table].contains(option) {
                    await MainActor.run {
                        showResponseWindow(for: option, with: result)
                    }
                    closeAction()
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                    closeAction()
                    if let previousApp = appState.previousApplication {
                        previousApp.activate()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            simulatePaste()
                        }
                    }
                }
            } catch {
                print("Error processing text: \(error.localizedDescription)")
            }
        }
    }

    private func processCustomInstruction(_ instruction: String) {
        guard !instruction.isEmpty else { return }
        appState.isProcessing = true
        Task {
            do {
                let systemPrompt = """
                You are a writing and coding assistant. Your sole task is to respond to the user's instruction thoughtfully and comprehensively.
                If the instruction is a question, provide a detailed answer.
                Use Markdown formatting to make your response more readable.
                """
                let userPrompt = appState.selectedText.isEmpty ? instruction : """
                User's instruction: \(instruction)
                
                Text:
                \(appState.selectedText)
                """
                let result = try await appState.activeProvider.processText(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    images: appState.selectedImages,
                    videos: appState.selectedVideos
                )
                await MainActor.run {
                    let window = ResponseWindow(
                        title: "AI Response",
                        content: result,
                        selectedText: appState.selectedText.isEmpty ? instruction : appState.selectedText,
                        option: .proofread
                    )
                    WindowManager.shared.addResponseWindow(window)
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
                closeAction()
            } catch {
                print("Error processing text: \(error.localizedDescription)")
            }
            isCustomLoading = false
            appState.isProcessing = false
        }
    }

    private func showResponseWindow(for option: WritingOption, with result: String) {
        DispatchQueue.main.async {
            let window = ResponseWindow(
                title: "\(option.rawValue) Result",
                content: result,
                selectedText: appState.selectedText,
                option: option
            )
            WindowManager.shared.addResponseWindow(window)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

// MARK: - Supporting Views

extension PopupView {
    struct CustomLoadingButtonStyle: ButtonStyle {
        let isLoading: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(isLoading ? 0.5 : 1.0)
        }
    }

    struct OptionButton: View {
        let option: WritingOption
        let action: () -> Void
        let isLoading: Bool

        var body: some View {
            Button(action: action) {
                HStack {
                    Image(systemName: option.icon)
                    Text(option.rawValue)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
            .buttonStyle(CustomLoadingButtonStyle(isLoading: isLoading))
            .disabled(isLoading)
        }
    }

    struct CustomOptionButton: View {
        let command: CustomCommand
        let action: () -> Void
        let isLoading: Bool

        var body: some View {
            Button(action: action) {
                HStack {
                    Image(systemName: command.icon)
                    Text(command.name)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
            .buttonStyle(CustomLoadingButtonStyle(isLoading: isLoading))
            .disabled(isLoading)
        }
    }
}

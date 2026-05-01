import AppKit
import Carbon
import SwiftUI

@main
enum QuickAskApp {
    @MainActor
    private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        QuickAskLog.write("QuickAsk main started")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: QuickAskPanelController?
    private var hotKeys: [GlobalHotKey] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        QuickAskLog.write("QuickAsk launched")
        NSApp.setActivationPolicy(.accessory)

        let gemini = GeminiClient(
            apiKeyProvider: APIKeyProvider(),
            model: ProcessInfo.processInfo.environment["QUICKASK_GEMINI_MODEL"] ?? "gemini-3-flash-preview"
        )
        let controller = QuickAskController(gemini: gemini)
        panelController = QuickAskPanelController(controller: controller)

        registerHotKeys()

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Ask", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = hotKeys.isEmpty ? "QuickAsk !" : "QuickAsk"
        statusItem.menu = menu
        StatusItemHolder.shared.statusItem = statusItem
    }

    private func registerHotKeys() {
        let candidates: [(String, UInt32, UInt32)] = [
            ("Option+Space", UInt32(kVK_Space), UInt32(optionKey)),
            ("Control+Option+Space", UInt32(kVK_Space), UInt32(controlKey | optionKey))
        ]

        for candidate in candidates {
            if let hotKey = GlobalHotKey(label: candidate.0, keyCode: candidate.1, modifiers: candidate.2, callback: { [weak self] in
                Task { @MainActor in
                    self?.panelController?.toggle()
                }
            }) {
                hotKeys.append(hotKey)
                QuickAskLog.write("Registered hotkey: \(candidate.0)")
            } else {
                QuickAskLog.write("Failed to register hotkey: \(candidate.0)")
            }
        }
    }

    @objc private func showPanel() {
        panelController?.show()
    }
}

@MainActor
private final class StatusItemHolder {
    static let shared = StatusItemHolder()
    var statusItem: NSStatusItem?
}

@MainActor
final class QuickAskController: ObservableObject {
    @Published var question = ""
    @Published var answer = ""
    @Published var isLoading = false
    @Published var errorText: String?

    private let gemini: GeminiClient
    private var task: Task<Void, Never>?

    init(gemini: GeminiClient) {
        self.gemini = gemini
    }

    func submit() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }

        answer = ""
        errorText = nil
        isLoading = true
        task?.cancel()

        task = Task {
            do {
                for try await chunk in gemini.ask(trimmed) {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self.answer += chunk
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorText = error.localizedDescription
                }
            }

            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isLoading = false
    }

    func resetForNextQuestion() {
        question = ""
        answer = ""
        errorText = nil
        cancel()
    }

    func copyAnswer() {
        guard !answer.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
    }
}

@MainActor
final class QuickAskPanelController: NSObject, NSWindowDelegate {
    private let controller: QuickAskController
    private let panel: NSPanel

    init(controller: QuickAskController) {
        self.controller = controller
        let content = QuickAskView(controller: controller)
        let hosting = NSHostingView(rootView: content)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 360),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        super.init()
        panel.delegate = self
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        QuickAskLog.write("Showing panel")
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - panel.frame.width / 2
            let y = frame.maxY - panel.frame.height - 120
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        QuickAskLog.write("Hiding panel")
        panel.orderOut(nil)
        controller.cancel()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

struct QuickAskView: View {
    @ObservedObject var controller: QuickAskController
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 20, weight: .semibold))

                TextField("Ask a quick question...", text: $controller.question)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .medium))
                    .focused($focused)
                    .onSubmit {
                        controller.submit()
                    }

                if controller.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let errorText = controller.errorText {
                        Text(errorText)
                            .foregroundStyle(.red)
                    } else if controller.answer.isEmpty {
                        Text("Option+Space to open. Enter to ask. Esc to close.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(controller.answer)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(size: 15, design: .monospaced))
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("Model: \(ProcessInfo.processInfo.environment["QUICKASK_GEMINI_MODEL"] ?? "gemini-3-flash-preview")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    controller.copyAnswer()
                }
                .disabled(controller.answer.isEmpty)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .onAppear {
            focused = true
        }
        .onExitCommand {
            NSApp.keyWindow?.orderOut(nil)
            controller.cancel()
        }
    }
}

struct APIKeyProvider {
    func apiKey() throws -> String {
        if let value = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !value.isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let value = readShellEnvFile(path: "~/.quickask.env"), !value.isEmpty {
            return value
        }

        if let value = readPlainTextKeyFile(path: "~/Gemini"), !value.isEmpty {
            return value
        }

        throw GeminiError.missingAPIKey
    }

    private func readShellEnvFile(path: String) -> String? {
        let expanded = NSString(string: path).expandingTildeInPath
        guard let data = try? String(contentsOfFile: expanded, encoding: .utf8) else {
            return nil
        }

        for rawLine in data.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("GEMINI_API_KEY=") else { continue }
            let rawValue = String(line.dropFirst("GEMINI_API_KEY=".count))
            return unquote(rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func readPlainTextKeyFile(path: String) -> String? {
        let expanded = NSString(string: path).expandingTildeInPath
        return try? String(contentsOfFile: expanded, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2,
           let first = trimmed.first,
           let last = trimmed.last,
           (first == "'" || first == "\""),
           first == last {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }
}

enum GeminiError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing Gemini API key. Set GEMINI_API_KEY, ~/.quickask.env, or ~/Gemini."
        case .invalidResponse:
            return "Gemini returned an invalid response."
        case .httpError(let status, let body):
            return "Gemini HTTP \(status): \(body)"
        }
    }
}

struct GeminiClient {
    private let apiKeyProvider: APIKeyProvider
    private let model: String

    init(apiKeyProvider: APIKeyProvider, model: String) {
        self.apiKeyProvider = apiKeyProvider
        self.model = model
    }

    func ask(_ question: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let apiKey = try apiKeyProvider.apiKey()
                    var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent")!
                    components.queryItems = [URLQueryItem(name: "alt", value: "sse")]

                    var request = URLRequest(url: components.url!)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(GeminiRequest.quickAnswer(question: question, model: model))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw GeminiError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 800 { break }
                        }
                        throw GeminiError.httpError(http.statusCode, body)
                    }

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let data = payload.data(using: .utf8) else { continue }
                        let event = try JSONDecoder().decode(GeminiStreamEvent.self, from: data)
                        let text = event.candidates?.first?.content.parts.compactMap(\.text).joined() ?? ""
                        if !text.isEmpty {
                            continuation.yield(text)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

struct GeminiRequest: Encodable {
    let systemInstruction: GeminiContent
    let contents: [GeminiContent]
    let generationConfig: GenerationConfig

    static func quickAnswer(question: String, model: String) -> GeminiRequest {
        GeminiRequest(
            systemInstruction: GeminiContent(parts: [
                GeminiPart(text: """
                You are a terse macOS and developer quick-answer helper. Answer in Chinese unless the user asks otherwise.
                Reply as one compact paragraph. Do not use headings, bullets, numbered lists, or blank lines.
                Prefer inline code spans for commands, paths, flags, and key names. Avoid fenced code blocks unless the user explicitly asks for multi-line code.
                Always answer in exactly 3 short sentences in one paragraph.
                Put the best answer first, alternatives second, and caveats or verification third when useful.
                Prefer under 160 Chinese characters total when possible.
                For risky commands, start the first sentence with "风险:" then the command.
                No greetings, no filler, no explanation of your formatting.
                """)
            ]),
            contents: [
                GeminiContent(parts: [GeminiPart(text: question)])
            ],
            generationConfig: GenerationConfig(
                temperature: 0.2,
                topP: 0.8,
                maxOutputTokens: Self.maxOutputTokens(),
                thinkingConfig: Self.thinkingConfig(for: model)
            )
        )
    }

    private static func maxOutputTokens() -> Int {
        let rawValue = ProcessInfo.processInfo.environment["QUICKASK_MAX_OUTPUT_TOKENS"] ?? "300"
        return Int(rawValue).map { min(max($0, 32), 512) } ?? 300
    }

    private static func thinkingConfig(for model: String) -> ThinkingConfig? {
        if model.hasPrefix("gemini-3") {
            let level = ProcessInfo.processInfo.environment["QUICKASK_THINKING_LEVEL"] ?? "minimal"
            return ThinkingConfig(thinkingLevel: level, thinkingBudget: nil)
        }

        if model.hasPrefix("gemini-2.5-flash") {
            let budget = ProcessInfo.processInfo.environment["QUICKASK_THINKING_BUDGET"].flatMap(Int.init) ?? 0
            return ThinkingConfig(thinkingLevel: nil, thinkingBudget: budget)
        }

        return nil
    }
}

struct GenerationConfig: Encodable {
    let temperature: Double
    let topP: Double
    let maxOutputTokens: Int
    let thinkingConfig: ThinkingConfig?
}

struct ThinkingConfig: Encodable {
    let thinkingLevel: String?
    let thinkingBudget: Int?
}

struct GeminiContent: Codable {
    let parts: [GeminiPart]
}

struct GeminiPart: Codable {
    let text: String?
}

struct GeminiStreamEvent: Decodable {
    let candidates: [GeminiCandidate]?
}

struct GeminiCandidate: Decodable {
    let content: GeminiContent
}

final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void
    private let label: String

    init?(label: String, keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        self.label = label
        self.callback = callback

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let handler: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            QuickAskLog.write("Pressed hotkey: \(hotKey.label)")
            hotKey.callback()
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5141534B), id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }
}

enum QuickAskLog {
    static func write(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/quickask.log")

        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

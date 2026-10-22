import AppKit
import AVFoundation
import NaturalLanguage
import Translation
import UniformTypeIdentifiers

@MainActor
final class Translator: ObservableObject {
    enum Status: Equatable {
        case idle, reading, translating, stopped
        case done(from: Locale.Language, to: Locale.Language)
        case failed(String)
    }

    private enum Keys {
        static let target = "target"
        static let fallback = "fallback"
        static let highQuality = "highQuality"
    }

    private struct Route: Equatable {
        let source: Locale.Language?
        let target: Locale.Language
        let highQuality: Bool

        @available(macOS 26.4, *)
        var strategy: TranslationSession.Strategy { highQuality ? .highFidelity : .lowLatency }
    }

    @Published var input = "" {
        didSet { if input != oldValue { scheduleTranslation() } }
    }
    @Published var source: Locale.Language? {
        didSet { scheduleTranslation(after: .zero) }
    }
    @Published var target: Locale.Language {
        didSet {
            defaults.set(target.minimalIdentifier, forKey: Keys.target)
            scheduleTranslation(after: .zero)
        }
    }
    @Published var highQuality: Bool {
        didSet {
            defaults.set(highQuality, forKey: Keys.highQuality)
            scheduleTranslation(after: .zero)
        }
    }
    @Published private(set) var image: NSImage?
    @Published private(set) var output = ""
    @Published private(set) var status = Status.idle
    @Published private(set) var detected: Locale.Language?
    @Published private(set) var languages: [Locale.Language] = []
    @Published private(set) var configuration: TranslationSession.Configuration?
    @Published private(set) var translationTarget: Locale.Language?

    private let defaults = UserDefaults.standard
    private let speech = AVSpeechSynthesizer()
    private var pending = ""
    private var route: Route?
    private var runID = 0
    private var debounce: Task<Void, Never>?
    private var job: Task<Void, Never>?

    private var fallback: Locale.Language? {
        get { defaults.string(forKey: Keys.fallback).map(Locale.Language.init(identifier:)) }
        set { defaults.set(newValue?.minimalIdentifier, forKey: Keys.fallback) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Keys.target)
        target = Locale.Language(identifier: saved ?? Locale.preferredLanguages.first ?? "en")
        highQuality = UserDefaults.standard.bool(forKey: Keys.highQuality)
    }

    var activeTarget: Locale.Language {
        translationTarget ?? target
    }

    var isBusy: Bool {
        status == .reading || status == .translating
    }

    var showsResult: Bool {
        !input.isBlank || status != .idle
    }

    func name(of language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    func loadLanguages() async {
        let supported = await LanguageAvailability().supportedLanguages
        languages = supported.sorted { name(of: $0) < name(of: $1) }
        if let match = languages.first(where: { $0.isSame(as: target) }), match != target {
            target = match
        }
    }

    func swapLanguages() {
        guard case let .done(from, to) = status else { return }
        let translated = output
        source = to
        target = languages.first(where: { $0.isSame(as: from) }) ?? from
        input = translated
    }

    func clear() {
        image = nil
        input = ""
        source = nil
    }

    func retry() {
        scheduleTranslation(after: .zero)
    }

    func stop() {
        job?.cancel()
        runID += 1
        dismissPresentedSession()
        status = .stopped
    }

    func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }

    func speakOutput() {
        speech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: output)
        utterance.voice = AVSpeechSynthesisVoice(language: activeTarget.minimalIdentifier)
        speech.speak(utterance)
    }

    func pasteClipboard() {
        ingest(pasteboard: .general)
    }

    func ingest(pasteboard board: NSPasteboard) {
        if let url = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL {
            Task { await ingest(file: url) }
        } else if let text = board.string(forType: .string) {
            ingest(text: text)
        } else if let image = NSImage(pasteboard: board) {
            Task { await ingest(image: image) }
        }
    }

    func ingest(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        Task { await ingest(provider) }
    }

    func ingest(file url: URL) async {
        image = await TextExtractor.preview(of: url)
        await read { try await TextExtractor.text(in: url) }
    }

    func ingest(image: NSImage) async {
        self.image = image
        await read { try await TextExtractor.text(in: image) }
    }

    func run(_ session: TranslationSession) async {
        runID += 1
        let id = runID
        let text = pending
        let lines = text.components(separatedBy: "\n")
        var translated: [String?] = lines.map { $0.isBlank ? $0 : nil }
        let requests = lines.indices.filter { translated[$0] == nil }.map {
            TranslationSession.Request(sourceText: lines[$0], clientIdentifier: String($0))
        }
        var last: TranslationSession.Response?
        do {
            for try await response in session.translate(batch: requests) {
                guard id == runID, text == pending else { return }
                guard let index = response.clientIdentifier.flatMap(Int.init) else { continue }
                translated[index] = response.targetText
                output = translated.prefix { $0 != nil }.compactMap { $0 }.joined(separator: "\n")
                last = response
            }
            guard id == runID, text == pending, let last else { return }
            finish(from: last.sourceLanguage, to: last.targetLanguage)
        } catch {
            guard id == runID, text == pending, !Task.isCancelled else { return }
            status = .failed(error.localizedDescription)
        }
        dismissPresentedSession()
    }

    private func finish(from source: Locale.Language, to target: Locale.Language) {
        status = .done(from: source, to: target)
        if !source.isSame(as: self.target) { fallback = source }
    }

    private func translateNow(_ text: String) {
        input = text
        scheduleTranslation(after: .zero)
    }

    private func ingest(text: String) {
        image = nil
        translateNow(text)
    }

    private func ingest(_ provider: NSItemProvider) async {
        if let url = await provider.fileURL() {
            await ingest(file: url)
        } else if let image = await provider.object(NSImage.self) {
            await ingest(image: image)
        } else if let text = await provider.object(NSString.self) {
            ingest(text: text as String)
        }
    }

    private func read(_ extract: () async throws -> String) async {
        status = .reading
        do {
            let text = try await extract()
            guard status == .reading else { return }
            if text.isBlank {
                status = .failed("No text found")
            } else {
                translateNow(text)
            }
        } catch {
            guard status == .reading else { return }
            status = .failed(error.localizedDescription)
        }
    }

    private func scheduleTranslation(after delay: Duration = .milliseconds(450)) {
        debounce?.cancel()
        guard !input.isBlank else {
            job?.cancel()
            pending = ""
            output = ""
            detected = nil
            status = .idle
            return
        }
        debounce = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            requestTranslation()
        }
    }

    private func requestTranslation() {
        detected = detectLanguage(of: input)
        let from = source ?? detected
        let to = resolvedTarget(from: from)
        output = ""
        if let from, from.isSame(as: to) {
            status = .failed("Already in \(name(of: to)). Pick another target.")
            return
        }
        pending = input
        status = .translating
        translationTarget = to
        let next = Route(source: from, target: to, highQuality: highQuality)
        job?.cancel()
        job = Task { await translate(along: next) }
    }

    private func translate(along next: Route) async {
        let session = await installedSession(for: next)
        guard !Task.isCancelled else { return }
        guard let session else { return present(next) }
        dismissPresentedSession()
        await run(session)
    }

    private func installedSession(for route: Route) async -> TranslationSession? {
        guard let source = route.source else { return nil }
        if #available(macOS 26.4, *) {
            let availability = LanguageAvailability(preferredStrategy: route.strategy)
            guard await availability.status(from: source, to: route.target) == .installed else { return nil }
            return TranslationSession(installedSource: source, target: route.target, preferredStrategy: route.strategy)
        }
        if #available(macOS 26.0, *) {
            guard await LanguageAvailability().status(from: source, to: route.target) == .installed else { return nil }
            return TranslationSession(installedSource: source, target: route.target)
        }
        return nil
    }

    private func present(_ next: Route) {
        if next == route {
            configuration?.invalidate()
        } else {
            route = next
            configuration = makeConfiguration(for: next)
        }
    }

    private func dismissPresentedSession() {
        configuration = nil
        route = nil
    }

    private func makeConfiguration(for route: Route) -> TranslationSession.Configuration {
        guard #available(macOS 26.4, *) else {
            return TranslationSession.Configuration(source: route.source, target: route.target)
        }
        return TranslationSession.Configuration(source: route.source, target: route.target, preferredStrategy: route.strategy)
    }

    private func resolvedTarget(from source: Locale.Language?) -> Locale.Language {
        guard let source, source.isSame(as: target), let fallback, !fallback.isSame(as: source) else { return target }
        return fallback
    }

    private func detectLanguage(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }
}

extension Locale.Language {
    func isSame(as other: Locale.Language) -> Bool {
        languageCode == other.languageCode && maximalScript == other.maximalScript
    }

    private var maximalScript: Locale.Script? {
        Locale.Language(identifier: maximalIdentifier).script
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

extension NSItemProvider {
    func fileURL() async -> URL? {
        guard hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
              let item = try? await loadItem(forTypeIdentifier: UTType.fileURL.identifier) else { return nil }
        if let url = item as? URL { return url }
        guard let data = item as? Data else { return nil }
        return URL(dataRepresentation: data, relativeTo: nil)
    }

    func object<T: NSItemProviderReading>(_ type: T.Type) async -> T? {
        guard canLoadObject(ofClass: type) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: type) { object, _ in continuation.resume(returning: object as? T) }
        }
    }
}

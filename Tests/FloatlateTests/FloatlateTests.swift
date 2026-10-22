import AppKit
import Testing
import Translation
@testable import Floatlate

@MainActor
struct FloatlateTests {
    @Test func mainMenuHandlesSelectAll() throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        textView.string = "hello world"
        let panel = NSPanel(contentRect: textView.frame, styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = textView
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(textView)
        defer { panel.orderOut(nil) }

        let selectAll = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil,
            characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ))
        #expect(MainMenu.make().performKeyEquivalent(with: selectAll))
        #expect(textView.selectedRange() == NSRange(location: 0, length: 11))
    }

    @Test func blankInputHidesResult() {
        let translator = Translator()
        translator.input = "  \n "
        #expect(!translator.showsResult)
    }

    @Test func clearingDropsTranslationInFlight() async throws {
        guard #available(macOS 26.4, *) else { return }
        let french = Locale.Language(identifier: "fr")
        let english = Locale.Language(identifier: "en")
        guard await LanguageAvailability().status(from: french, to: english) == .installed else { return }

        let translator = Translator()
        translator.input = (1...40).map { "Ceci est la phrase numéro \($0) d'un long document." }.joined(separator: "\n")
        try await waitUntil { translator.status == .translating }
        let session = TranslationSession(installedSource: french, target: english, preferredStrategy: .highFidelity)
        let run = Task { await translator.run(session) }
        try await waitUntil { !translator.output.isEmpty }
        try #require(translator.status == .translating)

        translator.clear()
        await run.value
        #expect(translator.output.isEmpty)
        #expect(translator.status == .idle)
    }

    private func waitUntil(timeout: Duration = .seconds(30), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

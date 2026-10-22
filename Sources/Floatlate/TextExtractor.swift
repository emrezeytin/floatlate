import AppKit
import PDFKit
import UniformTypeIdentifiers
import Vision

enum TextExtractor {
    enum Failure: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let name): "Can't read \(name)"
            }
        }
    }

    private static let maxScannedPages = 20

    static func text(in image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Failure.unreadable("this image")
        }
        return try await text(in: cgImage)
    }

    static func text(in url: URL) async throws -> String {
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .image) {
            guard let image = NSImage(contentsOf: url) else { throw Failure.unreadable(url.lastPathComponent) }
            return try await text(in: image)
        }
        if type.conforms(to: .pdf) {
            return try await pdfText(url)
        }
        return try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
    }

    static func preview(of url: URL) async -> NSImage? {
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .image) { return NSImage(contentsOf: url) }
        guard type.conforms(to: .pdf), let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        return render(page)
    }

    private static func text(in cgImage: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: cgImage)
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return reflow(lines)
    }

    private static func pdfText(_ url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else { throw Failure.unreadable(url.lastPathComponent) }
        if let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        var pages: [String] = []
        for index in 0..<min(document.pageCount, maxScannedPages) {
            guard let page = document.page(at: index) else { continue }
            pages.append(try await text(in: render(page)))
        }
        return pages.joined(separator: "\n\n")
    }

    private static func render(_ page: PDFPage) -> NSImage {
        let bounds = page.bounds(for: .mediaBox)
        return page.thumbnail(of: NSSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
    }

    private static func reflow(_ lines: [String]) -> String {
        guard var result = lines.first else { return "" }
        for (previous, line) in zip(lines, lines.dropFirst()) {
            result += continuesSentence(previous, line) ? " " : "\n"
            result += line
        }
        return result
    }

    private static func continuesSentence(_ previous: String, _ next: String) -> Bool {
        guard let last = previous.last, let first = next.first else { return false }
        return !".!?:;。！？".contains(last) && first.isLowercase
    }
}

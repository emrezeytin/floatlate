import AppKit

enum ScreenCapture {
    static func selectRegion() async -> NSImage? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("floatlate-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume()
            }
        }

        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }
}

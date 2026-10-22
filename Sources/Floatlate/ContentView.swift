import SwiftUI
import Translation

struct ContentView: View {
    @ObservedObject var translator: Translator
    let capture: () -> Void
    @State private var dropTargeted = false
    @State private var importing = false

    var body: some View {
        VStack(spacing: 10) {
            LanguageBar(translator: translator)
            InputCard(translator: translator, capture: capture, importing: $importing)
            if translator.showsResult {
                OutputCard(translator: translator)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(12)
        .frame(width: 400, height: 520)
        .animation(.snappy(duration: 0.25), value: translator.showsResult)
        .overlay { if dropTargeted { DropHighlight() } }
        .onDrop(of: [.fileURL, .image, .plainText], isTargeted: $dropTargeted) { providers in
            translator.ingest(providers)
            return true
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            guard case let .success(url) = result else { return }
            Task { await translator.ingest(file: url) }
        }
        .translationTask(translator.configuration) { session in
            await translator.run(session)
        }
        .task { await translator.loadLanguages() }
    }
}

private struct LanguageBar: View {
    @ObservedObject var translator: Translator
    @State private var turns = 0.0

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("From", selection: $translator.source) {
                    Label("Detect Language", systemImage: "sparkles").tag(Locale.Language?.none)
                    Divider()
                    ForEach(translator.languages, id: \.self) { language in
                        Text(translator.name(of: language)).tag(Optional(language))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                LanguageCapsule(title: sourceTitle, symbol: translator.source == nil ? "sparkles" : nil)
            }

            Button {
                withAnimation(.snappy) { turns += 1 }
                translator.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(turns * 180))
                    .frame(width: 28, height: 28)
                    .background(.quaternary.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!canSwap)
            .help("Swap languages")

            Menu {
                Picker("To", selection: $translator.target) {
                    ForEach(translator.languages, id: \.self) { language in
                        Text(translator.name(of: language)).tag(language)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                LanguageCapsule(title: translator.name(of: translator.target), symbol: nil)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .labelsHidden()
    }

    private var canSwap: Bool {
        if case .done = translator.status { return true }
        return false
    }

    private var sourceTitle: String {
        if let source = translator.source { return translator.name(of: source) }
        return translator.detected.map(translator.name(of:)) ?? "Detect"
    }
}

private struct LanguageCapsule: View {
    let title: String
    let symbol: String?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .contentShape(Capsule())
    }
}

private struct InputCard: View {
    @ObservedObject var translator: Translator
    let capture: () -> Void
    @Binding var importing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: caption) {
                if !translator.input.isEmpty || translator.image != nil {
                    IconButton("xmark", "Clear (⌘K)", action: translator.clear)
                        .keyboardShortcut("k")
                }
            }
            if translator.status == .reading, let image = translator.image {
                ReadingPreview(image: image)
            } else {
                if let image = translator.image {
                    SourceThumbnail(image: image)
                }
                editor
            }
        }
        .card(.background.opacity(0.65))
    }

    @ViewBuilder private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $translator.input)
                .font(.system(size: 15))
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9)
            if translator.input.isEmpty {
                Text("Type or paste text")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .allowsHitTesting(false)
            }
        }
        if translator.input.isEmpty {
            QuickActions(paste: translator.pasteClipboard, capture: capture) { importing = true }
        } else {
            HStack(spacing: 4) {
                IconButton("clipboard", "Paste text, image, or file (⇧⌘V)", action: translator.pasteClipboard)
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                IconButton("text.viewfinder", "Capture text from screen (⌃⌥S)", action: capture)
                IconButton("folder", "Open file (⌘O)") { importing = true }
                    .keyboardShortcut("o")
                Spacer()
                Text("\(translator.input.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }

    private var caption: String {
        if let source = translator.source { return translator.name(of: source) }
        guard let detected = translator.detected else { return "Original" }
        return "\(translator.name(of: detected)) · detected"
    }
}

private struct ReadingPreview: View {
    let image: NSImage
    @State private var scanning = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(spacing: 10) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(shape)
                .overlay { scanLine.clipShape(shape) }
                .overlay(shape.strokeBorder(.separator))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Label("Reading text…", systemImage: "text.viewfinder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding([.horizontal, .bottom], 12)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever()) { scanning = true }
        }
    }

    private var scanLine: some View {
        GeometryReader { proxy in
            LinearGradient(colors: [.clear, Color.accentColor.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)
                .offset(y: scanning ? proxy.size.height - 20 : -20)
        }
        .allowsHitTesting(false)
    }
}

private struct SourceThumbnail: View {
    let image: NSImage
    @State private var expanded = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.separator))
                .frame(height: expanded ? 200 : 52)
        }
        .buttonStyle(.plain)
        .help(expanded ? "Shrink image" : "Enlarge image")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }
}

private struct QuickActions: View {
    let paste: () -> Void
    let capture: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ActionTile("clipboard", "Paste", "⇧⌘V", action: paste)
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                ActionTile("text.viewfinder", "Capture", "⌃⌥S", action: capture)
                ActionTile("folder", "Open File", "⌘O", action: open)
                    .keyboardShortcut("o")
            }
            Text("or drop text, images, and PDFs here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
    }
}

private struct ActionTile: View {
    let symbol: String
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    init(_ symbol: String, _ title: String, _ shortcut: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(hovering ? Color.accentColor : .secondary)
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(shortcut)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(hovering ? 0.9 : 0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct OutputCard: View {
    @ObservedObject var translator: Translator
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: caption) {
                if translator.isBusy {
                    ProgressView().controlSize(.mini)
                    IconButton("stop.circle", "Stop (⌘.)", action: translator.stop)
                        .keyboardShortcut(".")
                }
            }
            ScrollView {
                result
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
            if !translator.output.isEmpty {
                HStack(spacing: 4) {
                    Spacer()
                    IconButton("speaker.wave.2", "Speak", action: translator.speakOutput)
                    Button(action: copy) {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .help("Copy translation (⇧⌘C)")
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .card(Color.accentColor.opacity(0.07))
    }

    @ViewBuilder private var result: some View {
        switch translator.status {
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
                retryButton
            }
        case .stopped:
            VStack(alignment: .leading, spacing: 10) {
                if !translator.output.isEmpty { translation }
                Label("Stopped", systemImage: "stop.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                retryButton
            }
        case .reading:
            Text("Reading text…")
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
        default:
            translation
        }
    }

    private var translation: some View {
        Text(translator.output.isEmpty ? "Translating…" : translator.output)
            .font(.system(size: 16))
            .lineSpacing(2)
            .foregroundStyle(translator.output.isEmpty ? .tertiary : .primary)
            .textSelection(.enabled)
    }

    @ViewBuilder private var retryButton: some View {
        if !translator.input.isBlank {
            Button("Try Again", action: translator.retry)
                .controlSize(.small)
        }
    }

    private var caption: String {
        let name = translator.name(of: translator.activeTarget)
        return translator.activeTarget.isSame(as: translator.target) ? name : "\(name) · auto"
    }

    private func copy() {
        translator.copyOutput()
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation { copied = false }
        }
    }
}

private struct CardHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            trailing
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 30)
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    init(_ symbol: String, _ help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 26, height: 24)
                .background(.quaternary.opacity(hovering ? 0.8 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? .primary : .secondary)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 28))
                    Text("Drop to translate")
                        .font(.headline)
                }
                .foregroundStyle(Color.accentColor)
            }
            .padding(8)
            .allowsHitTesting(false)
    }
}

private extension View {
    func card(_ fill: some ShapeStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return frame(maxHeight: .infinity)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(.separator.opacity(0.5)))
    }
}

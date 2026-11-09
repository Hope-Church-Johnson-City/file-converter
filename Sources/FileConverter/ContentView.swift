import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ConverterModel
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                titleBar
                switch model.phase {
                case .collecting:
                    if model.items.isEmpty {
                        emptyState
                            .transition(.opacity)
                    } else {
                        collecting
                            .transition(.opacity)
                    }
                case .running, .finished:
                    progress
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea(.container, edges: .top)

            if isTargeted && !model.items.isEmpty {
                dropOverlay
            }
        }
        .frame(minWidth: 520, minHeight: 580)
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .animation(.easeInOut(duration: 0.2), value: model.items.isEmpty)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard model.phase != .running else { return false }
            withAnimation { model.add(urls) }
            return true
        } isTargeted: { isTargeted = $0 }
    }

    static func chooseFiles(model: ConverterModel) {
        guard model.phase != .running else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK { model.add(panel.urls) }
    }

    // MARK: Frame

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color.accentColor.opacity(0.0)],
                startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }

    /// The window has no title bar of its own; this sits level with the window buttons.
    private var titleBar: some View {
        Text("File Converter")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
    }

    private var dropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.accentColor.opacity(0.10))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [9, 6]))
            Label("Drop to add", systemImage: "plus.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
        }
        .padding(10)
        .allowsHitTesting(false)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(isTargeted ? 0.22 : 0.12))
                        .frame(width: 112, height: 112)
                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.doc.fill")
                        .font(.system(size: 46, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .scaleEffect(isTargeted ? 1.08 : 1)

                VStack(spacing: 6) {
                    Text("Drop files or folders")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Drop a folder and the converted files go in a new folder inside it.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Self.chooseFiles(model: model)
                } label: {
                    Text("Choose Files…")
                        .padding(.horizontal, 8)
                }
                .controlSize(.large)

                HStack(spacing: 8) {
                    ExampleChip(from: "WAV", to: "MP3", symbol: "waveform")
                    ExampleChip(from: "PDF", to: "JPG", symbol: "doc.richtext")
                    ExampleChip(from: "FLAC", to: "M4A", symbol: "music.note")
                }
                .padding(.top, 6)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.primary.opacity(0.15),
                                  style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1.5, dash: [9, 6]))
            )
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 4)
        }
    }

    // MARK: Before converting

    private var collecting: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Files", trailing: "Drop more to add them")
                        VStack(spacing: 8) {
                            ForEach(model.items) { item in
                                ItemCard(item: item,
                                         format: model.format,
                                         convertCount: model.convertible(item).count) {
                                    withAnimation { model.remove(item) }
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Convert to")
                        formatTiles
                    }

                    if model.format == .mp3 {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(title: "MP3 quality")
                            Picker("MP3 quality", selection: $model.mp3Quality) {
                                ForEach(MP3Quality.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Text("320 kbps is the highest MP3 quality. Lower makes smaller files.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    }

                    if let notice = model.notice {
                        Label(notice, systemImage: "exclamationmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .animation(.easeInOut(duration: 0.2), value: model.format)
            }

            bottomBar {
                Button("Clear") { withAnimation { model.reset() } }
                    .controlSize(.large)
                Spacer()
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button {
                    model.convert()
                } label: {
                    Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.convertibleCount == 0)
            }
        }
    }

    private var formatTiles: some View {
        let formats = model.availableFormats
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: min(4, formats.count))
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(formats) { format in
                FormatTile(format: format, selected: model.format == format) {
                    withAnimation(.easeInOut(duration: 0.15)) { model.format = format }
                }
            }
        }
    }

    private var summary: String {
        let count = model.convertibleCount
        if count == 0 { return "Nothing to convert to \(model.format.title)" }
        return "\(count) file\(count == 1 ? "" : "s") to \(model.format.title)"
    }

    // MARK: Converting and done

    private var progress: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                ProgressRing(done: model.doneCount, total: model.jobs.count,
                             finished: model.phase == .finished, failed: model.failedCount > 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(progressTitle)
                        .font(.system(size: 20, weight: .semibold))
                    Text(progressSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 18)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.jobs) { job in
                        JobCard(job: job)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            bottomBar {
                if model.phase == .running {
                    Spacer()
                    Button("Stop") { model.stop() }
                        .controlSize(.large)
                } else {
                    Button {
                        model.showInFinder()
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .controlSize(.large)
                    Spacer()
                    Button {
                        withAnimation { model.reset() }
                    } label: {
                        Text("Convert More")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var progressTitle: String {
        let total = model.jobs.count
        if model.phase == .running { return "Converting to \(model.format.title)…" }
        let converted = total - model.failedCount - model.skippedCount
        if converted == total { return total == 1 ? "Converted" : "All \(total) converted" }
        return "\(converted) of \(total) converted"
    }

    private var progressSubtitle: String {
        if model.phase == .running {
            return "\(model.doneCount) of \(model.jobs.count) done"
        }
        var parts: [String] = []
        if model.bytesBefore > 0 {
            parts.append("\(byteString(model.bytesBefore)) → \(byteString(model.bytesAfter))")
        }
        if model.failedCount > 0 { parts.append("\(model.failedCount) failed") }
        if model.skippedCount > 0 { parts.append("\(model.skippedCount) stopped") }
        return parts.isEmpty ? "Done" : parts.joined(separator: " · ")
    }

    private func bottomBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12, content: content)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .background(.bar)
    }
}

func byteString(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

// MARK: - Pieces

private struct SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
    }
}

private struct ExampleChip: View {
    let from: String
    let to: String
    let symbol: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
            Text(from)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(to)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

private struct ItemCard: View {
    let item: DroppedItem
    let format: OutputFormat
    let convertCount: Int
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                destination
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove")
                .opacity(hovering ? 1 : 0)
            }
        }
        .onHover { hovering = $0 }
    }

    /// Where this item's files will end up, so nothing about the output is a surprise.
    @ViewBuilder private var destination: some View {
        if convertCount == 0 {
            Pill(text: "Skipped for \(format.rawValue.uppercased())", symbol: "minus.circle", tint: .secondary)
        } else if item.isFolder {
            Pill(text: "\(convertCount) → \(format.folderName) folder", symbol: "folder.fill", tint: .accentColor)
        } else {
            Pill(text: "Asks where to save", symbol: "square.and.arrow.down", tint: .accentColor)
        }
    }
}

private struct Pill: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
            .fixedSize()
    }
}

private struct FormatTile: View {
    let format: OutputFormat
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: format.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(height: 22)
                Text(format.rawValue.uppercased())
                    .font(.system(size: 14, weight: .bold))
                Text(format.caption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(selected ? Color.accentColor.opacity(0.85) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.accentColor.opacity(0.13)
                          : Color(nsColor: .controlBackgroundColor).opacity(hovering ? 1 : 0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.15 : 0.08),
                                  lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ProgressRing: View {
    let done: Int
    let total: Int
    let finished: Bool
    let failed: Bool

    private var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    private var tint: Color { finished ? (failed ? .orange : .green) : .accentColor }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: fraction)
            if finished {
                Image(systemName: failed ? "exclamationmark" : "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 58, height: 58)
        .animation(.spring(duration: 0.35), value: finished)
    }
}

private struct JobCard: View {
    let job: Job

    var body: some View {
        Card {
            HStack(spacing: 12) {
                status
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.input.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    switch job.state {
                    case .failed(let message):
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    case .skipped:
                        Text("Stopped before it started")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    default:
                        Text("→ " + job.outputLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 12)
                if let bytes = job.outputBytes {
                    Text(byteString(bytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .opacity(job.state == .waiting || job.state == .skipped ? 0.6 : 1)
    }

    @ViewBuilder private var status: some View {
        switch job.state {
        case .waiting:
            Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        case .working:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

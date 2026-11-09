import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ConverterModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .collecting:
                collecting
            case .running, .finished:
                progress
            }
        }
        .frame(minWidth: 480, minHeight: 440)
        .dropDestination(for: URL.self) { urls, _ in
            guard model.phase != .running else { return false }
            model.add(urls)
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

    // MARK: Before converting

    private var collecting: some View {
        VStack(spacing: 0) {
            if model.items.isEmpty {
                dropZone
                    .padding(20)
            } else {
                List {
                    ForEach(model.items) { item in
                        ItemRow(item: item) { model.remove(item) }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: 3)
                            .padding(2)
                    }
                }
                Text("Drop more files or folders to add them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }

            if let notice = model.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Divider()
            footer
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text("Drop files or folders here")
                .font(.title2.weight(.medium))
            Text("Audio: WAV, AIFF, MP3, M4A, FLAC\nImages and PDFs")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose…") { Self.chooseFiles(model: model) }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        )
        .contentShape(Rectangle())
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Picker("Convert to", selection: $model.format) {
                    ForEach(model.availableFormats) { Text($0.title).tag($0) }
                }
                .fixedSize()

                if model.format == .mp3 {
                    Picker("Quality", selection: $model.mp3Quality) {
                        ForEach(MP3Quality.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                }

                Spacer()

                if !model.items.isEmpty {
                    Button("Clear") { model.reset() }
                }
                Button("Convert") { model.convert() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.items.isEmpty)
            }

            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var explanation: String {
        let folder = "A folder gets a new “\(model.format.folderName)” folder inside it with the converted files."
        let single = "A single file asks where to save it and what to call it."
        if model.format.isAudio { return folder + " " + single }
        return folder + " " + single + " PDFs are saved at 300 DPI, one image per page."
    }

    // MARK: Converting and done

    private var progress: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(progressTitle)
                    .font(.headline)
                ProgressView(value: Double(model.doneCount), total: Double(max(model.jobs.count, 1)))
            }
            .padding(16)

            List(model.jobs) { job in
                JobRow(job: job)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()
            HStack {
                if model.phase == .running {
                    Spacer()
                    Button("Stop") { model.stop() }
                } else {
                    Text("Drop more files to start again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show in Finder") { model.showInFinder() }
                    Button("Convert More") { model.reset() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
    }

    private var progressTitle: String {
        let total = model.jobs.count
        if model.phase == .running {
            return "Converting \(min(model.doneCount + 1, total)) of \(total)…"
        }
        let converted = total - model.failedCount - model.skippedCount
        var title = "\(converted) of \(total) converted"
        if model.failedCount > 0 { title += ", \(model.failedCount) failed" }
        if model.skippedCount > 0 { title += ", \(model.skippedCount) stopped" }
        return title
    }
}

private struct ItemRow: View {
    let item: DroppedItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
        .padding(.vertical, 3)
    }
}

private struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            status
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.input.lastPathComponent)
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
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var status: some View {
        switch job.state {
        case .waiting:
            Image(systemName: "circle").foregroundStyle(.tertiary)
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

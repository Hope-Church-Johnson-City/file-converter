import AppKit
import Foundation

/// Something dropped on the window: a folder (its top-level files) or a single file.
struct DroppedItem: Identifiable {
    let id = UUID()
    let url: URL
    let isFolder: Bool
    /// For a folder, the files directly inside it that the app can read.
    let files: [URL]

    var name: String { url.lastPathComponent }

    init?(url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        self.url = url
        self.isFolder = isDir.boolValue
        if isDir.boolValue {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])) ?? []
            files = contents
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .filter { fileKind(of: $0) != nil }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } else {
            guard fileKind(of: url) != nil else { return nil }
            files = [url]
        }
    }

    var kinds: Set<FileKind> { Set(files.compactMap(fileKind(of:))) }

    var detail: String {
        if isFolder {
            let audio = files.filter { fileKind(of: $0) == .audio }.count
            let pdfs = files.filter { fileKind(of: $0) == .pdf }.count
            let images = files.filter { fileKind(of: $0) == .image }.count
            let parts = [
                audio > 0 ? "\(audio) audio file\(audio == 1 ? "" : "s")" : nil,
                pdfs > 0 ? "\(pdfs) PDF\(pdfs == 1 ? "" : "s")" : nil,
                images > 0 ? "\(images) image\(images == 1 ? "" : "s")" : nil,
            ].compactMap { $0 }
            return parts.isEmpty ? "No files it can convert" : "Folder · " + parts.joined(separator: ", ")
        }
        if fileKind(of: url) == .pdf {
            let pages = Engine.pdfPageCount(url)
            return "PDF · \(pages) page\(pages == 1 ? "" : "s")"
        }
        return url.pathExtension.uppercased()
    }
}

struct Job: Identifiable {
    enum State: Equatable {
        case waiting, working, done, skipped, failed(String)
    }

    let id = UUID()
    let input: URL
    let output: URL
    var state: State = .waiting
    var inputBytes: Int64 = 0
    /// Set once the file is converted; a multi-page PDF counts all its pages.
    var outputBytes: Int64?

    /// What the row shows as the result: for a multi-page PDF, the page files.
    var outputLabel: String {
        if fileKind(of: input) == .pdf, output.pathExtension != "pdf" {
            let pages = Engine.pdfPageCount(input)
            if pages > 1 {
                let urls = Engine.pdfPageURLs(base: output, pageCount: pages)
                return "\(urls.first!.lastPathComponent) … \(urls.last!.lastPathComponent)"
            }
        }
        return output.lastPathComponent
    }
}

@MainActor
final class ConverterModel: ObservableObject {
    static let shared = ConverterModel()

    enum Phase { case collecting, running, finished }

    @Published var items: [DroppedItem] = []
    @Published var jobs: [Job] = []
    @Published var phase: Phase = .collecting
    @Published var notice: String?

    @Published var format: OutputFormat = .mp3 {
        didSet {
            // Remember audio and image choices apart, so dropping PDFs after a run
            // of MP3s goes back to JPG.
            UserDefaults.standard.set(format.rawValue, forKey: format.isAudio ? "audioFormat" : "imageFormat")
        }
    }

    @Published var mp3Quality: MP3Quality = .k320 {
        didSet { UserDefaults.standard.set(mp3Quality.rawValue, forKey: "mp3Bitrate") }
    }

    private var queue: OperationQueue?
    /// What "Show in Finder" selects when the run is over.
    private(set) var results: [URL] = []

    init() {
        mp3Quality = MP3Quality(rawValue: UserDefaults.standard.integer(forKey: "mp3Bitrate")) ?? .k320
    }

    var kindsPresent: Set<FileKind> { items.reduce(into: []) { $0.formUnion($1.kinds) } }

    var availableFormats: [OutputFormat] {
        let kinds = kindsPresent
        let formats = OutputFormat.allCases.filter { format in kinds.contains { format.accepts($0) } }
        return formats.isEmpty ? OutputFormat.allCases : formats
    }

    /// Files in this item that the chosen format would convert.
    func convertible(_ item: DroppedItem) -> [URL] {
        item.files.filter { fileKind(of: $0).map(format.accepts) == true && !format.matches($0) }
    }

    var convertibleCount: Int { items.reduce(0) { $0 + convertible($1).count } }

    var bytesBefore: Int64 { jobs.filter { $0.outputBytes != nil }.reduce(0) { $0 + $1.inputBytes } }
    var bytesAfter: Int64 { jobs.reduce(0) { $0 + ($1.outputBytes ?? 0) } }

    var doneCount: Int { jobs.filter { $0.state != .waiting && $0.state != .working }.count }
    var failedCount: Int { jobs.filter { if case .failed = $0.state { true } else { false } }.count }
    var skippedCount: Int { jobs.filter { $0.state == .skipped }.count }

    func add(_ urls: [URL]) {
        if phase == .finished { reset() }
        guard phase == .collecting else { return }
        notice = nil
        let existing = Set(items.map(\.url.standardizedFileURL))
        let fresh = urls.filter { !existing.contains($0.standardizedFileURL) }
        let new = fresh.compactMap(DroppedItem.init(url:))
        if new.count < fresh.count {
            notice = "Some of those aren't audio, image or PDF files, so they were left out."
        }
        items += new
        pickFormat()
    }

    func remove(_ item: DroppedItem) {
        items.removeAll { $0.id == item.id }
        pickFormat()
    }

    func reset() {
        items = []
        jobs = []
        results = []
        notice = nil
        phase = .collecting
    }

    private func pickFormat() {
        let kinds = kindsPresent
        guard !kinds.isEmpty else { return }
        let preferAudio = kinds.contains(.audio)
        let saved = UserDefaults.standard.string(forKey: preferAudio ? "audioFormat" : "imageFormat")
        let wanted = saved.flatMap(OutputFormat.init(rawValue:)) ?? (preferAudio ? .mp3 : .jpg)
        if !availableFormats.contains(format) || format.isAudio != preferAudio {
            format = availableFormats.contains(wanted) ? wanted : availableFormats[0]
        }
    }

    // MARK: Converting

    func convert() {
        let format = format
        var plan: [Job] = []
        var results: [URL] = []

        // Folders: everything inside goes to a new folder within it, named for the format.
        for item in items where item.isFolder {
            let files = convertible(item)
            guard !files.isEmpty else { continue }
            let folder = item.url.appendingPathComponent(format.folderName, isDirectory: true)
            results.append(folder)
            for file in files {
                let name = file.deletingPathExtension().lastPathComponent + "." + format.fileExtension
                plan.append(Job(input: file, output: folder.appendingPathComponent(name)))
            }
        }

        // Single files: ask where to save, with the name ready to change.
        let loose = items.filter { !$0.isFolder }.flatMap(convertible)
        if loose.count == 1 {
            guard let output = askSaveLocation(for: loose[0], format: format) else { return }
            plan.append(Job(input: loose[0], output: output))
            results.append(contentsOf: firstOutputs(input: loose[0], output: output))
        } else if loose.count > 1 {
            guard let folder = askFolder(count: loose.count, near: loose[0], format: format) else { return }
            for file in loose {
                let name = file.deletingPathExtension().lastPathComponent + "." + format.fileExtension
                let output = folder.appendingPathComponent(name)
                plan.append(Job(input: file, output: output))
                results.append(contentsOf: firstOutputs(input: file, output: output))
            }
        }

        guard !plan.isEmpty else {
            notice = "Nothing here to convert to \(format.title). Files already in that format are left alone."
            return
        }

        for index in plan.indices {
            plan[index].inputBytes = fileSize(plan[index].input)
        }
        jobs = plan
        self.results = results
        notice = nil
        phase = .running
        run(format: format, bitrate: mp3Quality.rawValue)
    }

    private func firstOutputs(input: URL, output: URL) -> [URL] {
        Engine.outputURLs(input: input, output: output)
    }

    private func run(format: OutputFormat, bitrate: Int) {
        let queue = OperationQueue()
        // LAME and afconvert each use one core, so one file per core.
        queue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
        queue.qualityOfService = .userInitiated
        self.queue = queue

        for job in jobs {
            let id = job.id
            queue.addOperation { [weak self] in
                Task { @MainActor in self?.update(id, .working) }
                let state: Job.State
                var bytes: Int64?
                do {
                    try Engine.convert(job.input, to: job.output, format: format, mp3Bitrate: bitrate)
                    state = .done
                    bytes = Engine.outputURLs(input: job.input, output: job.output).reduce(0) { $0 + fileSize($1) }
                } catch {
                    state = .failed(error.localizedDescription)
                }
                Task { @MainActor in self?.update(id, state, outputBytes: bytes) }
            }
        }
    }

    private func update(_ id: UUID, _ state: Job.State, outputBytes: Int64? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        // A late "working" must not overwrite a result that already arrived.
        if state == .working && jobs[index].state != .waiting { return }
        jobs[index].state = state
        jobs[index].outputBytes = outputBytes
        if phase == .running && doneCount == jobs.count { finish() }
    }

    func stop() {
        queue?.cancelAllOperations()
        // Files already being converted finish; the rest are marked skipped.
        for index in jobs.indices where jobs[index].state == .waiting {
            jobs[index].state = .skipped
        }
        if doneCount == jobs.count { finish() }
    }

    private func finish() {
        phase = .finished
        queue = nil
        NSApp.requestUserAttention(.informationalRequest)
    }

    func showInFinder() {
        let existing = results.filter { FileManager.default.fileExists(atPath: $0.path) }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }

    // MARK: Panels

    private func askSaveLocation(for input: URL, format: OutputFormat) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save \(format.title)"
        panel.prompt = "Convert"
        panel.directoryURL = input.deletingLastPathComponent()
        panel.nameFieldStringValue = input.deletingPathExtension().lastPathComponent + "." + format.fileExtension
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        if fileKind(of: input) == .pdf {
            let pages = Engine.pdfPageCount(input)
            if pages > 1 {
                panel.message = "This PDF has \(pages) pages. Each page is saved as its own file: Name-1, Name-2 and so on."
            }
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func askFolder(count: Int, near: URL, format: OutputFormat) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder"
        panel.message = "Choose where to save the \(count) \(format.title) files."
        panel.prompt = "Save Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = near.deletingLastPathComponent()
        return panel.runModal() == .OK ? panel.url : nil
    }
}

func fileSize(_ url: URL) -> Int64 {
    Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
}

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What a dropped file is, as far as converting goes.
enum FileKind {
    case audio, image, pdf
}

func fileKind(of url: URL) -> FileKind? {
    guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
    if type.conforms(to: .pdf) { return .pdf }
    if type.conforms(to: .audio) { return .audio }
    // Only images ImageIO can actually read; .psd and the like would just fail later.
    if type.conforms(to: .image) {
        let readable = (CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []
        return readable.contains(type.identifier) ? .image : nil
    }
    return nil
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case mp3, m4a, wav, aiff, jpg, png

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mp3: return "MP3"
        case .m4a: return "M4A (AAC)"
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .jpg: return "JPG"
        case .png: return "PNG"
        }
    }

    var fileExtension: String { rawValue }

    /// The folder made inside a dropped folder, e.g. "MP3s".
    var folderName: String {
        switch self {
        case .m4a: return "M4As"
        case .aiff: return "AIFFs"
        default: return rawValue.uppercased() + "s"
        }
    }

    var contentType: UTType {
        switch self {
        case .mp3: return .mp3
        case .m4a: return .mpeg4Audio
        case .wav: return .wav
        case .aiff: return .aiff
        case .jpg: return .jpeg
        case .png: return .png
        }
    }

    var isAudio: Bool { [.mp3, .m4a, .wav, .aiff].contains(self) }

    func accepts(_ kind: FileKind) -> Bool {
        isAudio ? kind == .audio : (kind == .image || kind == .pdf)
    }

    /// True when the file is already this format, so a folder of WAVs and MP3s
    /// only converts the WAVs.
    func matches(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: contentType)
    }
}

/// MP3 bitrates offered. Constant bitrate keeps every stem of a multitrack the
/// same length and in sync, which variable bitrate doesn't promise in every player.
enum MP3Quality: Int, CaseIterable, Identifiable {
    case k320 = 320, k256 = 256, k192 = 192

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .k320: return "320 kbps (best)"
        case .k256: return "256 kbps"
        case .k192: return "192 kbps (smallest)"
        }
    }
}

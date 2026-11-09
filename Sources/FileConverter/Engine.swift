import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ConvertError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// The conversions themselves. Everything here blocks, so it runs off the main thread.
enum Engine {
    static let pdfDPI: CGFloat = 300
    static let jpegQuality = 0.9

    static func convert(_ input: URL, to output: URL, format: OutputFormat, mp3Bitrate: Int) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: output.path) { try fm.removeItem(at: output) }

        switch format {
        case .mp3:
            try encodeMP3(input, output, bitrate: mp3Bitrate)
        case .m4a:
            try afconvert(input, output, ["-f", "m4af", "-d", "aac", "-b", "256000", "-q", "127"])
        case .wav:
            try afconvert(input, output, ["-f", "WAVE", "-d", pcmFormat(input, bigEndian: false)])
        case .aiff:
            try afconvert(input, output, ["-f", "AIFF", "-d", pcmFormat(input, bigEndian: true)])
        case .jpg, .png:
            if fileKind(of: input) == .pdf {
                try renderPDF(input, base: output, format: format)
            } else {
                try convertImage(input, output, format: format)
            }
        }
    }

    // MARK: Audio

    static func encodeMP3(_ input: URL, _ output: URL, bitrate: Int) throws {
        guard let lame = lameURL() else {
            throw ConvertError("The MP3 encoder is missing from the app. Rebuild it with scripts/build-app.sh.")
        }
        let args = ["--quiet", "-b", String(bitrate), "-q", "2"]

        let ext = input.pathExtension.lowercased()
        if ["wav", "wave", "aif", "aiff"].contains(ext) {
            do {
                try run(lame, args + [input.path, output.path])
                return
            } catch {
                try? FileManager.default.removeItem(at: output)
            }
        }

        // LAME only reads plain WAV/AIFF with one or two channels. Anything else
        // (FLAC, M4A, a 6-channel WAV) is decoded by Core Audio to a temporary WAV first.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: temp) }
        var decode = ["-f", "WAVE", "-d", "LEI24"]
        if channelCount(input) > 2 { decode += ["-c", "2", "--mix"] }
        try run(afconvertURL, decode + [input.path, temp.path])
        do {
            try run(lame, args + [temp.path, output.path])
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    static func afconvert(_ input: URL, _ output: URL, _ options: [String]) throws {
        do {
            try run(afconvertURL, options + [input.path, output.path])
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    /// 16-bit when the source is 16-bit or lossy, 24-bit otherwise, so a WAV
    /// made from an MP3 isn't padded out to a bigger file for nothing.
    static func pcmFormat(_ input: URL, bigEndian: Bool) -> String {
        let depth = (try? AVAudioFile(forReading: input))?
            .fileFormat.settings[AVLinearPCMBitDepthKey] as? Int ?? 16
        return (bigEndian ? "BEI" : "LEI") + (depth <= 16 ? "16" : "24")
    }

    static func channelCount(_ input: URL) -> Int {
        Int((try? AVAudioFile(forReading: input))?.fileFormat.channelCount ?? 2)
    }

    static let afconvertURL = URL(fileURLWithPath: "/usr/bin/afconvert")

    /// The app carries its own copy of LAME; the Homebrew one is only for running
    /// straight out of `swift run` while working on the app.
    static func lameURL() -> URL? {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "lame") { return bundled }
        return ["/opt/homebrew/bin/lame", "/usr/local/bin/lame"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func run(_ executable: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let last = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline).last.map(String.init)
            throw ConvertError(last ?? "\(executable.lastPathComponent) couldn't convert this file.")
        }
    }

    // MARK: Images and PDFs

    static func convertImage(_ input: URL, _ output: URL, format: OutputFormat) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { throw ConvertError("Couldn't read this image.") }

        // A full-size "thumbnail" is the easy way to get the image turned upright
        // from its camera orientation, which a plain decode leaves to the viewer.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ConvertError("Couldn't read this image.")
        }
        try write(image, to: output, format: format, dpi: nil)
    }

    /// Output names for a PDF: one page keeps the chosen name, more pages get
    /// "Name-1.jpg", "Name-2.jpg" (zero-padded so they sort in order).
    static func pdfPageURLs(base: URL, pageCount: Int) -> [URL] {
        guard pageCount > 1 else { return [base] }
        let folder = base.deletingLastPathComponent()
        let name = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension
        let digits = String(pageCount).count
        return (1...pageCount).map { page in
            let number = String(repeating: "0", count: max(0, digits - String(page).count)) + String(page)
            return folder.appendingPathComponent("\(name)-\(number).\(ext)")
        }
    }

    static func pdfPageCount(_ url: URL) -> Int {
        CGPDFDocument(url as CFURL)?.numberOfPages ?? 0
    }

    static func renderPDF(_ input: URL, base: URL, format: OutputFormat) throws {
        guard let document = CGPDFDocument(input as CFURL) else {
            throw ConvertError("Couldn't open this PDF.")
        }
        if document.isEncrypted && !document.unlockWithPassword("") {
            throw ConvertError("This PDF is password-protected.")
        }
        let count = document.numberOfPages
        guard count > 0 else { throw ConvertError("This PDF has no pages.") }

        let outputs = pdfPageURLs(base: base, pageCount: count)
        for number in 1...count {
            guard let page = document.page(at: number) else { continue }
            let box = page.getBoxRect(.cropBox)
            let sideways = abs(page.rotationAngle) % 180 == 90
            let size = sideways ? CGSize(width: box.height, height: box.width) : box.size

            // 300 DPI, but never past 12,000 pixels on a side for oversized pages.
            let scale = min(pdfDPI / 72, 12_000 / max(size.width, size.height, 1))
            let width = Int((size.width * scale).rounded())
            let height = Int((size.height * scale).rounded())
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { throw ConvertError("Page \(number) is too large to render.") }

            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.scaleBy(x: scale, y: scale)
            // The drawing transform applies the page's own rotation; it never scales
            // up, which is why the DPI scale is set on the context above instead.
            context.concatenate(page.getDrawingTransform(
                .cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)

            guard let image = context.makeImage() else {
                throw ConvertError("Couldn't render page \(number).")
            }
            if FileManager.default.fileExists(atPath: outputs[number - 1].path) {
                try FileManager.default.removeItem(at: outputs[number - 1])
            }
            try write(image, to: outputs[number - 1], format: format, dpi: pdfDPI)
        }
    }

    static func write(_ image: CGImage, to url: URL, format: OutputFormat, dpi: CGFloat?) throws {
        var image = image
        // JPG has no transparency; without this, transparent areas come out black.
        if format == .jpg, ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo) {
            image = try flattenOnWhite(image)
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.contentType.identifier as CFString, 1, nil)
        else { throw ConvertError("Couldn't create \(url.lastPathComponent).") }

        var props: [CFString: Any] = [:]
        if format == .jpg { props[kCGImageDestinationLossyCompressionQuality] = jpegQuality }
        if let dpi {
            props[kCGImagePropertyDPIWidth] = dpi
            props[kCGImagePropertyDPIHeight] = dpi
        }
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConvertError("Couldn't save \(url.lastPathComponent).")
        }
    }

    static func flattenOnWhite(_ image: CGImage) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ConvertError("Couldn't convert this image.") }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        guard let flat = context.makeImage() else { throw ConvertError("Couldn't convert this image.") }
        return flat
    }
}

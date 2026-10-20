import AppKit
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Everything needed to convert one input file.
struct OCRJob {
    let input: URL
    let output: URL
    let textOutput: URL?
    let languages: [String]
    let accurate: Bool
    let force: Bool
    let deleteOriginal: Bool
}

/// Result of processing one file.
enum OCROutcome {
    case success(pages: Int)
    case skipped(String, pages: Int)
    case failed(String)
}

/// Turns a PDF or image into a searchable PDF: the page image is kept and an invisible
/// CoreText layer is placed over it at the positions Vision recognised. Runs synchronously;
/// call it from a background queue.
enum OCRProcessor {
    private static let renderDPI: CGFloat = 200
    private static let maxPixelSide: CGFloat = 10_000

    private struct RenderedPage { let image: CGImage; let size: CGSize }
    private struct TextLine { let text: String; let box: CGRect }

    static func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .pdf) || type.conforms(to: .image)
    }

    /// Languages Vision can recognise at the given level.
    static func supportedLanguages(accurate: Bool) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = accurate ? .accurate : .fast
        return (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
    }

    static func process(_ job: OCRJob) -> OCROutcome {
        if job.input.standardizedFileURL == job.output.standardizedFileURL {
            return .failed("Output would overwrite the original")
        }
        let pageCount: Int
        let render: (Int) -> RenderedPage?
        if UTType(filenameExtension: job.input.pathExtension)?.conforms(to: .pdf) == true {
            guard let doc = PDFDocument(url: job.input) else { return .failed("Could not open PDF") }
            if doc.isLocked { return .skipped("Password protected", pages: doc.pageCount) }
            if !job.force && hasTextLayer(doc) { return .skipped("Already has text", pages: doc.pageCount) }
            pageCount = doc.pageCount
            render = { renderPDFPage(doc.page(at: $0)) }
        } else {
            guard let source = CGImageSourceCreateWithURL(job.input as CFURL, nil) else {
                return .failed("Could not read image")
            }
            pageCount = CGImageSourceGetCount(source)
            render = { loadImage(source, index: $0) }
        }
        guard pageCount > 0 else { return .failed("No pages found") }

        // Write to a hidden temp file next to the output, then move into place, so a failure never leaves a partial PDF.
        let fm = FileManager.default
        let temp = job.output.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).ocrtmp.pdf")
        guard let consumer = CGDataConsumer(url: temp as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return .failed("Cannot write to output folder")
        }
        var text = ""
        var failure: String?
        for index in 0..<pageCount where failure == nil {
            autoreleasepool {
                guard let page = render(index) else {
                    failure = "Could not render page \(index + 1)"
                    return
                }
                let lines = recognize(page.image, job: job)
                var box = CGRect(origin: .zero, size: page.size)
                context.beginPage(mediaBox: &box)
                context.draw(page.image, in: box)
                drawInvisible(lines, in: context, pageSize: page.size)
                context.endPage()
                if job.textOutput != nil {
                    text += lines.map(\.text).joined(separator: "\n") + "\n\n"
                }
            }
        }
        context.closePDF()

        if let failure {
            try? fm.removeItem(at: temp)
            return .failed(failure)
        }
        do {
            if fm.fileExists(atPath: job.output.path) {
                _ = try fm.replaceItemAt(job.output, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: job.output)
            }
            if let textURL = job.textOutput {
                try text.write(to: textURL, atomically: true, encoding: .utf8)
            }
        } catch {
            try? fm.removeItem(at: temp)
            return .failed(error.localizedDescription)
        }
        if job.deleteOriginal {
            try? fm.trashItem(at: job.input, resultingItemURL: nil)
        }
        return .success(pages: pageCount)
    }

    private static func hasTextLayer(_ doc: PDFDocument) -> Bool {
        for index in 0..<min(doc.pageCount, 5) {
            let string = doc.page(at: index)?.string ?? ""
            if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        }
        return false
    }

    private static func renderPDFPage(_ page: PDFPage?) -> RenderedPage? {
        guard let page else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let size = page.rotation % 180 == 0 ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(renderDPI / 72, maxPixelSide / max(size.width, size.height))
        let pixelWidth = Int(size.width * scale), pixelHeight = Int(size.height * scale)
        guard pixelWidth > 0, pixelHeight > 0,
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        context.setFillColor(.white)
        context.fill(rect)
        // thumbnail(of:for:) applies the page rotation for us.
        let thumbnail = page.thumbnail(of: rect.size, for: .mediaBox)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        thumbnail.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        return RenderedPage(image: image, size: size)
    }

    private static func loadImage(_ source: CGImageSource, index: Int) -> RenderedPage? {
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if max(width, height) > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = max(width, height) }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { return nil }
        let dpi = (props[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 1 ? $0 : nil } ?? 72
        let scale = CGFloat(72 / dpi)
        return RenderedPage(image: image, size: CGSize(width: CGFloat(image.width) * scale,
                                                       height: CGFloat(image.height) * scale))
    }

    private static func recognize(_ image: CGImage, job: OCRJob) -> [TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = job.accurate ? .accurate : .fast
        request.usesLanguageCorrection = true
        let supported = Set((try? request.supportedRecognitionLanguages()) ?? [])
        let languages = job.languages.filter(supported.contains)
        if languages.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = languages
        }
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return [] // Still keep the page image.
        }
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else { return nil }
            return TextLine(text: candidate.string, box: observation.boundingBox)
        }
    }

    /// Vision's normalised boxes share PDF's bottom-left origin, so they only need scaling to page points.
    private static func drawInvisible(_ lines: [TextLine], in context: CGContext, pageSize: CGSize) {
        for line in lines {
            let rect = CGRect(x: line.box.minX * pageSize.width, y: line.box.minY * pageSize.height,
                              width: line.box.width * pageSize.width, height: line.box.height * pageSize.height)
            guard rect.width > 1, rect.height > 1 else { continue }
            let font = CTFontCreateWithName("Helvetica" as CFString, rect.height * 0.85, nil)
            let attributed = NSAttributedString(string: line.text,
                                                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            var descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, &descent, nil))
            guard width > 0 else { continue }
            context.saveGState()
            context.setTextDrawingMode(.invisible)
            context.translateBy(x: rect.minX, y: rect.minY + descent * 0.5)
            context.scaleBy(x: rect.width / width, y: 1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(ctLine, context)
            context.restoreGState()
        }
    }
}

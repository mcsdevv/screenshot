import Vision
import AppKit

class OCRService {
    enum OCRError: Error, LocalizedError, Sendable {
        case noTextFound
        case recognitionFailed(String)  // Store description instead of Error for Sendable
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .noTextFound:
                return "No text was found in the image."
            case .recognitionFailed(let description):
                return "Text recognition failed: \(description)"
            case .invalidImage:
                return "The image could not be processed."
            }
        }
    }

    // MARK: - Async/Await API

    /// Recognize text in an image using Vision framework
    func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            recognizeText(in: image) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Recognize text with bounding boxes in an image
    func recognizeTextWithBoundingBoxes(in image: CGImage) async throws -> [TextBlock] {
        try await withCheckedThrowingContinuation { continuation in
            recognizeTextWithBoundingBoxes(in: image) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Detect barcodes in an image
    func detectBarcodes(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            detectBarcodes(in: image) { result in
                continuation.resume(with: result)
            }
        }
    }

    // MARK: - Completion Handler API (for backwards compatibility)

    func recognizeText(in image: CGImage, completion: @escaping (Result<String, OCRError>) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(.failure(.recognitionFailed(error.localizedDescription)))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(.failure(.noTextFound))
                return
            }

            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }

            if recognizedStrings.isEmpty {
                completion(.failure(.noTextFound))
            } else {
                let text = recognizedStrings.joined(separator: "\n")
                completion(.success(text))
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "en-GB", "de-DE", "fr-FR", "es-ES", "it-IT", "pt-BR", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.recognitionFailed(error.localizedDescription)))
                }
            }
        }
    }

    func recognizeTextWithBoundingBoxes(in image: CGImage, completion: @escaping (Result<[TextBlock], OCRError>) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(.failure(.recognitionFailed(error.localizedDescription)))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(.failure(.noTextFound))
                return
            }

            let textBlocks = observations.compactMap { observation -> TextBlock? in
                guard let candidate = observation.topCandidates(1).first else { return nil }

                let boundingBox = observation.boundingBox
                let imageHeight = CGFloat(image.height)
                let imageWidth = CGFloat(image.width)

                let rect = CGRect(
                    x: boundingBox.origin.x * imageWidth,
                    y: (1 - boundingBox.origin.y - boundingBox.height) * imageHeight,
                    width: boundingBox.width * imageWidth,
                    height: boundingBox.height * imageHeight
                )

                return TextBlock(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: rect
                )
            }

            if textBlocks.isEmpty {
                completion(.failure(.noTextFound))
            } else {
                completion(.success(textBlocks))
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.recognitionFailed(error.localizedDescription)))
                }
            }
        }
    }

    func detectBarcodes(in image: CGImage, completion: @escaping (Result<[String], OCRError>) -> Void) {
        let request = VNDetectBarcodesRequest { request, error in
            if let error = error {
                completion(.failure(.recognitionFailed(error.localizedDescription)))
                return
            }

            guard let observations = request.results as? [VNBarcodeObservation] else {
                completion(.failure(.noTextFound))
                return
            }

            let barcodes = observations.compactMap { $0.payloadStringValue }

            if barcodes.isEmpty {
                completion(.failure(.noTextFound))
            } else {
                completion(.success(barcodes))
            }
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.recognitionFailed(error.localizedDescription)))
                }
            }
        }
    }
}

struct TextBlock: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let confidence: Float
    let boundingBox: CGRect

    var confidencePercentage: Int {
        Int(confidence * 100)
    }
}

extension OCRService {
    @MainActor
    static func recognizeAndCopy(from image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        Task { @MainActor in
            let service = OCRService()
            do {
                let text = try await service.recognizeText(in: cgImage)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } catch let error as OCRError {
                let alert = NSAlert()
                alert.messageText = "OCR Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            } catch {
                let alert = NSAlert()
                alert.messageText = "OCR Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

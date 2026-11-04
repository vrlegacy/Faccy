import AVFoundation
import CoreImage
import Foundation
import Vision

struct FaceAnalysis {
    let embedding: [Float]
    let quality: Double
    let boundingBox: CGRect
    /// Average eye height-to-width ratio, or nil when it was not measured.
    /// It drops sharply while the eyes are closed, which is how a blink is seen.
    let eyeOpenness: Double?
}

enum FaceAnalysisError: Error {
    case busy
    case noFace
    case lowQuality
    case faceTooSmall
    case featurePrintFailed

    var userMessage: String {
        switch self {
        case .busy:
            return ""
        case .noFace:
            return "No face detected. Center your face in the frame."
        case .lowQuality:
            return "Move into better light and hold still."
        case .faceTooSmall:
            return "Move a little closer to the camera."
        case .featurePrintFailed:
            return "Could not read your face. Try again."
        }
    }
}

/// Runs Vision face detection and feature-print extraction off the main thread.
final class FaceAnalyzer {
    private let queue = DispatchQueue(label: "io.github.vrlegacy.faccy.vision", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var isBusy = false

    func analyze(
        pixelBuffer: CVPixelBuffer,
        requireQuality: Bool,
        minimumQuality: Double,
        detectEyes: Bool = false,
        completion: @escaping (Result<FaceAnalysis, FaceAnalysisError>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            guard !self.isBusy else {
                DispatchQueue.main.async { completion(.failure(.busy)) }
                return
            }
            self.isBusy = true
            defer { self.isBusy = false }

            let result = self.perform(
                pixelBuffer: pixelBuffer,
                requireQuality: requireQuality,
                minimumQuality: minimumQuality,
                detectEyes: detectEyes
            )

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func perform(
        pixelBuffer: CVPixelBuffer,
        requireQuality: Bool,
        minimumQuality: Double,
        detectEyes: Bool
    ) -> Result<FaceAnalysis, FaceAnalysisError> {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        let faceRequest = VNDetectFaceRectanglesRequest()
        do {
            try handler.perform([faceRequest])
        } catch {
            return .failure(.noFace)
        }

        guard let faces = faceRequest.results, !faces.isEmpty else {
            return .failure(.noFace)
        }

        guard let face = faces.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) else {
            return .failure(.noFace)
        }

        let box = face.boundingBox
        guard box.width > 0.10, box.height > 0.12 else {
            return .failure(.faceTooSmall)
        }

        var eyeOpenness: Double?
        if detectEyes {
            let landmarksRequest = VNDetectFaceLandmarksRequest()
            landmarksRequest.inputFaceObservations = [face]
            if (try? handler.perform([landmarksRequest])) != nil,
               let landmarks = landmarksRequest.results?.first?.landmarks {
                let imageSize = CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )
                eyeOpenness = Self.eyeOpenness(
                    left: landmarks.leftEye,
                    right: landmarks.rightEye,
                    imageSize: imageSize
                )
            }
        }

        var quality = 0.0
        if requireQuality {
            let qualityRequest = VNDetectFaceCaptureQualityRequest()
            qualityRequest.inputFaceObservations = [face]
            do {
                try handler.perform([qualityRequest])
                quality = Double(qualityRequest.results?.first?.faceCaptureQuality ?? 0)
                if quality == 0 {
                    quality = Double(face.faceCaptureQuality ?? 0)
                }
            } catch {
                quality = 0
            }

            // Some Macs/cameras do not populate a quality score. In that case
            // treat the score as unknown rather than blocking enrollment.
            if quality > 0, quality < minimumQuality {
                return .failure(.lowQuality)
            }
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        let padding: CGFloat = 0.25
        let cropRect = CGRect(
            x: extent.minX + (box.minX - box.width * padding) * extent.width,
            y: extent.minY + (box.minY - box.height * padding) * extent.height,
            width: box.width * (1 + padding * 2) * extent.width,
            height: box.height * (1 + padding * 2) * extent.height
        ).intersection(extent)

        guard cropRect.width >= 32, cropRect.height >= 32 else {
            return .failure(.faceTooSmall)
        }

        guard let faceImage = context.createCGImage(ciImage, from: cropRect) else {
            return .failure(.featurePrintFailed)
        }

        let featureRequest = VNGenerateImageFeaturePrintRequest()
        featureRequest.imageCropAndScaleOption = .scaleFill

        let featureHandler = VNImageRequestHandler(cgImage: faceImage, orientation: .up, options: [:])
        do {
            try featureHandler.perform([featureRequest])
        } catch {
            return .failure(.featurePrintFailed)
        }

        guard let observation = featureRequest.results?.first,
              let embedding = Self.floats(from: observation),
              !embedding.isEmpty
        else {
            return .failure(.featurePrintFailed)
        }

        return .success(FaceAnalysis(
            embedding: embedding,
            quality: quality,
            boundingBox: box,
            eyeOpenness: eyeOpenness
        ))
    }

    /// Height-to-width ratio of each eye's landmark outline, averaged.
    private static func eyeOpenness(
        left: VNFaceLandmarkRegion2D?,
        right: VNFaceLandmarkRegion2D?,
        imageSize: CGSize
    ) -> Double? {
        let ratios = [left, right].compactMap { region -> Double? in
            guard let region, region.pointCount >= 4 else { return nil }
            let points = region.pointsInImage(imageSize: imageSize)
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max(),
                  maxX - minX > 1
            else { return nil }
            return Double((maxY - minY) / (maxX - minX))
        }
        guard !ratios.isEmpty else { return nil }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    private static func floats(from observation: VNFeaturePrintObservation) -> [Float]? {
        let count = observation.elementCount
        guard count > 0 else { return nil }

        switch observation.elementType {
        case .float:
            return observation.data.withUnsafeBytes { rawBuffer in
                let values = rawBuffer.bindMemory(to: Float.self)
                return Array(values.prefix(count))
            }
        case .double:
            return observation.data.withUnsafeBytes { rawBuffer in
                let values = rawBuffer.bindMemory(to: Double.self)
                return Array(values.prefix(count)).map(Float.init)
            }
        default:
            return nil
        }
    }

    static func distance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }

        var sum: Float = 0
        for index in lhs.indices {
            let delta = lhs[index] - rhs[index]
            sum += delta * delta
        }
        return sqrt(sum)
    }
}

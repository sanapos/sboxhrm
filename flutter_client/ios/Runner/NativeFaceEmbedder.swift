// NativeFaceEmbedder.swift
//
// iOS-native face embedding service that replaces the TFLite fallback.
//
// Pipeline:
//   1. Decode JPEG/PNG bytes -> CIImage.
//   2. VNDetectFaceLandmarksRequest -> 5-point landmarks (eyes, nose, mouth).
//   3. Similarity-transform align the face to 112x112 using the 5 landmarks
//      (same template InsightFace uses server-side).
//   4. CoreML predict with FaceNet.mlpackage (ArcFace MBF, 512-dim).
//   5. L2-normalize the embedding; return as raw Float32 bytes.
//
// Exposed via FlutterMethodChannel("sana/native_face_embedder"):
//   * ping                    -> Bool  (channel alive)
//   * isReady                 -> Bool  (CoreML model loaded)
//   * embed(bytes: Uint8List) -> Uint8List (embedding, 512 * 4 bytes) or null
//   * compareRaw(a, b)        -> Double (cosine similarity score, 0..100)
//
// This runs entirely on device (Neural Engine when available) so it is both
// fast AND uses the same architecture as the server's w600k_mbf model.

import Flutter
import Foundation
import CoreML
import Vision
import Accelerate
import UIKit
import CoreImage

@objc public final class NativeFaceEmbedder: NSObject {

    public static let shared = NativeFaceEmbedder()

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var mlModel: MLModel?
    private var inputFeatureName: String = "input"
    private var outputFeatureName: String?

    private override init() {
        super.init()
        _ = loadModel()
    }

    // MARK: - Registration

    @objc public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "sana/native_face_embedder",
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { call, result in
            NativeFaceEmbedder.shared.handle(call, result: result)
        }
    }

    // MARK: - Method channel dispatch

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "ping":
            result(true)
        case "isReady":
            result(mlModel != nil)
        case "embed":
            guard
                let args = call.arguments as? [String: Any],
                let bytes = (args["bytes"] as? FlutterStandardTypedData)?.data ?? (args["bytes"] as? Data)
            else {
                result(FlutterError(code: "bad_args", message: "Expected bytes", details: nil))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let embedding = self.embed(bytes: bytes)
                DispatchQueue.main.async {
                    if let emb = embedding {
                        result(FlutterStandardTypedData(bytes: emb))
                    } else {
                        result(nil)
                    }
                }
            }
        case "compareRaw":
            guard
                let args = call.arguments as? [String: Any],
                let a = (args["a"] as? FlutterStandardTypedData)?.data ?? (args["a"] as? Data),
                let b = (args["b"] as? FlutterStandardTypedData)?.data ?? (args["b"] as? Data)
            else {
                result(FlutterError(code: "bad_args", message: "Expected a and b", details: nil))
                return
            }
            result(cosineScore(a: a, b: b))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - CoreML model

    @discardableResult
    private func loadModel() -> Bool {
        if mlModel != nil { return true }

        // Find FaceNet.mlmodelc inside the main bundle (Xcode compiles
        // .mlpackage -> .mlmodelc at build time).
        guard let url = Bundle.main.url(forResource: "FaceNet", withExtension: "mlmodelc") else {
            NSLog("[NativeFaceEmbedder] FaceNet.mlmodelc not found in bundle")
            return false
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let model = try MLModel(contentsOf: url, configuration: config)
            mlModel = model

            if let firstInput = model.modelDescription.inputDescriptionsByName.keys.first {
                inputFeatureName = firstInput
            }
            outputFeatureName = model.modelDescription.outputDescriptionsByName.keys.first
            NSLog("[NativeFaceEmbedder] Loaded FaceNet; input=\(inputFeatureName) output=\(outputFeatureName ?? "?")")
            return true
        } catch {
            NSLog("[NativeFaceEmbedder] Failed to load FaceNet: \(error)")
            return false
        }
    }

    // MARK: - Public embedding API

    @objc public func embed(bytes: Data) -> Data? {
        guard loadModel(), let model = mlModel, let outputName = outputFeatureName else {
            return nil
        }
        guard let uiImage = UIImage(data: bytes), let cgImage = uiImage.cgImage ?? ciToCg(uiImage) else {
            NSLog("[NativeFaceEmbedder] failed to decode image")
            return nil
        }

        // 1. Detect face landmarks via Vision.
        let landmarks = detectFaceLandmarks(cgImage: cgImage)

        // 2. Align to 112x112 using either landmark similarity transform
        //    (preferred) or a center-crop fallback.
        guard let aligned112 = alignFace(cgImage: cgImage, landmarks: landmarks) else {
            NSLog("[NativeFaceEmbedder] alignment failed")
            return nil
        }

        // 3. Build a CoreML image feature from the aligned crop. The .mlpackage
        //    was compiled with scale=1/127.5, bias=-1 so we can hand raw RGB.
        guard let pixelBuffer = pixelBufferRGB112(from: aligned112) else {
            NSLog("[NativeFaceEmbedder] pixel buffer allocation failed")
            return nil
        }

        let featureProvider: MLFeatureProvider
        do {
            let imageFeature = MLFeatureValue(pixelBuffer: pixelBuffer)
            featureProvider = try MLDictionaryFeatureProvider(
                dictionary: [inputFeatureName: imageFeature]
            )
        } catch {
            NSLog("[NativeFaceEmbedder] feature provider error: \(error)")
            return nil
        }

        do {
            let prediction = try model.prediction(from: featureProvider)
            guard let ma = prediction.featureValue(for: outputName)?.multiArrayValue else {
                NSLog("[NativeFaceEmbedder] missing output \(outputName)")
                return nil
            }

            let count = ma.count
            var vec = [Float](repeating: 0, count: count)
            // MLMultiArray stores values of type either Float32 or Double.
            switch ma.dataType {
            case .float32:
                let ptr = ma.dataPointer.bindMemory(to: Float.self, capacity: count)
                for i in 0..<count { vec[i] = ptr[i] }
            case .double:
                let ptr = ma.dataPointer.bindMemory(to: Double.self, capacity: count)
                for i in 0..<count { vec[i] = Float(ptr[i]) }
            default:
                for i in 0..<count { vec[i] = ma[i].floatValue }
            }

            // L2 normalize.
            var norm: Float = 0
            vDSP_svesq(vec, 1, &norm, vDSP_Length(count))
            norm = sqrt(norm)
            if norm > 0 {
                var inv = 1.0 / norm
                vDSP_vsmul(vec, 1, &inv, &vec, 1, vDSP_Length(count))
            }

            return vec.withUnsafeBufferPointer { Data(buffer: $0) }
        } catch {
            NSLog("[NativeFaceEmbedder] prediction error: \(error)")
            return nil
        }
    }

    // MARK: - Cosine comparison

    private func cosineScore(a: Data, b: Data) -> Double {
        let count = min(a.count, b.count) / MemoryLayout<Float>.size
        guard count > 0 else { return 0 }
        var dot: Float = 0
        a.withUnsafeBytes { aBuf in
            b.withUnsafeBytes { bBuf in
                let ap = aBuf.bindMemory(to: Float.self)
                let bp = bBuf.bindMemory(to: Float.self)
                vDSP_dotpr(ap.baseAddress!, 1, bp.baseAddress!, 1, &dot, vDSP_Length(count))
            }
        }
        // Assume both are L2 normalized -> dot is cosine in [-1, 1].
        let cos = max(-1.0, min(1.0, Double(dot)))
        // Map cos -> 0..100 (matches server-side convention).
        let score = ((cos + 1.0) / 2.0) * 100.0
        return score
    }

    // MARK: - Vision landmark detection

    private struct FaceLandmarks {
        let leftEye: CGPoint
        let rightEye: CGPoint
        let nose: CGPoint
        let leftMouth: CGPoint
        let rightMouth: CGPoint
    }

    private func detectFaceLandmarks(cgImage: CGImage) -> FaceLandmarks? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("[NativeFaceEmbedder] Vision error: \(error)")
            return nil
        }
        guard
            let face = (request.results as? [VNFaceObservation])?.first,
            let lm = face.landmarks
        else { return nil }

        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let box = VNImageRectForNormalizedRect(face.boundingBox, Int(w), Int(h))

        func firstPoint(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let r = region, r.pointCount > 0 else { return nil }
            // Landmarks are normalized inside the face bounding box, Vision's
            // coordinate origin is bottom-left.
            var sx: CGFloat = 0, sy: CGFloat = 0
            let pts = r.normalizedPoints
            for p in pts {
                sx += p.x
                sy += p.y
            }
            let n = CGFloat(r.pointCount)
            let nx = sx / n
            let ny = sy / n
            let x = box.origin.x + nx * box.size.width
            let yFromBottom = box.origin.y + ny * box.size.height
            let y = h - yFromBottom // flip to top-left origin (CGImage space)
            return CGPoint(x: x, y: y)
        }

        guard
            let le = firstPoint(lm.leftEye),
            let re = firstPoint(lm.rightEye),
            let no = firstPoint(lm.nose),
            let mo = firstPoint(lm.outerLips ?? lm.innerLips)
        else { return nil }

        // For the 5pt template InsightFace expects left/right mouth corners.
        // Fall back to splitting the mouth region in halves.
        let (lMouth, rMouth) = mouthCorners(region: lm.outerLips ?? lm.innerLips, imageH: h, box: box) ?? (
            CGPoint(x: mo.x - 10, y: mo.y),
            CGPoint(x: mo.x + 10, y: mo.y)
        )

        return FaceLandmarks(
            leftEye: le,
            rightEye: re,
            nose: no,
            leftMouth: lMouth,
            rightMouth: rMouth
        )
    }

    private func mouthCorners(region: VNFaceLandmarkRegion2D?,
                               imageH h: CGFloat,
                               box: CGRect) -> (CGPoint, CGPoint)? {
        guard let r = region, r.pointCount > 1 else { return nil }
        let pts = r.normalizedPoints
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var leftIdx = 0, rightIdx = 0
        for (i, p) in pts.enumerated() {
            if p.x < minX { minX = p.x; leftIdx = i }
            if p.x > maxX { maxX = p.x; rightIdx = i }
        }
        let pL = pts[leftIdx]
        let pR = pts[rightIdx]
        let xL = box.origin.x + pL.x * box.size.width
        let yL = h - (box.origin.y + pL.y * box.size.height)
        let xR = box.origin.x + pR.x * box.size.width
        let yR = h - (box.origin.y + pR.y * box.size.height)
        return (CGPoint(x: xL, y: yL), CGPoint(x: xR, y: yR))
    }

    // MARK: - Alignment

    // InsightFace 5pt template used for w600k_*: 112x112 target.
    private static let arcTemplate: [(Float, Float)] = [
        (38.2946, 51.6963),
        (73.5318, 51.5014),
        (56.0252, 71.7366),
        (41.5493, 92.3655),
        (70.7299, 92.2041),
    ]

    private func alignFace(cgImage: CGImage, landmarks: FaceLandmarks?) -> CGImage? {
        if let lm = landmarks, let aligned = similarityAlign(cgImage: cgImage, lm: lm) {
            return aligned
        }
        return centerCropResize(cgImage: cgImage, size: 112)
    }

    private func similarityAlign(cgImage: CGImage, lm: FaceLandmarks) -> CGImage? {
        // Compute a 2D similarity transform (scale + rotation + translation)
        // mapping source 5 points to the ArcFace template via least squares
        // (Umeyama algorithm for similarity).
        let src: [(Float, Float)] = [
            (Float(lm.leftEye.x),   Float(lm.leftEye.y)),
            (Float(lm.rightEye.x),  Float(lm.rightEye.y)),
            (Float(lm.nose.x),      Float(lm.nose.y)),
            (Float(lm.leftMouth.x), Float(lm.leftMouth.y)),
            (Float(lm.rightMouth.x),Float(lm.rightMouth.y)),
        ]
        let dst = Self.arcTemplate

        // Compute centroids.
        var sxMean: Float = 0, syMean: Float = 0, dxMean: Float = 0, dyMean: Float = 0
        for i in 0..<5 {
            sxMean += src[i].0; syMean += src[i].1
            dxMean += dst[i].0; dyMean += dst[i].1
        }
        sxMean /= 5; syMean /= 5; dxMean /= 5; dyMean /= 5

        // Covariance / scale terms.
        var a: Float = 0, b: Float = 0
        var varSrc: Float = 0
        for i in 0..<5 {
            let sx = src[i].0 - sxMean
            let sy = src[i].1 - syMean
            let dx = dst[i].0 - dxMean
            let dy = dst[i].1 - dyMean
            a += sx * dx + sy * dy
            b += sx * dy - sy * dx
            varSrc += sx * sx + sy * sy
        }
        if varSrc < 1e-6 { return nil }
        let scaleCos = a / varSrc
        let scaleSin = b / varSrc

        // Affine: [scaleCos, -scaleSin, tx; scaleSin, scaleCos, ty]
        let tx = dxMean - (scaleCos * sxMean - scaleSin * syMean)
        let ty = dyMean - (scaleSin * sxMean + scaleCos * syMean)

        // CoreImage transforms operate on CIImage coordinates (origin bottom-left).
        // We'll render via CGContext in CGImage coordinates (top-left) for
        // simplicity: build a CGAffineTransform that maps source pixel -> dest pixel.
        // Note: CGAffineTransform.a/b/c/d/tx/ty convention uses column-major:
        //   x' = a*x + c*y + tx
        //   y' = b*x + d*y + ty
        // Our linear part is R = [[cos, -sin], [sin, cos]] with our scale*cos/sin.
        // So a=scaleCos, c=-scaleSin, b=scaleSin, d=scaleCos.
        let transform = CGAffineTransform(
            a: CGFloat(scaleCos),
            b: CGFloat(scaleSin),
            c: CGFloat(-scaleSin),
            d: CGFloat(scaleCos),
            tx: CGFloat(tx),
            ty: CGFloat(ty)
        )

        // Invert because CGContext uses the transform to go from user space -> device.
        // We want to render into a 112x112 buffer such that, for each dest (x',y'),
        // we sample the source at transform^{-1}(x',y').
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let width = 112
        let height = 112
        let bitmapInfo: UInt32 = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.interpolationQuality = .high
        // Clear to black.
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Apply the inverse transform so that drawing the whole source image
        // places the face at the template positions.
        let inverse = transform.inverted()
        context.concatenate(inverse)

        let srcRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        context.draw(cgImage, in: srcRect)

        return context.makeImage()
    }

    private func centerCropResize(cgImage: CGImage, size: Int) -> CGImage? {
        let w = cgImage.width
        let h = cgImage.height
        let m = min(w, h)
        let x = (w - m) / 2
        let y = (h - m) / 2
        guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: m, height: m)) else {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()
    }

    // MARK: - Utilities

    private func ciToCg(_ ui: UIImage) -> CGImage? {
        guard let ci = ui.ciImage ?? (ui.cgImage.flatMap { CIImage(cgImage: $0) }) else { return nil }
        return ciContext.createCGImage(ci, from: ci.extent)
    }

    private func pixelBufferRGB112(from cgImage: CGImage) -> CVPixelBuffer? {
        let width = 112
        let height = 112
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let base = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let rgb = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: rgb,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}

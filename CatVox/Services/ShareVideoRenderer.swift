import AVFoundation
import Foundation
import UIKit
import os

enum ShareVideoRenderer {
    struct Request {
        let scanID: UUID
        let sourceVideoURL: URL
        let analysis: CatAnalysis
    }

    enum RenderError: LocalizedError {
        case missingVideoTrack
        case exportSessionUnavailable
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack:
                return "We couldn't prepare this clip for sharing."
            case .exportSessionUnavailable:
                return "We couldn't start the share export."
            case .exportFailed:
                return "We couldn't render the share video."
            }
        }
    }

    private static let logger = Logger(subsystem: "com.kathelix.catvox", category: "ShareVideoRenderer")
    private static let renderedSharesDirectoryName = "RenderedShares"
    private static let expirationInterval: TimeInterval = 24 * 60 * 60

    static func existingRenderedVideoURL(for scanID: UUID) throws -> URL? {
        try cleanupExpiredArtifacts()

        let directoryURL = try scanDirectoryURL(for: scanID, createIfMissing: false)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return nil
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let outputURL = contents.first { url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                return false
            }

            return url.pathExtension.lowercased() == "mp4" || url.pathExtension.lowercased() == "mov"
        }

        return outputURL
    }

    static func renderVideo(for request: Request) async throws -> URL {
        try cleanupExpiredArtifacts()

        let asset = AVURLAsset(url: request.sourceVideoURL)
        guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
            logger.error("render aborted: missing video track url=\(request.sourceVideoURL.path, privacy: .public)")
            throw RenderError.missingVideoTrack
        }

        let duration = asset.duration
        let composition = AVMutableComposition()

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RenderError.exportSessionUnavailable
        }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = sourceVideoTrack.preferredTransform

        if let sourceAudioTrack = asset.tracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        let videoComposition = AVMutableVideoComposition(propertiesOf: composition)
        let renderSize = normalizedRenderSize(
            naturalSize: sourceVideoTrack.naturalSize,
            preferredTransform: sourceVideoTrack.preferredTransform
        )
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration(for: sourceVideoTrack)

        let overlayImage = makeOverlayImage(
            renderSize: renderSize,
            analysis: request.analysis
        )

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame

        let overlayLayer = CALayer()
        overlayLayer.frame = parentLayer.frame
        overlayLayer.contents = overlayImage.cgImage
        overlayLayer.contentsGravity = .resize

        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        let outputDirectory = try scanDirectoryURL(for: request.scanID, createIfMissing: true)
        try removeExistingOutputs(in: outputDirectory)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RenderError.exportSessionUnavailable
        }

        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        let outputFileType: AVFileType = exportSession.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let outputExtension = outputFileType == .mp4 ? "mp4" : "mov"
        let outputURL = outputDirectory
            .appendingPathComponent("share")
            .appendingPathExtension(outputExtension)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType

        logger.info(
            "render start scan=\(request.scanID.uuidString, privacy: .public) format=\(outputExtension, privacy: .public) size=\(Int(renderSize.width))x\(Int(renderSize.height))"
        )

        try await export(exportSession)

        logger.info(
            "render complete scan=\(request.scanID.uuidString, privacy: .public) url=\(outputURL.path, privacy: .public)"
        )

        return outputURL
    }

    static func deleteRenderedArtifacts(for scanID: UUID) throws {
        let directoryURL = try scanDirectoryURL(for: scanID, createIfMissing: false)
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
    }

    static func cleanupExpiredArtifacts() throws {
        let rootDirectory = try renderedSharesRootDirectory(createIfMissing: true)
        let fileManager = FileManager.default
        let directories = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let cutoffDate = Date().addingTimeInterval(-expirationInterval)
        for directory in directories {
            let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
            let modifiedAt = values?.contentModificationDate ?? .distantPast
            guard modifiedAt < cutoffDate else { continue }

            logger.info("cleanup expired rendered share dir=\(directory.path, privacy: .public)")
            try? fileManager.removeItem(at: directory)
        }
    }

    private static func export(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume(returning: ())

                case .failed:
                    let message = session.error?.localizedDescription ?? "unknown"
                    logger.error("render failed: \(message, privacy: .public)")
                    continuation.resume(throwing: RenderError.exportFailed(message))

                case .cancelled:
                    continuation.resume(throwing: CancellationError())

                default:
                    let message = session.error?.localizedDescription ?? "unexpected_export_state"
                    logger.error("render ended unexpectedly status=\(session.status.rawValue) error=\(message, privacy: .public)")
                    continuation.resume(throwing: RenderError.exportFailed(message))
                }
            }
        }
    }

    private static func makeOverlayImage(renderSize: CGSize, analysis: CatAnalysis) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        let persona = CatPersona.from(analysis.personaType)

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: renderSize)
            let minDimension = min(renderSize.width, renderSize.height)
            let margin = max(28, minDimension * 0.05)
            let thoughtCardHeight = min(renderSize.height * 0.34, max(170, minDimension * 0.34))
            let maxCardWidth = min(renderSize.width - (margin * 2), max(320, renderSize.width * 0.9))
            let metadataPaddingX = max(18, minDimension * 0.03)
            let metadataPaddingY = max(14, minDimension * 0.026)
            let personaText = "\(persona.emoji)  \(persona.displayName.uppercased())"
            let personaFont = UIFont.systemFont(ofSize: metadataPersonaFontSize(for: renderSize), weight: .bold)
            let emotionFont = UIFont.systemFont(ofSize: metadataEmotionFontSize(for: renderSize), weight: .semibold)
            let brandFont = UIFont.systemFont(ofSize: chipFontSize(for: renderSize) * 1.22, weight: .heavy)
            let metadataMaxWidth = min(renderSize.width * 0.58, max(240, renderSize.width - (margin * 2) - 120))
            let metadataCardRect = metadataCardRect(
                x: margin,
                y: margin,
                maxWidth: metadataMaxWidth,
                personaText: personaText,
                personaFont: personaFont,
                emotionText: analysis.primaryEmotion,
                emotionFont: emotionFont,
                horizontalPadding: metadataPaddingX,
                verticalPadding: metadataPaddingY
            )
            let brandTextWidth = min(
                renderSize.width * 0.34,
                measuredTextWidth(for: "CatVox", font: brandFont, letterSpacing: 0.4)
            )
            let brandWordmarkRect = CGRect(
                x: renderSize.width - margin - brandTextWidth,
                y: margin + 4,
                width: brandTextWidth,
                height: ceil(brandFont.lineHeight) + 2
            )
            let thoughtCardRect = CGRect(
                x: (renderSize.width - maxCardWidth) / 2,
                y: renderSize.height - margin - thoughtCardHeight,
                width: maxCardWidth,
                height: thoughtCardHeight
            )

            let cgContext = context.cgContext

            let gradientColors = [UIColor(red: 0.06, green: 0.08, blue: 0.16, alpha: 0.06).cgColor,
                                  UIColor.black.withAlphaComponent(0.30).cgColor] as CFArray
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: gradientColors,
                locations: [0, 1]
            )
            if let gradient {
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.maxY),
                    options: []
                )
            }

            drawMetadataCard(
                in: metadataCardRect,
                personaText: personaText,
                personaFont: personaFont,
                personaColor: personaUIColor(for: persona),
                emotionText: analysis.primaryEmotion,
                emotionFont: emotionFont
            )

            let brandParagraph = NSMutableParagraphStyle()
            brandParagraph.alignment = .right
            brandParagraph.lineBreakMode = .byTruncatingTail
            let brandAttributes: [NSAttributedString.Key: Any] = [
                .font: brandFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.92),
                .kern: 0.4,
                .paragraphStyle: brandParagraph,
            ]
            "CatVox".draw(
                with: brandWordmarkRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: brandAttributes,
                context: nil
            )

            let thoughtCardPath = UIBezierPath(
                roundedRect: thoughtCardRect,
                cornerRadius: max(22, minDimension * 0.04)
            )
            UIColor(white: 0.12, alpha: 0.62).setFill()
            thoughtCardPath.fill()
            UIColor.white.withAlphaComponent(0.14).setStroke()
            thoughtCardPath.lineWidth = 3
            thoughtCardPath.stroke()

            let quoteParagraph = NSMutableParagraphStyle()
            quoteParagraph.lineBreakMode = .byWordWrapping
            let watermarkFont = UIFont.systemFont(ofSize: max(12, minDimension * 0.02), weight: .semibold)
            let watermarkHeight = ceil(watermarkFont.lineHeight) + 8
            let watermarkRect = CGRect(
                x: thoughtCardRect.minX + 24,
                y: thoughtCardRect.maxY - 18 - watermarkHeight,
                width: thoughtCardRect.width - 48,
                height: watermarkHeight
            )
            let quoteRect = CGRect(
                x: thoughtCardRect.minX + 24,
                y: thoughtCardRect.minY + 26,
                width: thoughtCardRect.width - 48,
                height: max(44, watermarkRect.minY - (thoughtCardRect.minY + 36))
            )
            let quoteText = "\"\(analysis.catThought)\""
            let quoteFont = fittedThoughtFont(for: quoteText, in: quoteRect)
            let quoteAttributes: [NSAttributedString.Key: Any] = [
                .font: quoteFont,
                .foregroundColor: UIColor.white,
                .paragraphStyle: quoteParagraph,
            ]
            quoteText.draw(with: quoteRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: quoteAttributes, context: nil)

            let watermarkParagraph = NSMutableParagraphStyle()
            watermarkParagraph.alignment = .right

            let watermarkAttributes: [NSAttributedString.Key: Any] = [
                .font: watermarkFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.72),
                .paragraphStyle: watermarkParagraph,
            ]
            "Powered by Kathelix".draw(in: watermarkRect, withAttributes: watermarkAttributes)
        }
    }

    private static func drawChip(
        in rect: CGRect,
        text: String,
        textColor: UIColor,
        fillColor: UIColor,
        strokeColor: UIColor,
        font: UIFont,
        letterSpacing: CGFloat = 1.2,
        verticalInset: CGFloat = 8
    ) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = 2
        path.stroke()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .kern: letterSpacing,
            .paragraphStyle: paragraphStyle,
        ]

        let inset = rect.insetBy(dx: 18, dy: verticalInset)
        text.draw(with: inset, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
    }

    private static func drawMetadataCard(
        in rect: CGRect,
        personaText: String,
        personaFont: UIFont,
        personaColor: UIColor,
        emotionText: String,
        emotionFont: UIFont
    ) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height * 0.26)
        UIColor(white: 0.12, alpha: 0.48).setFill()
        path.fill()
        UIColor.white.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let insetX = max(18, rect.width * 0.08)
        let topInset = max(14, rect.height * 0.16)
        let interLineSpacing = max(6, rect.height * 0.08)
        let lineWidth = rect.width - (insetX * 2)

        let personaRect = CGRect(
            x: rect.minX + insetX,
            y: rect.minY + topInset,
            width: lineWidth,
            height: ceil(personaFont.lineHeight) + 4
        )
        let emotionRect = CGRect(
            x: rect.minX + insetX,
            y: personaRect.maxY + interLineSpacing,
            width: lineWidth,
            height: ceil(emotionFont.lineHeight) + 4
        )

        let personaParagraph = NSMutableParagraphStyle()
        personaParagraph.lineBreakMode = .byTruncatingTail
        let personaAttributes: [NSAttributedString.Key: Any] = [
            .font: personaFont,
            .foregroundColor: personaColor,
            .kern: 1.3,
            .paragraphStyle: personaParagraph,
        ]
        personaText.draw(with: personaRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: personaAttributes, context: nil)

        let emotionParagraph = NSMutableParagraphStyle()
        emotionParagraph.lineBreakMode = .byTruncatingTail
        let emotionAttributes: [NSAttributedString.Key: Any] = [
            .font: emotionFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.95),
            .paragraphStyle: emotionParagraph,
        ]
        emotionText.draw(with: emotionRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: emotionAttributes, context: nil)
    }

    private static func chipFontSize(for renderSize: CGSize) -> CGFloat {
        max(12, min(renderSize.width, renderSize.height) * 0.028)
    }

    private static func metadataPersonaFontSize(for renderSize: CGSize) -> CGFloat {
        max(14, min(renderSize.width, renderSize.height) * 0.028)
    }

    private static func metadataEmotionFontSize(for renderSize: CGSize) -> CGFloat {
        max(14, min(renderSize.width, renderSize.height) * 0.025)
    }

    private static func fittedThoughtFont(for text: String, in rect: CGRect) -> UIFont {
        let maxFontSize = max(
            28,
            min(rect.height * 0.24, rect.width * 0.085)
        )
        let minFontSize: CGFloat = 18
        var candidateSize = maxFontSize

        while candidateSize > minFontSize {
            let font = UIFont.systemFont(ofSize: candidateSize, weight: .bold)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraphStyle,
            ]

            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )

            if ceil(bounds.height) <= rect.height {
                return font
            }

            candidateSize -= 1
        }

        return UIFont.systemFont(ofSize: minFontSize, weight: .bold)
    }

    private static func chipWidth(
        for text: String,
        font: UIFont,
        horizontalPadding: CGFloat,
        letterSpacing: CGFloat = 1.2
    ) -> CGFloat {
        measuredTextWidth(for: text, font: font, letterSpacing: letterSpacing) + (horizontalPadding * 2)
    }

    private static func measuredTextWidth(
        for text: String,
        font: UIFont,
        letterSpacing: CGFloat
    ) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: letterSpacing,
            .paragraphStyle: paragraphStyle,
        ]

        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: .greatestFiniteMagnitude, height: ceil(font.lineHeight) + 10),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )

        return ceil(bounds.width)
    }

    private static func metadataCardRect(
        x: CGFloat,
        y: CGFloat,
        maxWidth: CGFloat,
        personaText: String,
        personaFont: UIFont,
        emotionText: String,
        emotionFont: UIFont,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat
    ) -> CGRect {
        let personaWidth = measuredTextWidth(for: personaText, font: personaFont, letterSpacing: 1.3)
        let emotionWidth = measuredTextWidth(for: emotionText, font: emotionFont, letterSpacing: 0)
        let width = min(
            maxWidth,
            max(personaWidth, emotionWidth) + (horizontalPadding * 2)
        )
        let height = ceil(personaFont.lineHeight + emotionFont.lineHeight + verticalPadding * 2 + 10)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func personaUIColor(for persona: CatPersona) -> UIColor {
        switch persona {
        case .grumpyBoss:
            return UIColor(red: 0.90, green: 0.22, blue: 0.22, alpha: 1)
        case .existentialPhilosopher:
            return UIColor(red: 0.60, green: 0.30, blue: 0.90, alpha: 1)
        case .chaoticHunter:
            return UIColor(red: 1.00, green: 0.50, blue: 0.10, alpha: 1)
        case .dramaticDiva:
            return UIColor(red: 0.90, green: 0.28, blue: 0.68, alpha: 1)
        case .affectionateSweetheart:
            return UIColor(red: 0.25, green: 0.85, blue: 0.68, alpha: 1)
        case .secretAgent:
            return UIColor(red: 0.18, green: 0.78, blue: 0.92, alpha: 1)
        }
    }

    private static func frameDuration(for track: AVAssetTrack) -> CMTime {
        let nominalFrameRate = track.nominalFrameRate
        guard nominalFrameRate.isFinite, nominalFrameRate > 0 else {
            return CMTime(value: 1, timescale: 30)
        }

        let roundedFrameRate = max(24, min(60, Int32(nominalFrameRate.rounded())))
        return CMTime(value: 1, timescale: roundedFrameRate)
    }

    private static func normalizedRenderSize(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let width = max(1, Int(abs(rect.width).rounded()))
        let height = max(1, Int(abs(rect.height).rounded()))
        return CGSize(width: width, height: height)
    }

    private static func scanDirectoryURL(for scanID: UUID, createIfMissing: Bool) throws -> URL {
        let directoryURL = try renderedSharesRootDirectory(createIfMissing: true)
            .appendingPathComponent(scanID.uuidString, isDirectory: true)

        if createIfMissing {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL
    }

    private static func renderedSharesRootDirectory(createIfMissing: Bool) throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = baseURL.appendingPathComponent(renderedSharesDirectoryName, isDirectory: true)

        if createIfMissing {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        return rootURL
    }

    private static func removeExistingOutputs(in directoryURL: URL) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for item in contents {
            try fileManager.removeItem(at: item)
        }
    }
}

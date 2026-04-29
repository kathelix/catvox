import AVFoundation
import CoreMedia
import Foundation
import PhotosUI
import UniformTypeIdentifiers

enum ImportedVideoValidationError: LocalizedError {
    case tooLong
    case tooLarge
    case proResUnsupported
    case unsupportedFormat
    case importFailed

    static func analyticsReason(for error: Error) -> String {
        guard let validationError = error as? ImportedVideoValidationError else {
            return "import_failed"
        }

        return validationError.analyticsReason
    }

    var errorDescription: String? {
        switch self {
        case .tooLong:
            return "This video is longer than 10 seconds. Please choose a shorter clip."
        case .tooLarge:
            return "This video is larger than 100 MB. Please choose a smaller clip."
        case .proResUnsupported:
            return "ProRes videos aren't supported."
        case .unsupportedFormat:
            return "This video format isn't supported."
        case .importFailed:
            return "We couldn't import this video. Please try another clip."
        }
    }

    private var analyticsReason: String {
        switch self {
        case .tooLong:
            return "too_long"
        case .tooLarge:
            return "too_large"
        case .proResUnsupported:
            return "prores_unsupported"
        case .unsupportedFormat:
            return "unsupported_format"
        case .importFailed:
            return "import_failed"
        }
    }
}

enum ImportedVideoService {
    static let maxDurationSeconds = 10.0
    static let maxFileSizeBytes = 100 * 1024 * 1024

    static func importValidatedVideo(from result: PHPickerResult) async throws -> URL {
        let localURL = try await copyPickedVideo(from: result.itemProvider)

        do {
            try await validateImportedVideo(at: localURL)
            return localURL
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            throw error
        }
    }

    static func mimeType(for videoURL: URL) -> String {
        supportedMIMEType(for: videoURL) ?? "video/quicktime"
    }

    private static func validateImportedVideo(at videoURL: URL) async throws {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw ImportedVideoValidationError.unsupportedFormat
        }

        if durationSeconds > maxDurationSeconds + 0.001 {
            throw ImportedVideoValidationError.tooLong
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else {
            throw ImportedVideoValidationError.unsupportedFormat
        }

        let formatDescriptions = try await track.load(.formatDescriptions)
        let codecs = Set(formatDescriptions.map { CMFormatDescriptionGetMediaSubType($0) })

        guard !codecs.isEmpty else {
            throw ImportedVideoValidationError.unsupportedFormat
        }

        if codecs.contains(where: isProRes) {
            throw ImportedVideoValidationError.proResUnsupported
        }

        guard codecs.allSatisfy(isSupportedCodec) else {
            throw ImportedVideoValidationError.unsupportedFormat
        }

        guard supportedMIMEType(for: videoURL) != nil else {
            throw ImportedVideoValidationError.unsupportedFormat
        }

        // File size is an operational guardrail, so surface format/codec
        // problems first and only then reject oversized otherwise-valid clips.
        let fileSize = try fileSizeBytes(for: videoURL)
        if fileSize > maxFileSizeBytes {
            throw ImportedVideoValidationError.tooLarge
        }
    }

    private static func copyPickedVideo(from provider: NSItemProvider) async throws -> URL {
        guard let typeIdentifier = preferredTypeIdentifier(for: provider) else {
            throw ImportedVideoValidationError.unsupportedFormat
        }

        let suggestedName = provider.suggestedName

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { sourceURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sourceURL else {
                    continuation.resume(throwing: ImportedVideoValidationError.importFailed)
                    return
                }

                do {
                    let copiedURL = try makeTemporaryCopy(
                        of: sourceURL,
                        suggestedName: suggestedName
                    )
                    continuation.resume(returning: copiedURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first {
            guard let type = UTType($0) else { return false }
            return type.conforms(to: .movie) || type.conforms(to: .video)
        }
    }

    private static func makeTemporaryCopy(of sourceURL: URL, suggestedName: String?) throws -> URL {
        let fileManager = FileManager.default
        let importDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("catvox-imports", isDirectory: true)

        try fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)

        let fileExtension = preferredExtension(sourceURL: sourceURL, suggestedName: suggestedName)
        let baseName = preferredBaseName(sourceURL: sourceURL, suggestedName: suggestedName)
        let destinationURL = importDirectory
            .appendingPathComponent("\(baseName)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private static func preferredBaseName(sourceURL: URL, suggestedName: String?) -> String {
        let candidate = suggestedName ?? sourceURL.deletingPathExtension().lastPathComponent
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "imported-video" : trimmed
    }

    private static func preferredExtension(sourceURL: URL, suggestedName: String?) -> String {
        let sourceExtension = sourceURL.pathExtension.lowercased()
        if !sourceExtension.isEmpty {
            return sourceExtension
        }

        if let suggestedName {
            let url = URL(fileURLWithPath: suggestedName)
            let suggestedExtension = url.pathExtension.lowercased()
            if !suggestedExtension.isEmpty {
                return suggestedExtension
            }
        }

        return "mov"
    }

    private static func fileSizeBytes(for videoURL: URL) throws -> Int {
        let values = try videoURL.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey])
        if let totalSize = values.totalFileSize {
            return totalSize
        }
        if let fileSize = values.fileSize {
            return fileSize
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    private static func supportedMIMEType(for videoURL: URL) -> String? {
        switch videoURL.pathExtension.lowercased() {
        case "mov":
            return "video/quicktime"
        case "mp4":
            return "video/mp4"
        case "m4v":
            return "video/x-m4v"
        default:
            break
        }

        if let contentType = try? videoURL.resourceValues(forKeys: [.contentTypeKey]).contentType,
           let mimeType = contentType.preferredMIMEType,
           mimeType.hasPrefix("video/") {
            return mimeType
        }

        return nil
    }

    private static func isSupportedCodec(_ codec: FourCharCode) -> Bool {
        codec == kCMVideoCodecType_H264 || codec == kCMVideoCodecType_HEVC
    }

    private static func isProRes(_ codec: FourCharCode) -> Bool {
        switch codec {
        case kCMVideoCodecType_AppleProRes422Proxy,
             kCMVideoCodecType_AppleProRes422LT,
             kCMVideoCodecType_AppleProRes422,
             kCMVideoCodecType_AppleProRes422HQ,
             kCMVideoCodecType_AppleProRes4444,
             kCMVideoCodecType_AppleProRes4444XQ:
            return true
        default:
            return false
        }
    }
}

import AVFoundation
import Foundation
import SwiftData
import UIKit

enum ScanHistoryStore {
    private static let scansDirectoryName = "Scans"

    @MainActor
    static func saveScan(
        from sourceVideoURL: URL,
        sourceType: ScanSourceType,
        analysis: CatAnalysis,
        in context: ModelContext
    ) throws -> SavedScan {
        let scanDirectory = try scanDirectoryURL(for: analysis.id, createIfMissing: true)
        let videoExtension = sourceVideoURL.pathExtension.isEmpty ? "mov" : sourceVideoURL.pathExtension
        let originalVideoURL = scanDirectory
            .appendingPathComponent("original")
            .appendingPathExtension(videoExtension)
        let thumbnailURL = scanDirectory.appendingPathComponent("thumbnail.jpg")

        try adoptVideo(at: sourceVideoURL, to: originalVideoURL)
        try generateThumbnail(for: originalVideoURL, at: thumbnailURL)

        let relativeVideoPath = relativePath(for: originalVideoURL)
        let relativeThumbnailPath = relativePath(for: thumbnailURL)

        let savedScan = SavedScan(
            id: analysis.id,
            createdAt: analysis.timestamp,
            sourceType: sourceType,
            originalVideoRelativePath: relativeVideoPath,
            thumbnailRelativePath: relativeThumbnailPath,
            primaryEmotion: analysis.primaryEmotion,
            confidenceScore: analysis.confidenceScore,
            analysisText: analysis.analysis,
            personaType: analysis.personaType,
            catThought: analysis.catThought,
            ownerTip: analysis.ownerTip
        )

        context.insert(savedScan)
        try context.save()
        return savedScan
    }

    @MainActor
    static func deleteScan(_ scan: SavedScan, from context: ModelContext) throws {
        let directoryURL = try scanDirectoryURL(for: scan.id, createIfMissing: false)
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }

        try ShareVideoRenderer.deleteRenderedArtifacts(for: scan.id)

        context.delete(scan)
        try context.save()
    }

    static func originalVideoURL(for scan: SavedScan) -> URL {
        absoluteURL(forRelativePath: scan.originalVideoRelativePath)
    }

    static func thumbnailURL(for scan: SavedScan) -> URL {
        absoluteURL(forRelativePath: scan.thumbnailRelativePath)
    }

    private static func adoptVideo(at sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let sourceIsTemporary = sourceURL.path.hasPrefix(fileManager.temporaryDirectory.path)
        if sourceIsTemporary {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } else {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func generateThumbnail(for videoURL: URL, at destinationURL: URL) throws {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 720, height: 720)

        let durationSeconds = asset.duration.seconds
        let preferredTime = durationSeconds.isFinite && durationSeconds > 0
            ? CMTime(seconds: durationSeconds / 2, preferredTimescale: 600)
            : .zero

        let cgImage: CGImage
        do {
            cgImage = try imageGenerator.copyCGImage(at: preferredTime, actualTime: nil)
        } catch {
            cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
        }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.82) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try jpegData.write(to: destinationURL, options: .atomic)
    }

    private static func scanDirectoryURL(for scanID: UUID, createIfMissing: Bool) throws -> URL {
        let directoryURL = try scansRootDirectory()
            .appendingPathComponent(scanID.uuidString, isDirectory: true)

        if createIfMissing {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL
    }

    private static func scansRootDirectory() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = baseURL.appendingPathComponent(scansDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private static func relativePath(for absoluteURL: URL) -> String {
        absoluteURL.lastPathComponents(from: scansRootDirectoryName())
    }

    private static func absoluteURL(forRelativePath relativePath: String) -> URL {
        let baseURL = try? scansRootDirectory()
        return (baseURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(relativePath)
    }

    private static func scansRootDirectoryName() -> String {
        scansDirectoryName
    }
}

private extension URL {
    func lastPathComponents(from marker: String) -> String {
        let components = pathComponents
        guard let markerIndex = components.lastIndex(of: marker) else {
            return lastPathComponent
        }
        return components[(markerIndex + 1)...].joined(separator: "/")
    }
}

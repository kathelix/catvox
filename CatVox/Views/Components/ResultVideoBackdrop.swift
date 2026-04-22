import AVFoundation
import SwiftUI
import UIKit

struct ResultVideoBackdrop: View {
    let videoURL: URL
    let ambientImageURL: URL?
    var onPlaybackFailure: (URL, String) -> Void = { _, _ in }

    @State private var ambientImage: UIImage?
    @State private var videoAspectRatio: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ambientBackdrop

                if let videoAspectRatio {
                    let fittedSize = fittedVideoSize(
                        in: geometry.size,
                        aspectRatio: videoAspectRatio
                    )

                    LoopingVideoBackground(
                        url: videoURL,
                        videoGravity: .resizeAspect,
                        backgroundColor: .clear,
                        onPlaybackFailure: onPlaybackFailure
                    )
                    .frame(width: fittedSize.width, height: fittedSize.height)
                    .shadow(color: .black.opacity(0.18), radius: 28, y: 10)
                    .overlay {
                        Rectangle()
                            .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                    }
                } else {
                    LoopingVideoBackground(
                        url: videoURL,
                        videoGravity: .resizeAspect,
                        backgroundColor: .clear,
                        onPlaybackFailure: onPlaybackFailure
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
            .clipped()
        }
        .task(id: visualContextID) {
            await loadVisualContext()
        }
    }

    @ViewBuilder
    private var ambientBackdrop: some View {
        if let ambientImage {
            Image(uiImage: ambientImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.01)
                .blur(radius: 6)
                .saturation(1.0)
                .overlay(Color.black.opacity(0.04))
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.01), location: 0.00),
                            .init(color: .black.opacity(0.03), location: 0.36),
                            .init(color: .black.opacity(0.07), location: 0.72),
                            .init(color: .black.opacity(0.10), location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .transition(.opacity)
        } else {
            Color.black
        }
    }

    private var visualContextID: String {
        "\(videoURL.path)|\(ambientImageURL?.path ?? "")"
    }

    private func fittedVideoSize(in availableSize: CGSize, aspectRatio: CGFloat) -> CGSize {
        guard availableSize.width > 0, availableSize.height > 0, aspectRatio > 0 else {
            return availableSize
        }

        let availableAspectRatio = availableSize.width / availableSize.height
        if availableAspectRatio > aspectRatio {
            let height = availableSize.height
            return CGSize(width: height * aspectRatio, height: height)
        } else {
            let width = availableSize.width
            return CGSize(width: width, height: width / aspectRatio)
        }
    }

    private func loadVisualContext() async {
        let context = await VisualContextLoader.makeVisualContext(
            videoURL: videoURL,
            ambientImageURL: ambientImageURL
        )

        guard !Task.isCancelled else { return }

        videoAspectRatio = context.aspectRatio.map { CGFloat($0) }
        ambientImage = context.ambientImageData.flatMap(UIImage.init(data:))
    }
}

private enum VisualContextLoader {
    static func makeVisualContext(videoURL: URL, ambientImageURL: URL?) async -> VisualContext {
        let asset = AVURLAsset(url: videoURL)
        let aspectRatio = await videoAspectRatio(for: asset)

        if let ambientImageURL, let ambientImageData = try? Data(contentsOf: ambientImageURL) {
            return VisualContext(
                aspectRatio: aspectRatio,
                ambientImageData: ambientImageData
            )
        }

        return VisualContext(
            aspectRatio: aspectRatio,
            ambientImageData: await posterImageData(for: asset)
        )
    }

    private static func videoAspectRatio(for asset: AVURLAsset) async -> Double? {
        guard
            let track = try? await asset.loadTracks(withMediaType: .video).first,
            let naturalSize = try? await track.load(.naturalSize),
            let preferredTransform = try? await track.load(.preferredTransform)
        else {
            return nil
        }

        let transformedSize = naturalSize.applying(preferredTransform)
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)
        guard width > 0, height > 0 else {
            return nil
        }

        return width / height
    }

    private static func posterImageData(for asset: AVURLAsset) async -> Data? {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 1400, height: 1400)

        let duration = (try? await asset.load(.duration)) ?? .zero
        let durationSeconds = duration.seconds
        let preferredTime = durationSeconds.isFinite && durationSeconds > 0
            ? CMTime(seconds: durationSeconds / 2, preferredTimescale: 600)
            : .zero

        let cgImage: CGImage
        do {
            cgImage = try imageGenerator.copyCGImage(at: preferredTime, actualTime: nil)
        } catch {
            guard let fallbackImage = try? imageGenerator.copyCGImage(at: .zero, actualTime: nil) else {
                return nil
            }
            cgImage = fallbackImage
        }

        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.82)
    }
}

private struct VisualContext: Sendable {
    let aspectRatio: Double?
    let ambientImageData: Data?
}

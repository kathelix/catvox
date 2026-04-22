import AVFoundation
import SwiftUI
import UIKit
import os

struct LoopingVideoBackground: UIViewRepresentable {
    let url: URL
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var backgroundColor: UIColor = .black
    var onPlaybackFailure: (URL, String) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPlaybackFailure: onPlaybackFailure)
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        applyPresentation(to: view)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        applyPresentation(to: uiView)
        context.coordinator.configure(url: url, in: uiView)
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.teardown(from: uiView)
    }

    private func applyPresentation(to view: PlayerContainerView) {
        view.playerLayer.videoGravity = videoGravity
        view.playerLayer.backgroundColor = backgroundColor.cgColor
        view.backgroundColor = backgroundColor
        view.isOpaque = backgroundColor != .clear
    }

    final class Coordinator: NSObject {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var currentURL: URL?
        private var itemStatusObservation: NSKeyValueObservation?
        private var endFailureObserver: NSObjectProtocol?
        private let logger = Logger(subsystem: "com.kathelix.catvox", category: "LoopingVideoBackground")
        private let onPlaybackFailure: (URL, String) -> Void

        init(onPlaybackFailure: @escaping (URL, String) -> Void) {
            self.onPlaybackFailure = onPlaybackFailure
        }

        func configure(url: URL, in view: PlayerContainerView) {
            guard currentURL != url else { return }

            teardown(from: view)
            currentURL = url

            let fileManager = FileManager.default
            let exists = fileManager.fileExists(atPath: url.path)
            let fileSize = fileSizeBytes(at: url)

            logger.info(
                "prepare looping background url=\(url.path, privacy: .public) exists=\(exists) size=\(fileSize)"
            )

            guard exists else {
                reportFailure(
                    for: url,
                    message: "The saved video couldn't be found.",
                    details: "file_missing size=\(fileSize)"
                )
                return
            }

            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            let player = AVQueuePlayer(playerItem: item)
            player.isMuted = true
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = false

            looper = AVPlayerLooper(player: player, templateItem: item)
            self.player = player
            view.playerLayer.player = player

            itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard let self, let currentURL = self.currentURL else { return }

                switch item.status {
                case .readyToPlay:
                    self.logger.info("looping background ready url=\(currentURL.path, privacy: .public)")
                    self.player?.play()

                case .failed:
                    let errorDescription = item.error?.localizedDescription ?? "unknown_item_failure"
                    self.reportFailure(
                        for: currentURL,
                        message: "We couldn't open the video for this scan.",
                        details: "item_failed error=\(errorDescription)"
                    )

                case .unknown:
                    break

                @unknown default:
                    self.reportFailure(
                        for: currentURL,
                        message: "We couldn't open the video for this scan.",
                        details: "item_status_unknown"
                    )
                }
            }

            endFailureObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] notification in
                guard let self, let currentURL = self.currentURL else { return }
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self.reportFailure(
                    for: currentURL,
                    message: "We couldn't open the video for this scan.",
                    details: "failed_to_play_to_end error=\(error?.localizedDescription ?? "none")"
                )
            }
        }

        func teardown(from view: PlayerContainerView) {
            itemStatusObservation?.invalidate()
            itemStatusObservation = nil

            if let endFailureObserver {
                NotificationCenter.default.removeObserver(endFailureObserver)
                self.endFailureObserver = nil
            }

            player?.pause()
            looper?.disableLooping()
            looper = nil
            player = nil
            currentURL = nil
            view.playerLayer.player = nil
        }

        private func reportFailure(for url: URL, message: String, details: String) {
            logger.error(
                "looping background failed url=\(url.path, privacy: .public) details=\(details, privacy: .public)"
            )
            player?.pause()
            onPlaybackFailure(url, message)
        }

        private func fileSizeBytes(at url: URL) -> Int64 {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey])
            if let total = values?.totalFileSize {
                return Int64(total)
            }
            if let fileSize = values?.fileSize {
                return Int64(fileSize)
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? -1
        }
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

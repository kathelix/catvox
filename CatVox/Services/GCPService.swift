import Foundation
import Observation

/// Transport layer for CatVox video uploads.
///
/// Pipeline:
///   1. Fetch a short-lived signed PUT URL from the Firebase Cloud Function.
///   2. Stream the recorded .mov file to Google Cloud Storage via HTTP PUT
///      with Content-Type: video/mp4.
///   3. Trigger the Vertex AI analysis Cloud Function and return a CatAnalysis.
///
/// Mock mode (default on):
///   Simulates the full pipeline with realistic delays so every UI state
///   transition can be exercised without a live server connection.
///
/// Phase 2: flip `mockMode = false` once the GCP backend is deployed.
@MainActor
@Observable
final class GCPService {

    // MARK: - Upload state

    enum UploadState: Equatable {
        case idle
        case fetchingSignedURL
        case uploading(Double)        // 0.0 – 1.0 byte progress
        case analysing
        case complete(CatAnalysis)
        case failed(String)

        static func == (lhs: UploadState, rhs: UploadState) -> Bool {
            switch (lhs, rhs) {
            case (.idle,              .idle),
                 (.fetchingSignedURL, .fetchingSignedURL),
                 (.analysing,         .analysing):
                return true
            case let (.uploading(a),  .uploading(b)):
                return a == b
            case let (.complete(a),   .complete(b)):
                return a.id == b.id
            case let (.failed(a),     .failed(b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Configuration

    /// `true`  — simulated delays, mock CatAnalysis (no server required).
    /// `false` — real GCS upload + backend analysis (Phase 2).
    var mockMode: Bool = true

    // MARK: - Observable properties

    private(set) var uploadState: UploadState = .idle

    // MARK: - Private

    private var currentTask: Task<Void, Never>?

    // MARK: - Backend endpoints (Phase 2)

    private enum Endpoint {
        // Replace with your deployed Cloud Function URLs before going live.
        static let signedURL = URL(
            string: "https://REGION-PROJECT_ID.cloudfunctions.net/getSignedUploadURL")!
        static let analyse   = URL(
            string: "https://REGION-PROJECT_ID.cloudfunctions.net/analyseVideo")!
    }

    // MARK: - Public API

    /// Starts the upload + analysis pipeline. Cancels any in-flight request first.
    func uploadAndAnalyse(videoAt localURL: URL) {
        currentTask?.cancel()
        currentTask = Task { await run(localURL: localURL) }
    }

    /// Re-starts the pipeline after a failure.
    func retry(videoAt localURL: URL) {
        uploadState = .idle
        uploadAndAnalyse(videoAt: localURL)
    }

    /// Cancels any in-flight task and returns to `.idle`.
    func reset() {
        currentTask?.cancel()
        uploadState = .idle
    }

    // MARK: - Pipeline orchestration

    private func run(localURL: URL) async {
        do {
            if mockMode {
                try await mockPipeline()
            } else {
                try await realPipeline(localURL: localURL)
            }
        } catch is CancellationError {
            uploadState = .idle
        } catch {
            uploadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Mock pipeline

    private func mockPipeline() async throws {
        // Step 1 — simulate signed URL negotiation
        uploadState = .fetchingSignedURL
        try await Task.sleep(for: .seconds(0.7))
        try Task.checkCancellation()

        // Step 2 — simulate chunked upload with smooth progress
        let steps = 25
        for step in 1...steps {
            try await Task.sleep(for: .milliseconds(70))
            try Task.checkCancellation()
            uploadState = .uploading(Double(step) / Double(steps))
        }

        // Step 3 — simulate Vertex AI analysis latency
        uploadState = .analysing
        try await Task.sleep(for: .seconds(1.4))
        try Task.checkCancellation()

        uploadState = .complete(MockAnalysisService.sampleAnalysis)
    }

    // MARK: - Real pipeline (Phase 2)

    private func realPipeline(localURL: URL) async throws {
        uploadState = .fetchingSignedURL
        let signedURL = try await fetchSignedURL(for: localURL)
        try Task.checkCancellation()

        uploadState = .uploading(0)
        try await upload(fileURL: localURL, to: signedURL)
        try Task.checkCancellation()

        uploadState = .analysing
        let analysis = try await triggerAnalysis(videoURL: signedURL)
        uploadState = .complete(analysis)
    }

    private func fetchSignedURL(for videoURL: URL) async throws -> URL {
        var request = URLRequest(url: Endpoint.signedURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "filename":    videoURL.lastPathComponent,
            "contentType": "video/mp4",
        ]
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        guard let raw = decoded["signedUrl"], let url = URL(string: raw) else {
            throw URLError(.cannotParseResponse)
        }
        return url
    }

    /// Streams the video file to GCS with a PUT request.
    /// Uses an NSObject delegate shim to relay byte-level progress back to the
    /// main actor — the same pattern used by CaptureDelegate in CameraService.
    private func upload(fileURL: URL, to signedURL: URL) async throws {
        let progressDelegate = UploadProgressDelegate { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.uploadState = .uploading(progress)
            }
        }
        let session = URLSession(
            configuration: .default,
            delegate: progressDelegate,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: signedURL)
        request.httpMethod = "PUT"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func triggerAnalysis(videoURL: URL) async throws -> CatAnalysis {
        var request = URLRequest(url: Endpoint.analyse)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["videoUrl": videoURL.absoluteString]
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(CatAnalysis.self, from: data)
    }
}

// MARK: - Upload progress delegate (NSObject shim)

/// Isolated NSObject that forwards URLSession byte-progress callbacks to a
/// Swift closure. Mirrors the CaptureDelegate pattern in CameraService —
/// keeps NSObject out of the @Observable class to avoid init-accessor conflicts.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {

    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

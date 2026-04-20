import Foundation
import Observation
import os

/// Transport layer for CatVox video uploads.
///
/// Pipeline:
///   1. Fetch a short-lived signed PUT URL from the Firebase Cloud Function.
///   2. Stream the recorded .mov file to Google Cloud Storage via HTTP PUT
///      with Content-Type: video/quicktime (matches the QuickTime container).
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
        case quotaExceeded
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
            case (.quotaExceeded,    .quotaExceeded):
                return true
            case let (.failed(a),     .failed(b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Configuration

    /// `true`  — simulated delays, mock CatAnalysis (no server required).
    /// `false` — real GCS upload + backend analysis.
    var mockMode: Bool = false

    // MARK: - Observable properties

    private(set) var uploadState: UploadState = .idle

    // MARK: - Private

    private var currentTask: Task<Void, Never>?

    // MARK: - Logging

    private let logger = Logger(subsystem: "com.kathelix.catvox", category: "GCPService")

    // MARK: - Backend endpoints

    private enum Endpoint {
        static let signedURL = URL(
            string: "https://getsigneduploadurl-pdkw5uifga-uc.a.run.app")!
        static let analyse   = URL(
            string: "https://analysevideo-pdkw5uifga-uc.a.run.app")!
    }

    // MARK: - User identity

    /// Persistent anonymous device identifier used for per-user usage quota enforcement.
    /// Stored in UserDefaults on first launch. Replace with Firebase Auth UID once Auth is added.
    private var userId: String {
        let key = "catvox.userId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
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
        } catch GCPError.quotaExceeded {
            uploadState = .quotaExceeded
        } catch is CancellationError {
            uploadState = .idle
        } catch {
            logger.error("pipeline failed: \(error)")
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
        let (signedURL, gcsUri) = try await fetchSignedURL(for: localURL)
        try Task.checkCancellation()

        uploadState = .uploading(0)
        try await upload(fileURL: localURL, to: signedURL)
        try Task.checkCancellation()

        uploadState = .analysing
        let analysis = try await triggerAnalysis(gcsUri: gcsUri)
        uploadState = .complete(analysis)
    }

    /// Returns `(signedURL, gcsUri)` — the signed PUT URL for the upload and
    /// the GCS URI (`gs://…`) passed to the analysis function.
    private func fetchSignedURL(for videoURL: URL) async throws -> (URL, String) {
        var request = URLRequest(url: Endpoint.signedURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "filename":    videoURL.lastPathComponent,
            "contentType": "video/quicktime",
        ]
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            logger.error("getSignedUploadURL: HTTP \(http.statusCode) — \(body)")
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        guard let rawURL = decoded["signedUrl"],
              let signedURL = URL(string: rawURL),
              let gcsUri = decoded["gcsUri"] else {
            throw URLError(.cannotParseResponse)
        }
        return (signedURL, gcsUri)
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
        // Use an ephemeral session so it has no inherited HTTP/3 alternative-service
        // cache from previous URLSession.shared requests. QUIC (HTTP/3) mid-stream
        // frame loss was dropping the GCS PUT at ~30% on some cellular networks.
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(
            configuration: config,
            delegate: progressDelegate,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: signedURL)
        request.httpMethod = "PUT"
        request.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else {
            logger.error("GCS PUT: response was not HTTPURLResponse")
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            logger.error("GCS PUT: HTTP \(http.statusCode) — \(body)")
            throw URLError(.badServerResponse)
        }
        logger.debug("GCS PUT: HTTP \(http.statusCode) — upload complete")
    }

    private func triggerAnalysis(gcsUri: String) async throws -> CatAnalysis {
        var request = URLRequest(url: Endpoint.analyse)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "gcsUri": gcsUri,
            "userId": userId,
        ]
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 429 { throw GCPError.quotaExceeded }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            logger.error("analyseVideo: HTTP \(http.statusCode) — \(body)")
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(CatAnalysis.self, from: data)
    }
}

// MARK: - Error types

enum GCPError: LocalizedError {
    case quotaExceeded

    var errorDescription: String? {
        "Daily scan limit reached. Come back tomorrow."
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

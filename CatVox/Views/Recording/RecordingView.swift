import SwiftUI

/// Camera viewfinder with a 10-second recording countdown.
///
/// Lifecycle:
///   1. onAppear   → requests camera + mic permissions, starts AVCaptureSession
///   2. Tap record → countdown begins (progress ring + integer timer)
///   3. After 2 seconds, tapping the capture control stops recording early
///   4. Recording ends automatically at 10 seconds if the user does not stop
///   5. captureState == .finished → lightweight review state appears
///   6. "Use This Clip" → hand off the recorded file back to Home for ResultView
///
/// Simulator note: no physical camera is available so the preview is black,
/// but the countdown and handoff simulation run identically to a real device.
///
/// See TRD §3.1 and §5.1.
struct RecordingView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var service       = CameraService()
    @State private var recordedURL:  URL?
    @State private var errorMessage  = ""
    @State private var showError     = false
    @State private var transientStatusMessage: String?
    @State private var hintTask: Task<Void, Never>?
    @State private var handoffToResult = false

    let onUseClip: (URL) -> Void

    // Integer countdown derived from continuous progress (0 – 10).
    private var countdown: Int {
        max(0, 10 - Int(service.progress * CameraService.clipDuration))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── Background ─────────────────────────────────────────────────
            Color.black.ignoresSafeArea()

            CameraPreviewView(session: service.session)
                .ignoresSafeArea()

            // Show while camera is initialising or if permission is denied.
            if !service.isSessionReady || service.permissionDenied {
                cameraPlaceholder
            }

            // Vignette — darkens bottom half for control legibility.
            LinearGradient(
                stops: [
                    .init(color: .clear,                location: 0.0),
                    .init(color: .clear,                location: 0.42),
                    .init(color: .black.opacity(0.92),  location: 1.0),
                ],
                startPoint: .top,
                endPoint:   .bottom
            )
            .ignoresSafeArea()

            // ── Controls ────────────────────────────────────────────────────
            VStack(spacing: 0) {
                topBar
                Spacer()
                captureControl
                    .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear  { service.requestPermissionsAndConfigure() }
        .onDisappear {
            hintTask?.cancel()
            service.stopSession()
            if !handoffToResult {
                discardRecordedClip()
            }
        }
        .onChange(of: service.captureState) { _, state in
            switch state {
            case .finished(let url):
                recordedURL = url
            case .failed(let msg):
                errorMessage = msg
                showError    = true
            default:
                break
            }
        }
        .alert("Recording Failed", isPresented: $showError) {
            Button("Retry",  role: .none)   { service.reset() }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.80))
            }
            .padding(4)

            Spacer()

            // Recording indicator
            HStack(spacing: 7) {
                if isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .opacity(0.9)
                }
                Text(topBarLabel)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(2.5)
                    .animation(.default, value: topBarLabel)
            }

            Spacer()
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Capture control

    private var captureControl: some View {
        VStack(spacing: 18) {
            ZStack {
                // ── Track ring ──────────────────────────────────────────
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 4)

                // ── Progress fill (brand indigo → cyan) ────────────────
                Circle()
                    .trim(from: 0, to: service.progress)
                    .stroke(
                        CatVoxTheme.brandAngularGradient,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    // Linear so the ring speed perfectly matches real time.
                    .animation(.linear(duration: 0.05), value: service.progress)

                // ── Centre content ──────────────────────────────────────
                centreContent
            }
            .frame(width: 128, height: 128)
            .contentShape(Circle())
            .onTapGesture(perform: handleCaptureTap)

            Text(statusLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(2.2)
                .animation(.default, value: statusLabel)

            if hasReviewActions {
                reviewActions
            }
        }
    }

    // The content inside the ring changes depending on capture state.
    @ViewBuilder
    private var centreContent: some View {
        switch service.captureState {

        case .idle:
            Button { service.startRecording() } label: {
                Circle()
                    .fill(CatVoxTheme.brandGradient)
                    .frame(width: 80, height: 80)
                    .shadow(color: CatVoxTheme.indigo.opacity(0.45), radius: 16, x: 0, y: 0)
            }
            .disabled(!service.isSessionReady)

        case .recording:
            Text("\(countdown)")
                .font(.system(size: 46, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(response: 0.3, dampingFraction: 0.7),
                           value: countdown)

        case .finalizing:
            ProgressView()
                .tint(.white)
                .scaleEffect(1.4)

        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)

        case .failed(_):
            ProgressView()
                .tint(.white)
                .scaleEffect(1.4)
        }
    }

    private var reviewActions: some View {
        HStack(spacing: 12) {
            Button {
                retakeRecording()
            } label: {
                Text("Retake")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.08))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
            }

            Button {
                useRecordedClip()
            } label: {
                Text("Use This Clip")
                    .font(.subheadline.bold())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        CatVoxTheme.brandGradient,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Camera placeholder

    private var cameraPlaceholder: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09)

            VStack(spacing: 14) {
                Image(systemName: service.permissionDenied
                      ? "video.slash.fill" : "camera.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.16))

                Text(service.permissionDenied
                     ? "Camera Access\nDenied in Settings."
                     : "Initialising Camera...")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
    }

    // MARK: - Helpers

    private var isRecording: Bool {
        if case .recording = service.captureState { return true }
        return false
    }

    private var hasReviewActions: Bool {
        if case .finished = service.captureState { return true }
        return false
    }

    private var topBarLabel: String {
        switch service.captureState {
        case .recording:
            return "REC"
        case .finished:
            return "REVIEW"
        default:
            return "10 SEC"
        }
    }

    private var statusLabel: String {
        if let transientStatusMessage {
            return transientStatusMessage
        }

        switch service.captureState {
        case .idle:         return "TAP TO START"
        case .recording:
            return service.canStopRecording ? "TAP TO FINISH" : "KEEP RECORDING"
        case .finalizing:   return "FINALIZING"
        case .finished(_):  return "CHOOSE NEXT STEP"
        case .failed(_):    return "FAILED"
        }
    }

    private func handleCaptureTap() {
        guard isRecording else { return }

        if service.canStopRecording {
            clearTransientStatusMessage()
            service.stopRecording()
        } else {
            showTransientStatusMessage("KEEP RECORDING A BIT LONGER")
        }
    }

    private func showTransientStatusMessage(_ message: String) {
        hintTask?.cancel()
        transientStatusMessage = message

        hintTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.25))
            transientStatusMessage = nil
        }
    }

    private func clearTransientStatusMessage() {
        hintTask?.cancel()
        hintTask = nil
        transientStatusMessage = nil
    }

    private func useRecordedClip() {
        guard let recordedURL else { return }
        handoffToResult = true
        onUseClip(recordedURL)
        dismiss()
    }

    private func retakeRecording() {
        clearTransientStatusMessage()
        discardRecordedClip()
        recordedURL = nil
        service.reset()
    }

    private func discardRecordedClip() {
        if let recordedURL {
            try? FileManager.default.removeItem(at: recordedURL)
        }
    }
}

#Preview {
    RecordingView { _ in }
}

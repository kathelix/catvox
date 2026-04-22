import SwiftUI
import SwiftData

/// The centrepiece of the CatVox experience.
///
/// Two initialisation paths:
///   `init(analysis:)`  — Dev-preview / Phase 1.  Analysis is supplied directly;
///                        no upload occurs and the result UI springs in immediately.
///   `init(videoURL:)`  — Normal recording path.  GCPService drives the upload
///                        pipeline; the result UI replaces the loading card once
///                        analysis is returned from the backend (or mock).
///   `init(savedScan:)` — Reopened local history item; result UI uses persisted
///                        data without re-uploading or re-analysing the clip.
///
/// Layout (bottom-to-top):
///   1. Full-screen animated gradient background (persona-tinted)
///   2. Soft vignette
///   3. ThoughtBubbleView / UploadProgressView — springs in after upload
///   4. Bottom panel (PersonaBadge + ExpertInsightsDrawer + Done CTA)
///   5. Top bar with a dismiss control only while the result is incomplete
///
/// See TRD §5.1 and PROMPT.md §2 for the full specification.
struct ResultView: View {

    @Environment(\.dismiss)        private var dismiss
    @Environment(\.modelContext)   private var modelContext
    @Environment(ScanQuotaStore.self) private var quotaStore

    /// Becomes non-nil once analysis is available — immediately for the dev
    /// path, or after `gcpService` completes for the recording path.
    @State private var viewModel: ResultViewModel?

    /// Active only when `videoURL` is non-nil.
    @State private var gcpService = GCPService()

    /// Error state for the retry alert.
    @State private var showRetryAlert = false
    @State private var failureMessage  = ""
    @State private var persistenceMessage = ""
    @State private var showPersistenceAlert = false

    /// Set at init; nil in dev-preview mode (analysis provided directly).
    private let videoURL: URL?
    private let sourceType: ScanSourceType?

    // MARK: - Init

    /// Dev-preview / Phase 1: analysis is provided directly, no upload.
    init(analysis: CatAnalysis) {
        videoURL = nil
        sourceType = nil
        _viewModel = State(initialValue: ResultViewModel(analysis: analysis))
    }

    /// Normal recording path: upload is triggered on appear.
    init(videoURL: URL, sourceType: ScanSourceType) {
        self.videoURL = videoURL
        self.sourceType = sourceType
        _viewModel = State(initialValue: nil)
    }

    /// Local-history path: result is reconstructed from persisted state.
    init(savedScan: SavedScan) {
        videoURL = ScanHistoryStore.originalVideoURL(for: savedScan)
        sourceType = savedScan.sourceType
        _viewModel = State(initialValue: ResultViewModel(analysis: savedScan.analysis))
    }

    // MARK: - Derived

    /// Falls back to `.grumpyBoss` while the upload is pending so the
    /// background gradient always has a valid persona to render.
    private var activePersona: CatPersona {
        viewModel?.persona ?? .grumpyBoss
    }

    private var showsCompletedResult: Bool {
        viewModel != nil
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── 1. Background ──────────────────────────────────────────────
            AnimatedVideoBackground(persona: activePersona)
                .ignoresSafeArea()

            // ── 2. Vignette ────────────────────────────────────────────────
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.00), location: 0.00),
                    .init(color: .black.opacity(0.15), location: 0.35),
                    .init(color: .black.opacity(0.82), location: 0.75),
                    .init(color: .black.opacity(0.95), location: 1.00),
                ],
                startPoint: .top,
                endPoint:   .bottom
            )
            .ignoresSafeArea()

            // ── 3 + 4 + 5. Content ─────────────────────────────────────────
            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                Spacer()

                if let viewModel {
                    resultContent(viewModel)
                } else if gcpService.uploadState == .quotaExceeded {
                    quotaExceededContent
                } else {
                    loadingContent
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear(perform: handleAppear)
        .onChange(of: gcpService.uploadState) { _, state in handleUploadState(state) }
        .alert("Upload Failed", isPresented: $showRetryAlert) {
            Button("Retry") {
                if let url = videoURL { gcpService.retry(videoAt: url) }
            }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text(failureMessage)
        }
        .alert("History Save Failed", isPresented: $showPersistenceAlert) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(persistenceMessage)
        }
    }

    // MARK: - Content branches

    /// Shown when the daily free scan quota is exhausted (HTTP 429).
    private var quotaExceededContent: some View {
        QuotaExceededView { dismiss() }
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
            .transition(.opacity)
    }

    /// Shown while GCPService is working. Sits in the same vertical zone
    /// as the thought bubble so the transition feels continuous.
    private var loadingContent: some View {
        UploadProgressView(state: gcpService.uploadState)
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
            .transition(.opacity)
    }

    /// Full result UI — mirrors the original single-path layout.
    @ViewBuilder
    private func resultContent(_ vm: ResultViewModel) -> some View {
        if vm.thoughtBubbleVisible {
            ThoughtBubbleView(
                analysis: vm.analysis,
                persona:  vm.persona
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.82, anchor: .bottom)
                               .combined(with: .opacity),
                    removal:   .opacity
                )
            )
        }

        if vm.panelVisible {
            bottomPanel(vm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            if showsCompletedResult {
                Color.clear.frame(width: 32, height: 32)
            } else {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(4)
            }

            Spacer()

            Text("CAT VOX")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(3)

            Spacer()

            // Balances the close button for optical centering.
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Bottom panel

    private func bottomPanel(_ vm: ResultViewModel) -> some View {
        VStack(spacing: 12) {
            PersonaBadgeView(
                emotion:    vm.analysis.primaryEmotion,
                persona:    vm.persona,
                confidence: vm.analysis.confidenceScore
            )

            ExpertInsightsDrawer(
                analysis:   vm.analysis,
                isExpanded: Binding(
                    get: { vm.isInsightsExpanded },
                    set: { vm.isInsightsExpanded = $0 }
                )
            )

            doneButton(vm)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
    }

    private func doneButton(_ vm: ResultViewModel) -> some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                Text("Done")
                    .fontWeight(.bold)
            }
            .font(.subheadline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [
                        vm.persona.accentColor,
                        vm.persona.accentColor.opacity(0.78),
                    ],
                    startPoint: .leading,
                    endPoint:   .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }

    // MARK: - Event handlers

    private func handleAppear() {
        if viewModel != nil {
            viewModel?.onAppear()
        } else if let url = videoURL {
            // Recording path — kick off the upload pipeline.
            gcpService.uploadAndAnalyse(videoAt: url)
        }
    }

    private func handleUploadState(_ state: GCPService.UploadState) {
        switch state {
        case .complete(let analysis):
            handleCompletedAnalysis(analysis)

        case .quotaExceeded:
            quotaStore.markExhausted()

        case .failed(let message):
            failureMessage = message
            showRetryAlert = true

        default:
            break
        }
    }

    private func handleCompletedAnalysis(_ analysis: CatAnalysis) {
        quotaStore.recordScan()

        guard let videoURL, let sourceType else {
            let vm = ResultViewModel(analysis: analysis)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                viewModel = vm
            }
            Task { @MainActor in vm.onAppear() }
            return
        }

        do {
            _ = try ScanHistoryStore.saveScan(
                from: videoURL,
                sourceType: sourceType,
                analysis: analysis,
                in: modelContext
            )

            let vm = ResultViewModel(analysis: analysis)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                viewModel = vm
            }
            Task { @MainActor in vm.onAppear() }
        } catch {
            persistenceMessage = "We couldn't save this scan to local history."
            showPersistenceAlert = true
        }
    }
}

// MARK: - Previews

#Preview("Grumpy Boss") {
    ResultView(analysis: MockAnalysisService.sampleAnalysis)
        .environment(ScanQuotaStore())
        .modelContainer(for: SavedScan.self, inMemory: true)
}

#Preview("Existential Philosopher") {
    ResultView(analysis: MockAnalysisService.allSamples[1])
        .environment(ScanQuotaStore())
        .modelContainer(for: SavedScan.self, inMemory: true)
}

#Preview("Chaotic Hunter") {
    ResultView(analysis: MockAnalysisService.allSamples[2])
        .environment(ScanQuotaStore())
        .modelContainer(for: SavedScan.self, inMemory: true)
}

#Preview("Upload in Progress") {
    ResultView(videoURL: URL(fileURLWithPath: "/dev/null"), sourceType: .recorded)
        .environment(ScanQuotaStore())
        .modelContainer(for: SavedScan.self, inMemory: true)
}

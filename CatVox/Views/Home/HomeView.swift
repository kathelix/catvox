import SwiftUI

struct HomeView: View {

    @Environment(ScanQuotaStore.self) private var quotaStore

    @State private var showSourceChoice = false
    @State private var showPhotoPicker  = false
    @State private var showRecording    = false
    @State private var showImportedResult = false
    @State private var showQuotaCard    = false
    @State private var showPhotoNotice  = false
    @State private var photoNoticeText  = ""
    @State private var importedVideoURL: URL?

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: Logo
                VStack(spacing: 10) {
                    Text("🐱")
                        .font(.system(size: 72))

                    Text("CatVox")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text("Powered by Kathelix")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.35))
                        .tracking(2)
                }

                Spacer()

                // MARK: Primary CTA
                Button {
                    if quotaStore.scansRemaining > 0 {
                        showSourceChoice = true
                    } else {
                        showQuotaCard = true
                    }
                } label: {
                    Label("Read My Cat", systemImage: "video.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            CatVoxTheme.brandGradient,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }
                .padding(.horizontal, 24)

                Text(quotaLabel)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 12)

                Spacer().frame(height: 56)
            }
        }
        .overlay {
            if showQuotaCard {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    QuotaExceededView { showQuotaCard = false }
                        .padding(.horizontal, 20)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showQuotaCard)
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Choose Video Source",
            isPresented: $showSourceChoice,
            titleVisibility: .visible
        ) {
            Button("Record New Video") {
                showRecording = true
            }

            Button("Choose from Photos") {
                showPhotoPicker = true
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Start with a new recording or pick an existing clip.")
        }
        .sheet(isPresented: $showPhotoPicker) {
            HomeVideoPicker { outcome in
                switch outcome {
                case .cancelled:
                    break

                case .success(let videoURL):
                    importedVideoURL = videoURL
                    showImportedResult = true

                case .failure(let message):
                    photoNoticeText = message
                    showPhotoNotice = true
                }
            }
        }
        .fullScreenCover(isPresented: $showRecording) {
            RecordingView()
        }
        .fullScreenCover(isPresented: $showImportedResult) {
            if let importedVideoURL {
                ResultView(videoURL: importedVideoURL)
            } else {
                ResultView(analysis: MockAnalysisService.sampleAnalysis)
            }
        }
        .onChange(of: showImportedResult) { _, isShowing in
            if !isShowing {
                importedVideoURL = nil
            }
        }
        .alert("Photos Import", isPresented: $showPhotoNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoNoticeText)
        }
    }

    private var quotaLabel: String {
        let n = quotaStore.scansRemaining
        return "\(n) free \(n == 1 ? "scan" : "scans") remaining today"
    }
}

#Preview {
    HomeView()
        .environment(ScanQuotaStore())
}

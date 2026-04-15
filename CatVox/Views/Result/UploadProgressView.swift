import SwiftUI

/// Glassmorphic status card shown in place of ThoughtBubbleView while a
/// video is being uploaded to GCS and analysed by Vertex AI.
///
/// State mapping:
///   .fetchingSignedURL  → lock icon  + spinner  + "Securing connection..."
///   .uploading(p)       → arrow icon + progress bar + "Sending clip — XX%"
///   .analysing          → brain icon + spinner  + "Reading your cat's mind..."
struct UploadProgressView: View {

    let state: GCPService.UploadState

    var body: some View {
        VStack(spacing: 16) {
            statusRow

            // Linear progress bar is only visible during the upload phase.
            if case let .uploading(progress) = state {
                uploadProgressBar(progress)
            }
        }
        .padding(20)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
    }

    // MARK: - Status row

    private var statusRow: some View {
        HStack(spacing: 14) {

            // Animated icon pill
            ZStack {
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .symbolEffect(.pulse)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.default, value: iconName)
            }

            // Label stack
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(1.6)

                Text(subtitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: subtitle)
            }

            Spacer()

            // Spinner — hidden while the progress bar is showing
            if case .uploading = state {
                EmptyView()
            } else {
                ProgressView()
                    .tint(.white.opacity(0.55))
                    .scaleEffect(0.9)
            }
        }
    }

    // MARK: - Progress bar

    private func uploadProgressBar(_ progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.12))
                    .frame(height: 4)
                Capsule()
                    .fill(.white.opacity(0.80))
                    .frame(width: geo.size.width * max(0, min(progress, 1)), height: 4)
                    .animation(.linear(duration: 0.09), value: progress)
            }
        }
        .frame(height: 4)
    }

    // MARK: - State-derived text and icons

    private var iconName: String {
        switch state {
        case .fetchingSignedURL: return "lock.icloud.fill"
        case .uploading:         return "arrow.up.circle.fill"
        case .analysing:         return "brain.head.profile"
        default:                 return "arrow.up.circle.fill"
        }
    }

    private var title: String {
        switch state {
        case .fetchingSignedURL: return "Preparing"
        case .uploading:         return "Uploading"
        case .analysing:         return "Analysing"
        default:                 return "Processing"
        }
    }

    private var subtitle: String {
        switch state {
        case .fetchingSignedURL:  return "Securing connection..."
        case let .uploading(p):   return "Sending clip — \(Int(p * 100))%"
        case .analysing:          return "Reading your cat's mind..."
        default:                  return "Please wait..."
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea()
        VStack(spacing: 16) {
            UploadProgressView(state: .fetchingSignedURL)
            UploadProgressView(state: .uploading(0.62))
            UploadProgressView(state: .analysing)
        }
        .padding(24)
    }
    .preferredColorScheme(.dark)
}

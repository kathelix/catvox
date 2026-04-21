import PhotosUI
import SwiftUI

struct HomeVideoPicker: UIViewControllerRepresentable {
    enum Outcome {
        case cancelled
        case success(URL)
        case failure(String)
    }

    let onFinish: (Outcome) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onFinish: (Outcome) -> Void

        init(onFinish: @escaping (Outcome) -> Void) {
            self.onFinish = onFinish
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                picker.dismiss(animated: true) {
                    self.onFinish(.cancelled)
                }
                return
            }

            Task {
                do {
                    let importedURL = try await ImportedVideoService.importValidatedVideo(from: result)
                    await MainActor.run {
                        picker.dismiss(animated: true) {
                            self.onFinish(.success(importedURL))
                        }
                    }
                } catch {
                    let message =
                        (error as? LocalizedError)?.errorDescription ??
                        ImportedVideoValidationError.importFailed.localizedDescription

                    await MainActor.run {
                        picker.dismiss(animated: true) {
                            self.onFinish(.failure(message))
                        }
                    }
                }
            }
        }
    }
}

import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let onComplete: (UIActivity.ActivityType?, Bool, Error?) -> Void

    init(
        activityItems: [Any],
        onComplete: @escaping (UIActivity.ActivityType?, Bool, Error?) -> Void = { _, _, _ in }
    ) {
        self.activityItems = activityItems
        self.onComplete = onComplete
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, error in
            onComplete(activityType, completed, error)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

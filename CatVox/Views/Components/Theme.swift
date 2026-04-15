import SwiftUI

/// Brand colours and gradients extracted from the CatVox app icon.
///
/// Icon palette:
///   Indigo  #4F46E5  →  rgb(0.310, 0.275, 0.898)
///   Cyan    #06B6D4  →  rgb(0.024, 0.714, 0.831)
enum CatVoxTheme {

    // MARK: - Brand colours

    static let indigo = Color(red: 0.310, green: 0.275, blue: 0.898)
    static let cyan   = Color(red: 0.024, green: 0.714, blue: 0.831)

    // MARK: - Gradients

    /// Primary brand gradient used for progress rings and CTAs.
    static let brandGradient = LinearGradient(
        colors:     [indigo, cyan],
        startPoint: .topLeading,
        endPoint:   .bottomTrailing
    )

    /// Angular version for circular progress indicators.
    static let brandAngularGradient = AngularGradient(
        colors:      [indigo, cyan, indigo],
        center:      .center,
        startAngle:  .degrees(0),
        endAngle:    .degrees(360)
    )
}

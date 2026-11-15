import SwiftUI

struct SizeBar: View {
    let usedBytes: Int64
    let totalBytes: Int64

    private var ratio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    private var fillColor: Color {
        if ratio >= 0.9 { return .red }
        if ratio >= 0.75 { return .orange }
        return .accentColor
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(0, proxy.size.width * ratio))
            }
        }
        .frame(height: 8)
    }
}

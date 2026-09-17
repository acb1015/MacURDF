import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // App Icon with glow
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            } else {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text("MacURDF")
                    .font(.title.bold())
                Text("Version 1.0 (Build 1)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Native macOS URDF Viewer & Kinematics Studio")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                FeatureBadge(icon: "apple.terminal", title: "Pure Native Swift & SwiftUI", subtitle: "No ROS runtime or Python environment required")
                FeatureBadge(icon: "cube.fill", title: "SceneKit & Metal Acceleration", subtitle: "Hardware accelerated 3D viewport with 60+ FPS")
                FeatureBadge(icon: "visionpro", title: "Apple USDZ Export", subtitle: "Export robot models directly to iOS AR & visionOS")
                FeatureBadge(icon: "lock.shield", title: "App Sandbox Hardened", subtitle: "Security-scoped filesystem access for safe robotics workflows")
            }
            .padding(.horizontal, 8)

            Divider()

            HStack {
                Text("Copyright © 2026 MacURDF Contributors")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct FeatureBadge: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.bold())
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

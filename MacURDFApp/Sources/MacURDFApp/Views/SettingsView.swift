import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            ViewportSettingsView()
                .tabItem {
                    Label("Viewport", systemImage: "cube.transparent")
                }
            PackagesSettingsView()
                .tabItem {
                    Label("Packages", systemImage: "folder")
                }
        }
        .frame(width: 480, height: 320)
        .padding(16)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("Angle Representation") {
                Picker("Display Units", selection: $appModel.useDegrees) {
                    Text("Degrees (°)").tag(true)
                    Text("Radians (rad)").tag(false)
                }
                .pickerStyle(.radioGroup)
                Text("Applies to joint sliders, direct input fields, and kinematic readouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Coordinate System") {
                Toggle("Auto Z-up to Y-up orientation", isOn: Binding(
                    get: { appModel.useZUpToYUp },
                    set: { appModel.setUseZUpToYUp($0) }
                ))
                Text("ROS URDF robots use Z-up coordinates by default. Converts to SceneKit Y-up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }
}

private struct ViewportSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("Visual Style") {
                Picker("Background Theme", selection: $appModel.viewportTheme) {
                    Text("Dark Slate").tag(ViewportTheme.darkSlate)
                    Text("Space Black").tag(ViewportTheme.spaceBlack)
                    Text("Neutral Gray").tag(ViewportTheme.neutralGray)
                    Text("Light Studio").tag(ViewportTheme.lightStudio)
                }

                Toggle("Force Teal Mesh Tint (STL/OBJ)", isOn: Binding(
                    get: { appModel.tealMeshTint },
                    set: { appModel.setTealMeshTint($0) }
                ))

                Toggle("Show Floor Grid", isOn: $appModel.showGrid)
                Toggle("Show World Coordinate Axes", isOn: $appModel.showWorldAxes)
                Toggle("Show Link TF Coordinate Frames", isOn: $appModel.showCoordinateFrames)
            }

            Section("Camera Navigation") {
                Toggle("Invert Orbit Rotation", isOn: $appModel.invertOrbit)
                Text("Reverses the mouse drag orbit rotation direction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }
}

private struct PackagesSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registered Package Roots (App Sandbox)")
                .font(.headline)
            Text("These directories have been granted security-scoped file access for resolving mesh files (package://...).")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(appModel.packageHints, id: \.self) { url in
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.caption.bold())
                        Text(url.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack {
                Button("Grant Additional Folder Access…") {
                    appModel.grantPackageFolderAccess()
                }
                Spacer()
                Text("\(appModel.packageHints.count) paths configured")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }
}

enum ViewportTheme: String, CaseIterable, Sendable {
    case darkSlate = "Dark Slate"
    case spaceBlack = "Space Black"
    case neutralGray = "Neutral Gray"
    case lightStudio = "Light Studio"

    var nsColor: NSColor {
        switch self {
        case .darkSlate:
            return NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: 1.0)
        case .spaceBlack:
            return NSColor(calibratedWhite: 0.03, alpha: 1.0)
        case .neutralGray:
            return NSColor(calibratedWhite: 0.22, alpha: 1.0)
        case .lightStudio:
            return NSColor(calibratedWhite: 0.88, alpha: 1.0)
        }
    }
}

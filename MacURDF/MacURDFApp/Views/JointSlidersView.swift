import SwiftUI
import URDFCore

struct JointSlidersView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header & Action Bar
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Text("Joint Controls")
                        .font(.headline)
                    Spacer()
                    // Degree / Radian Toggle
                    Picker("Units", selection: $appModel.useDegrees) {
                        Text("deg (°)").tag(true)
                        Text("rad").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 120)
                }

                // Preset Buttons: Zero, Random, Demo Play
                HStack(spacing: 6) {
                    Button {
                        appModel.resetAllJointsToZero()
                    } label: {
                        Label("Zero", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Reset all joints to 0.0 (⌘0)")

                    Button {
                        appModel.randomizeJoints()
                    } label: {
                        Label("Random", systemImage: "dice")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Randomize joints within limits (⌥⌘R)")

                    Button {
                        appModel.toggleDemoAnimation()
                    } label: {
                        Label(
                            appModel.isDemoAnimating ? "Pause" : "Play Demo",
                            systemImage: appModel.isDemoAnimating ? "pause.fill" : "play.fill"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(appModel.isDemoAnimating ? Color.orange : Color.accentColor)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appModel.isDemoAnimating ? Color.orange.opacity(0.25) : Color.accentColor.opacity(0.2))
                    .help("Smoothly animate joints in a continuous harmonic wave")
                }

                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter joints...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Joint List
            if let doc = appModel.document {
                let movable = doc.joints.filter {
                    switch $0.type {
                    case .revolute, .prismatic, .continuous: return true
                    default: return false
                    }
                }
                let filtered = movable.filter {
                    searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
                }

                if movable.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("All Joints Fixed")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("This robot does not have any movable (revolute/prismatic/continuous) joints.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("No matching joints.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered, id: \.name) { joint in
                        JointSliderRow(joint: joint)
                    }
                    .listStyle(.plain)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No Robot Loaded")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Open a URDF file to control robot kinematics.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct JointSliderRow: View {
    @EnvironmentObject private var appModel: AppModel
    let joint: Joint

    @State private var textBuffer: String = ""
    @State private var isEditingText: Bool = false

    var isRevoluteOrContinuous: Bool {
        joint.type == .revolute || joint.type == .continuous
    }

    var body: some View {
        let rawRadian = appModel.jointState.values[joint.name] ?? 0
        let displayVal = appModel.displayValue(forJointName: joint.name, rawRadian: rawRadian)
        let displayRange = appModel.displayRange(forJoint: joint)

        VStack(alignment: .leading, spacing: 4) {
            // Joint Name & Type Tag
            HStack {
                Text(joint.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer()

                // Direct Numeric Input Field
                HStack(spacing: 2) {
                    TextField(
                        "",
                        text: Binding(
                            get: {
                                isEditingText ? textBuffer : String(format: "%.2f", displayVal)
                            },
                            set: { newVal in
                                textBuffer = newVal
                                if let parsed = Double(newVal) {
                                    appModel.setJointFromDisplay(joint.name, displayValue: parsed)
                                }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .font(.caption2.monospaced())
                    .multilineTextAlignment(.trailing)
                    .onTapGesture {
                        isEditingText = true
                        textBuffer = String(format: "%.2f", displayVal)
                    }
                    .onSubmit {
                        isEditingText = false
                    }

                    Text(appModel.unitSuffix(forJoint: joint))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(joint.type.rawValue.prefix(3).uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Slider with Nudge Buttons
            HStack(spacing: 6) {
                Button {
                    let step = isRevoluteOrContinuous ? (appModel.useDegrees ? 5.0 : 0.05) : 0.05
                    appModel.setJointFromDisplay(joint.name, displayValue: displayVal - step)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.borderless)
                .frame(width: 14, height: 14)

                Slider(
                    value: Binding(
                        get: { displayVal },
                        set: { appModel.setJointFromDisplay(joint.name, displayValue: $0) }
                    ),
                    in: displayRange
                )

                Button {
                    let step = isRevoluteOrContinuous ? (appModel.useDegrees ? 5.0 : 0.05) : 0.05
                    appModel.setJointFromDisplay(joint.name, displayValue: displayVal + step)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.borderless)
                .frame(width: 14, height: 14)
            }

            // Limit bounds readout
            HStack {
                Text(String(format: "%.1f", displayRange.lowerBound))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(joint.parent) → \(joint.child)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.1f", displayRange.upperBound))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(
            appModel.selectedJointName == joint.name
                ? Color.accentColor.opacity(0.12)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            appModel.selectJoint(joint.name)
        }
    }
}

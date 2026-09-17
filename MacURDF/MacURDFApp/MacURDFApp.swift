import SwiftUI
import URDFCore
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appModel: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        Task { @MainActor in
            appModel?.load(url: url)
        }
        return true
    }
}

@main
struct MacURDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @State private var showingAbout: Bool = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 1080, minHeight: 680)
                .onAppear {
                    appDelegate.appModel = appModel
                }
                .onOpenURL { url in
                    appModel.load(url: url)
                }
                .sheet(isPresented: $showingAbout) {
                    AboutView()
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // App Menu
            CommandGroup(replacing: .appInfo) {
                Button("About MacURDF") {
                    showingAbout = true
                }
            }

            // File Menu
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .newItem) {
                Button("Open…") {
                    appModel.openURDF()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Reload") {
                    appModel.reload()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(appModel.openedURL == nil)

                Button("Grant Package Folder Access…") {
                    appModel.grantPackageFolderAccess()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Menu("Open Sample Robot") {
                    Button("Simple Arm (Primitives)") {
                        appModel.loadSample(name: "simple_arm")
                    }
                    Button("Simple Arm Mesh (STL)") {
                        appModel.loadSample(name: "simple_arm_mesh")
                    }
                    Button("Demo Package Robot") {
                        appModel.loadSample(name: "pkg_robot")
                    }
                }
            }

            // Edit Menu
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Reset Joints to Zero") {
                    appModel.resetAllJointsToZero()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button("Randomize Joints") {
                    appModel.randomizeJoints()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button(appModel.isDemoAnimating ? "Stop Demo Animation" : "Play Demo Animation") {
                    appModel.toggleDemoAnimation()
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
            }

            // View Menu
            CommandMenu("View") {
                Menu("Render Mode") {
                    Picker("Mode", selection: $appModel.renderMode) {
                        ForEach(RenderMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                }

                Menu("Camera") {
                    Button("Fit Robot to View") {
                        appModel.triggerCamera(.fitToView)
                    }
                    .keyboardShortcut("f", modifiers: [.command])

                    Button("Isometric View") {
                        appModel.triggerCamera(.isometric)
                    }
                    .keyboardShortcut("4", modifiers: [.command])

                    Button("Front View") {
                        appModel.triggerCamera(.front)
                    }
                    .keyboardShortcut("1", modifiers: [.command])

                    Button("Side View") {
                        appModel.triggerCamera(.side)
                    }
                    .keyboardShortcut("2", modifiers: [.command])

                    Button("Top View") {
                        appModel.triggerCamera(.top)
                    }
                    .keyboardShortcut("3", modifiers: [.command])

                    Divider()

                    Button("Reset Camera") {
                        appModel.triggerCamera(.reset)
                    }
                    .keyboardShortcut(".", modifiers: [.command])
                }

                Divider()

                Toggle("Floor Grid", isOn: $appModel.showGrid)
                Toggle("World Coordinate Axes", isOn: $appModel.showWorldAxes)
                Toggle("Link TF Coordinate Frames", isOn: $appModel.showCoordinateFrames)

                Divider()

                Toggle("Use Degrees for Angles", isOn: $appModel.useDegrees)
                Toggle(
                    "Z-up URDF (stand upright)",
                    isOn: Binding(
                        get: { appModel.useZUpToYUp },
                        set: { appModel.setUseZUpToYUp($0) }
                    )
                )
                Toggle(
                    "Teal mesh tint",
                    isOn: Binding(
                        get: { appModel.tealMeshTint },
                        set: { appModel.setTealMeshTint($0) }
                    )
                )

                Divider()

                Toggle(
                    "Inspector & Issues Drawer",
                    isOn: Binding(
                        get: { appModel.showIssuesPanel },
                        set: { appModel.setShowIssuesPanel($0) }
                    )
                )
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            // Help Menu
            CommandGroup(replacing: .help) {
                Button("MacURDF Help & Documentation") {
                    if let url = URL(string: "https://github.com/stupid1potato/MacURDF") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("About MacURDF") {
                    showingAbout = true
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }
}

extension UTType {
    static var urdf: UTType {
        UTType(filenameExtension: "urdf")
            ?? UTType(importedAs: "org.ros.urdf")
    }
}

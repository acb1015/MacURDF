import Foundation
import SwiftUI
import URDFCore
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isDropTargeted = false
    @State private var showLeftSidebar: Bool = true
    @State private var showRightSidebar: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                if showLeftSidebar {
                    LinkTreeView()
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .overlay(alignment: .trailing) {
                            Divider()
                        }
                        .transition(.move(edge: .leading))
                }

                SceneViewportView()
                    .frame(minWidth: 450)

                if showRightSidebar {
                    JointSlidersView()
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .overlay(alignment: .leading) {
                            Divider()
                        }
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxHeight: .infinity)

            if appModel.showIssuesPanel {
                Divider()
                BottomDrawerView()
                    .frame(minHeight: 140, idealHeight: 190, maxHeight: 320)
                    .transition(.move(edge: .bottom))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(appModel.document?.robotName ?? "MacURDF")
        .navigationSubtitle(appModel.statusMessage)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showLeftSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Model Tree Sidebar (⌘1)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.openURDF()
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .help("Open URDF File… (⌘O)")

                Button {
                    appModel.reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Reload URDF (⌘R)")
                .disabled(appModel.openedURL == nil)

                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appModel.showIssuesPanel.toggle()
                    }
                } label: {
                    Image(systemName: appModel.showIssuesPanel ? "rectangle.bottomthird.inset.filled" : "rectangle.bottomthird.inset.split")
                }
                .help("Toggle Inspector & Diagnostics Drawer (⇧⌘I)")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showRightSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Joint Controls (⌘2)")
            }
        }
        .overlay {
            if isDropTargeted {
                ZStack {
                    Color.accentColor.opacity(0.12)
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .padding(8)

                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentColor)
                        Text("Drop URDF or Robot Package Folder")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
                    let isDirectory = isDir.boolValue
                    Task { @MainActor in
                        if isDirectory {
                            appModel.loadFromFolder(url)
                        } else {
                            let ext = url.pathExtension.lowercased()
                            guard ext == "urdf" || ext == "xml" else { return }
                            appModel.load(url: url)
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}

import AppKit
import SceneKit
import SwiftUI
import simd
import URDFCore

struct SceneViewportView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var currentSCNView: SCNView?

    var body: some View {
        ZStack {
            SceneViewRepresentable(
                sceneEpoch: appModel.sceneEpoch,
                jointState: appModel.jointState,
                document: appModel.document,
                audits: appModel.meshAudits,
                renderMode: appModel.renderMode,
                selectedLinkName: appModel.selectedLinkName,
                useZUpToYUp: appModel.useZUpToYUp,
                tealMeshTint: appModel.tealMeshTint,
                showGrid: appModel.showGrid,
                showWorldAxes: appModel.showWorldAxes,
                showCoordinateFrames: appModel.showCoordinateFrames,
                viewportTheme: appModel.viewportTheme,
                invertOrbit: appModel.invertOrbit,
                cameraTrigger: appModel.cameraTrigger,
                linkTransforms: appModel.linkTransforms,
                meshNode: { appModel.nodeForResolvedMesh(url: $0) },
                onViewCreated: { view in
                    currentSCNView = view
                }
            )

            // Empty state overlay
            if appModel.document == nil {
                welcomeOverlay
            }

            // Top HUD Controls
            VStack {
                HStack(alignment: .center, spacing: 12) {
                    if let doc = appModel.document {
                        // Robot Name & Component Count Tag
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 7, height: 7)
                            Text(doc.robotName)
                                .font(.caption.bold())
                            Text("(\(doc.links.count)L · \(doc.joints.count)J)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
                    }

                    Spacer()

                    // Unified Viewport Tools Capsule
                    HStack(spacing: 6) {
                        // Render Shading & Display Options Menu
                        Menu {
                            Section("Shading Mode") {
                                Picker("Shading Mode", selection: $appModel.renderMode) {
                                    ForEach(RenderMode.allCases) { mode in
                                        Label(mode.rawValue, systemImage: mode.icon)
                                            .tag(mode)
                                    }
                                }
                                .pickerStyle(.inline)
                                .labelsHidden()
                            }

                            Divider()

                            Section("Scene Overlays") {
                                Toggle("Floor Grid", isOn: $appModel.showGrid)
                                Toggle("World Axes", isOn: $appModel.showWorldAxes)
                                Toggle("Link TF Coordinate Frames", isOn: $appModel.showCoordinateFrames)
                            }

                            Divider()

                            Section("Coordinates & Meshes") {
                                Toggle("Z-up Coordinate Correction", isOn: Binding(
                                    get: { appModel.useZUpToYUp },
                                    set: { appModel.setUseZUpToYUp($0) }
                                ))
                                Toggle("Teal Mesh Tint", isOn: Binding(
                                    get: { appModel.tealMeshTint },
                                    set: { appModel.setTealMeshTint($0) }
                                ))
                                Toggle("Invert Orbit Direction", isOn: $appModel.invertOrbit)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: appModel.renderMode.icon)
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                                Text(appModel.renderMode.rawValue)
                                    .font(.caption.bold())
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                        }
                        .menuStyle(.borderlessButton)
                        .help("Visual & Display Options (Shading, Grid, Coordinates, Mesh Tint)")

                        Divider()
                            .frame(height: 12)

                        // Camera Presets Menu
                        Menu {
                            Button("Fit to View (Zoom All)") {
                                appModel.triggerCamera(.fitToView)
                            }
                            .keyboardShortcut("f", modifiers: [.command])

                            Divider()

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
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "camera")
                                    .font(.caption)
                                Text("Camera")
                                    .font(.caption)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                        }
                        .menuStyle(.borderlessButton)
                        .help("Camera View Presets (⌘1 ~ ⌘4, ⌘F)")

                        Divider()
                            .frame(height: 12)

                        // Export Menu
                        Menu {
                            Button {
                                if let scn = currentSCNView?.scene {
                                    ExportManager.exportUSDZ(scene: scn, defaultName: appModel.document?.robotName ?? "Robot")
                                }
                            } label: {
                                Label("Export 3D Model (USDZ)…", systemImage: "cube.transparent")
                            }
                            .disabled(appModel.document == nil)

                            Button {
                                if let view = currentSCNView {
                                    ExportManager.exportSnapshot(from: view, defaultName: appModel.document?.robotName ?? "Robot")
                                }
                            } label: {
                                Label("Export Viewport Snapshot (PNG)…", systemImage: "camera.viewfinder")
                            }

                            Button {
                                if let view = currentSCNView {
                                    ExportManager.copySnapshotToClipboard(from: view)
                                }
                            } label: {
                                Label("Copy Snapshot to Clipboard", systemImage: "doc.on.doc")
                            }
                            .keyboardShortcut("c", modifiers: [.command, .option])
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                                .padding(3)
                        }
                        .menuStyle(.borderlessButton)
                        .help("Export 3D Model or Snapshot (USDZ, PNG)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                // Navigation Controls Quick Guide at bottom-right
                if appModel.document != nil {
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Label("좌클릭: 회전", systemImage: "arrow.triangle.2.circlepath")
                            Text("·").foregroundStyle(.tertiary)
                            Label("우클릭: 이동", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            Text("·").foregroundStyle(.tertiary)
                            Label("휠: 확대/축소", systemImage: "plus.magnifyingglass")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
                        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 1)
                        .padding(.trailing, 16)
                        .padding(.bottom, 10)
                    }
                }
            }
        }
    }

    // MARK: - Welcome Overlay
    private var welcomeOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.transparent.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .shadow(color: Color.accentColor.opacity(0.4), radius: 12)

            VStack(spacing: 6) {
                Text("Welcome to MacURDF")
                    .font(.title2.bold())
                Text("Drop a .urdf file or robot package folder anywhere to view")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    appModel.openURDF()
                } label: {
                    Label("Open URDF…", systemImage: "doc.badge.plus")
                        .font(.callout.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("o", modifiers: [.command])

                Button {
                    appModel.grantPackageFolderAccess()
                } label: {
                    Label("Grant Package Access…", systemImage: "folder.badge.plus")
                        .font(.callout)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }

            Divider()
                .frame(width: 320)

            // Sample Models Card
            VStack(spacing: 8) {
                Text("Try Sample Robots")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    SampleButton(title: "Simple Arm", icon: "cube.fill") {
                        appModel.loadSample(name: "simple_arm")
                    }
                    SampleButton(title: "Mesh Arm (STL)", icon: "shippingbox.fill") {
                        appModel.loadSample(name: "simple_arm_mesh")
                    }
                    SampleButton(title: "Package Robot", icon: "archivebox.fill") {
                        appModel.loadSample(name: "pkg_robot")
                    }
                }
            }

            // Navigation guide
            HStack(spacing: 16) {
                Label("Left Click: Orbit", systemImage: "hand.draw")
                Label("Right/Shift: Pan", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                Label("Scroll: Zoom", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
    }
}

private struct SampleButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.caption2.bold())
            }
            .frame(width: 100, height: 56)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

enum CameraPreset: Sendable {
    case reset
    case fitToView
    case isometric
    case front
    case side
    case top
}

enum ViewportScene {
    static func makeBaseEnvironment(showGrid: Bool, showWorldAxes: Bool) -> SCNScene {
        let scene = SCNScene()

        let ambient = SCNNode()
        ambient.light = {
            let l = SCNLight()
            l.type = .ambient
            l.intensity = 450
            return l
        }()
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = {
            let l = SCNLight()
            l.type = .directional
            l.intensity = 850
            l.castsShadow = true
            l.shadowMode = .deferred
            l.shadowColor = NSColor.black.withAlphaComponent(0.4)
            return l
        }()
        sun.eulerAngles = SCNVector3(-0.85, 0.45, 0)
        scene.rootNode.addChildNode(sun)

        if showGrid {
            scene.rootNode.addChildNode(gridNode(size: 20, step: 1))
        }
        if showWorldAxes {
            scene.rootNode.addChildNode(axisNode())
        }

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.001
        camera.camera?.zFar = 500
        camera.camera?.automaticallyAdjustsZRange = false
        camera.position = SCNVector3(2.5, 2.0, 4.0)
        camera.look(at: SCNVector3(0, 0.2, 0))
        camera.name = "MainCamera"
        scene.rootNode.addChildNode(camera)

        return scene
    }

    private static func gridNode(size: Int, step: Int) -> SCNNode {
        let parent = SCNNode()
        parent.name = "Grid"
        let half = Double(size) / 2.0
        let color = NSColor.gray.withAlphaComponent(0.28)
        for i in stride(from: -size / 2, through: size / 2, by: step) {
            let t = Double(i)
            parent.addChildNode(line(from: SCNVector3(-half, 0, t), to: SCNVector3(half, 0, t), color: color))
            parent.addChildNode(line(from: SCNVector3(t, 0, -half), to: SCNVector3(t, 0, half), color: color))
        }
        return parent
    }

    private static func axisNode() -> SCNNode {
        let parent = SCNNode()
        parent.name = "WorldAxes"
        let len: Double = 1.0
        parent.addChildNode(line(from: .init(0, 0, 0), to: .init(len, 0, 0), color: .systemRed))
        parent.addChildNode(line(from: .init(0, 0, 0), to: .init(0, len, 0), color: .systemGreen))
        parent.addChildNode(line(from: .init(0, 0, 0), to: .init(0, 0, len), color: .systemBlue))
        return parent
    }

    private static func line(from: SCNVector3, to: SCNVector3, color: NSColor) -> SCNNode {
        let positions = [from, to]
        let source = SCNGeometrySource(vertices: positions)
        let indices: [UInt8] = [0, 1]
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geo = SCNGeometry(sources: [source], elements: [element])
        geo.firstMaterial?.diffuse.contents = color
        geo.firstMaterial?.lightingModel = .constant
        return SCNNode(geometry: geo)
    }

    static func configureCameraClipping(cameraNode: SCNNode?, fitting target: SCNNode?) {
        guard let cam = cameraNode?.camera else { return }
        cam.zNear = 0.001
        cam.zFar = 500
        cam.automaticallyAdjustsZRange = false
        guard let target else { return }
        let (bmin, bmax) = target.boundingBox
        let dx = Double(bmax.x - bmin.x)
        let dy = Double(bmax.y - bmin.y)
        let dz = Double(bmax.z - bmin.z)
        let extent = (dx * dx + dy * dy + dz * dz).squareRoot()
        if extent.isFinite, extent > 1e-6 {
            cam.zNear = max(0.0001, extent * 0.00005)
            cam.zFar = max(200, extent * 100)
        }
    }
}

struct SceneViewRepresentable: NSViewRepresentable {
    var sceneEpoch: Int
    var jointState: JointState
    var document: URDFDocument?
    var audits: [MeshAudit]
    var renderMode: RenderMode
    var selectedLinkName: String?
    var useZUpToYUp: Bool
    var tealMeshTint: Bool
    var showGrid: Bool
    var showWorldAxes: Bool
    var showCoordinateFrames: Bool
    var viewportTheme: ViewportTheme
    var invertOrbit: Bool
    var cameraTrigger: (preset: CameraPreset, epoch: Int)?
    var linkTransforms: [String: simd_float4x4]
    var meshNode: (URL) -> SCNNode?
    var onViewCreated: (SCNView) -> Void

    final class Coordinator {
        var appliedEpoch: Int = -1
        var appliedCameraEpoch: Int = -1
        var linkNodes: [String: SCNNode] = [:]
        var robotRootName: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> CADSceneView {
        let view = CADSceneView()
        view.backgroundColor = viewportTheme.nsColor
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.getBoundingBox = { [weak view] in
            guard let scene = view?.scene else { return nil }
            return self.getRobotBoundingBox(in: scene)
        }
        rebuild(view: view, context: context, preserveCamera: false)
        if let cam = view.pointOfView?.camera {
            cam.zNear = 0.001
            cam.zFar = 500
            cam.automaticallyAdjustsZRange = false
        }
        DispatchQueue.main.async {
            onViewCreated(view)
        }
        return view
    }

    func updateNSView(_ nsView: CADSceneView, context: Context) {
        nsView.backgroundColor = viewportTheme.nsColor
        nsView.cameraController?.invertOrbit = invertOrbit

        if context.coordinator.appliedEpoch != sceneEpoch {
            rebuild(view: nsView, context: context, preserveCamera: true)
            return
        }

        applyTransforms(context.coordinator)

        if let trigger = cameraTrigger, trigger.epoch != context.coordinator.appliedCameraEpoch {
            context.coordinator.appliedCameraEpoch = trigger.epoch
            let bb = getRobotBoundingBox(in: nsView.scene ?? SCNScene())
            nsView.cameraController?.applyPreset(trigger.preset, boundingBox: bb)
        }

        if let cam = nsView.pointOfView?.camera, cam.zNear > 0.05 {
            cam.zNear = 0.001
            cam.automaticallyAdjustsZRange = false
            if cam.zFar < 100 { cam.zFar = 500 }
        }
    }

    private func rebuild(view: CADSceneView, context: Context, preserveCamera: Bool) {
        let scene: SCNScene
        if let existing = view.scene, preserveCamera {
            scene = existing
            let removable = scene.rootNode.childNodes.filter { node in
                let n = node.name ?? ""
                return n != "MainCamera" && n != "Grid" && n != "WorldAxes" && node.light == nil
            }
            removable.forEach { $0.removeFromParentNode() }
            if let doc = document {
                scene.rootNode.addChildNode(
                    RobotSceneBuilder.makeRobotRoot(
                        document: doc,
                        audits: audits,
                        transforms: linkTransforms,
                        renderMode: renderMode,
                        selectedLinkName: selectedLinkName,
                        useZUpToYUp: useZUpToYUp,
                        tealMeshTint: tealMeshTint,
                        showCoordinateFrames: showCoordinateFrames,
                        meshNode: meshNode
                    )
                )
            }
        } else {
            scene = RobotSceneBuilder.buildScene(
                document: document,
                audits: audits,
                transforms: linkTransforms,
                renderMode: renderMode,
                selectedLinkName: selectedLinkName,
                useZUpToYUp: useZUpToYUp,
                tealMeshTint: tealMeshTint,
                showGrid: showGrid,
                showWorldAxes: showWorldAxes,
                showCoordinateFrames: showCoordinateFrames,
                meshNode: meshNode
            )
            view.scene = scene
            if let cam = scene.rootNode.childNode(withName: "MainCamera", recursively: false) {
                view.pointOfView = cam
            }
        }

        var map: [String: SCNNode] = [:]
        if let doc = document {
            let root = scene.rootNode.childNode(withName: doc.robotName, recursively: true)
            context.coordinator.robotRootName = doc.robotName
            if let root {
                for link in doc.links {
                    if let node = root.childNode(withName: link.name, recursively: false) {
                        map[link.name] = node
                    }
                }
            }
        } else {
            context.coordinator.robotRootName = nil
        }
        context.coordinator.linkNodes = map
        context.coordinator.appliedEpoch = sceneEpoch

        let camNode = scene.rootNode.childNode(withName: "MainCamera", recursively: false) ?? view.pointOfView
        let bb = getRobotBoundingBox(in: scene)
        if view.cameraController == nil || !preserveCamera {
            view.cameraController = CADCameraController(cameraNode: camNode, scnView: view)
            view.cameraController?.invertOrbit = invertOrbit
            if let bb {
                view.cameraController?.applyPreset(.reset, boundingBox: bb)
            }
        } else {
            view.cameraController?.cameraNode = camNode
            view.cameraController?.invertOrbit = invertOrbit
        }

        let fit = document.flatMap { scene.rootNode.childNode(withName: $0.robotName, recursively: true) }
            ?? scene.rootNode.childNode(withName: "URDFWorldCorrection", recursively: false)
        ViewportScene.configureCameraClipping(cameraNode: camNode, fitting: fit)
        if let cam = camNode?.camera {
            view.pointOfView?.camera?.zNear = cam.zNear
            view.pointOfView?.camera?.zFar = cam.zFar
            view.pointOfView?.camera?.automaticallyAdjustsZRange = false
        }
    }

    private func applyTransforms(_ coordinator: Coordinator) {
        for (name, node) in coordinator.linkNodes {
            node.simdTransform = linkTransforms[name] ?? matrix_identity_float4x4
        }
    }

    private func getRobotBoundingBox(in scene: SCNScene) -> (min: SCNVector3, max: SCNVector3)? {
        let target = document.flatMap { scene.rootNode.childNode(withName: $0.robotName, recursively: true) }
            ?? scene.rootNode.childNode(withName: "URDFWorldCorrection", recursively: false)
        return target?.hierarchicalBoundingBox
    }
}

// MARK: - Hierarchical Bounding Box Extension
extension SCNNode {
    var hierarchicalBoundingBox: (min: SCNVector3, max: SCNVector3)? {
        var overallMin: SCNVector3?
        var overallMax: SCNVector3?

        func visit(_ node: SCNNode, transform: SCNMatrix4) {
            let localTransform = SCNMatrix4Mult(node.transform, transform)
            if let geo = node.geometry {
                let (bmin, bmax) = geo.boundingBox
                if bmin.x != bmax.x || bmin.y != bmax.y || bmin.z != bmax.z {
                    let corners = [
                        SCNVector3(bmin.x, bmin.y, bmin.z),
                        SCNVector3(bmax.x, bmin.y, bmin.z),
                        SCNVector3(bmin.x, bmax.y, bmin.z),
                        SCNVector3(bmax.x, bmax.y, bmin.z),
                        SCNVector3(bmin.x, bmin.y, bmax.z),
                        SCNVector3(bmax.x, bmin.y, bmax.z),
                        SCNVector3(bmin.x, bmax.y, bmax.z),
                        SCNVector3(bmax.x, bmax.y, bmax.z),
                    ]
                    for pt in corners {
                        let wpt = SCNVector3(
                            CGFloat(Double(localTransform.m11) * Double(pt.x) + Double(localTransform.m21) * Double(pt.y) + Double(localTransform.m31) * Double(pt.z) + Double(localTransform.m41)),
                            CGFloat(Double(localTransform.m12) * Double(pt.x) + Double(localTransform.m22) * Double(pt.y) + Double(localTransform.m32) * Double(pt.z) + Double(localTransform.m42)),
                            CGFloat(Double(localTransform.m13) * Double(pt.x) + Double(localTransform.m23) * Double(pt.y) + Double(localTransform.m33) * Double(pt.z) + Double(localTransform.m43))
                        )
                        if let omin = overallMin, let omax = overallMax {
                            overallMin = SCNVector3(min(omin.x, wpt.x), min(omin.y, wpt.y), min(omin.z, wpt.z))
                            overallMax = SCNVector3(max(omax.x, wpt.x), max(omax.y, wpt.y), max(omax.z, wpt.z))
                        } else {
                            overallMin = wpt
                            overallMax = wpt
                        }
                    }
                }
            }
            for child in node.childNodes {
                visit(child, transform: localTransform)
            }
        }

        visit(self, transform: SCNMatrix4Identity)
        if let min = overallMin, let max = overallMax {
            return (min, max)
        }
        return nil
    }
}

// MARK: - CAD Camera Controller (Orbit, Pan, Zoom)
final class CADCameraController {
    weak var cameraNode: SCNNode?
    weak var scnView: SCNView?

    var target: SCNVector3 = SCNVector3(0, 0.2, 0)
    var distance: Double = 3.2
    var azimuth: Double = .pi / 4.0      // 45 degrees
    var elevation: Double = 0.52         // ~30 degrees

    var orbitSensitivity: Double = 0.007
    var panSensitivity: Double = 0.0016
    var zoomSensitivity: Double = 0.04
    var invertOrbit: Bool = false

    init(cameraNode: SCNNode?, scnView: SCNView?) {
        self.cameraNode = cameraNode
        self.scnView = scnView
        syncFromCameraNode()
    }

    func syncFromCameraNode() {
        guard let cam = cameraNode else { return }
        let dx = Double(cam.position.x - target.x)
        let dy = Double(cam.position.y - target.y)
        let dz = Double(cam.position.z - target.z)
        let r = (dx * dx + dy * dy + dz * dz).squareRoot()
        if r > 0.01 {
            distance = r
            elevation = asin(max(-1.0, min(1.0, dy / r)))
            azimuth = atan2(dx, dz)
        }
    }

    func updateCameraTransform(animated: Bool = false, duration: TimeInterval = 0.35) {
        guard let cam = cameraNode else { return }
        let cosElev = cos(elevation)
        let sinElev = sin(elevation)
        let cosAzim = cos(azimuth)
        let sinAzim = sin(azimuth)

        let cx = target.x + CGFloat(distance * cosElev * sinAzim)
        let cy = target.y + CGFloat(distance * sinElev)
        let cz = target.z + CGFloat(distance * cosElev * cosAzim)

        let apply = {
            let camPos = SCNVector3(cx, cy, cz)

            // Forward vector from camera pointing toward target (normalized)
            let fX = Double(self.target.x - cx)
            let fY = Double(self.target.y - cy)
            let fZ = Double(self.target.z - cz)
            let fLen = (fX * fX + fY * fY + fZ * fZ).squareRoot()
            guard fLen > 1e-6 else { return }

            let F = SCNVector3(CGFloat(fX / fLen), CGFloat(fY / fLen), CGFloat(fZ / fLen))

            // Right vector: cross(F, WorldUp=(0, 1, 0)) -> (-F.z, 0, F.x)
            let rX = Double(-F.z)
            let rZ = Double(F.x)
            let rLen = (rX * rX + rZ * rZ).squareRoot()

            let R: SCNVector3
            if rLen > 1e-6 {
                R = SCNVector3(CGFloat(rX / rLen), 0, CGFloat(rZ / rLen))
            } else {
                R = SCNVector3(1, 0, 0)
            }

            // Up vector = cross(R, F)
            let uX = Double(R.y * F.z - R.z * F.y)
            let uY = Double(R.z * F.x - R.x * F.z)
            let uZ = Double(R.x * F.y - R.y * F.x)
            let uLen = (uX * uX + uY * uY + uZ * uZ).squareRoot()
            let U = uLen > 1e-6 ? SCNVector3(CGFloat(uX / uLen), CGFloat(uY / uLen), CGFloat(uZ / uLen)) : SCNVector3(0, 1, 0)

            // Strictly zero-roll orthonormal camera matrix:
            // Column 1 = Right (always horizontal, R.y == 0)
            // Column 2 = Up
            // Column 3 = Back (-F)
            // Column 4 = Position
            cam.transform = SCNMatrix4(
                m11: R.x, m12: R.y, m13: R.z, m14: 0,
                m21: U.x, m22: U.y, m23: U.z, m24: 0,
                m31: -F.x, m32: -F.y, m33: -F.z, m34: 0,
                m41: camPos.x, m42: camPos.y, m43: camPos.z, m44: 1
            )
        }

        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            apply()
            SCNTransaction.commit()
        } else {
            apply()
        }
    }

    // Left click drag: Orbit around target
    func orbit(deltaX: Double, deltaY: Double) {
        // Invert horizontal rotation per user request (dragging right rotates object to the right)
        let hSign: Double = invertOrbit ? 1.0 : -1.0
        azimuth += hSign * deltaX * orbitSensitivity

        // Maintain vertical rotation per user request ("위아래 회전은 수정 안해도 돼")
        elevation += deltaY * orbitSensitivity

        let maxElev = 1.45 // ~83.1 degrees to prevent gimbal singularity
        elevation = max(-maxElev, min(maxElev, elevation))
        updateCameraTransform(animated: false)
    }

    // Right click drag / Middle drag: Pan camera and target
    func pan(deltaX: Double, deltaY: Double) {
        guard let cam = cameraNode else { return }
        let transform = cam.transform
        let right = SCNVector3(transform.m11, transform.m12, transform.m13)
        let up = SCNVector3(transform.m21, transform.m22, transform.m23)

        let factor = CGFloat(distance * panSensitivity)
        let shiftX = (-CGFloat(deltaX) * right.x + CGFloat(deltaY) * up.x) * factor
        let shiftY = (-CGFloat(deltaX) * right.y + CGFloat(deltaY) * up.y) * factor
        let shiftZ = (-CGFloat(deltaX) * right.z + CGFloat(deltaY) * up.z) * factor

        target.x += shiftX
        target.y += shiftY
        target.z += shiftZ

        updateCameraTransform(animated: false)
    }

    // Scroll wheel: Zoom in/out
    func zoom(deltaY: Double, isPrecise: Bool) {
        let factor = isPrecise ? (1.0 - deltaY * 0.005) : (1.0 - deltaY * zoomSensitivity)
        let clampedFactor = max(0.5, min(1.8, factor))
        distance = max(0.05, min(300.0, distance * clampedFactor))
        updateCameraTransform(animated: false)
    }

    func zoomByMagnification(_ magnification: Double) {
        let factor = 1.0 / (1.0 + magnification)
        let clampedFactor = max(0.5, min(1.8, factor))
        distance = max(0.05, min(300.0, distance * clampedFactor))
        updateCameraTransform(animated: false)
    }

    func applyPreset(_ preset: CameraPreset, boundingBox: (min: SCNVector3, max: SCNVector3)? = nil) {
        if let bb = boundingBox {
            target = SCNVector3(
                (bb.min.x + bb.max.x) / 2,
                (bb.min.y + bb.max.y) / 2,
                (bb.min.z + bb.max.z) / 2
            )
            let dx = Double(bb.max.x - bb.min.x)
            let dy = Double(bb.max.y - bb.min.y)
            let dz = Double(bb.max.z - bb.min.z)
            let extent = max(0.4, (dx * dx + dy * dy + dz * dz).squareRoot())
            distance = extent * 2.2
        }

        switch preset {
        case .reset, .isometric:
            azimuth = .pi / 4.0
            elevation = 0.55
        case .fitToView:
            break
        case .front:
            azimuth = 0
            elevation = 0
        case .side:
            azimuth = .pi / 2.0
            elevation = 0
        case .top:
            azimuth = 0
            elevation = 1.45
        }

        updateCameraTransform(animated: true, duration: 0.35)
    }
}

// MARK: - CAD Interactive SCNView
final class CADSceneView: SCNView {
    var cameraController: CADCameraController?
    var getBoundingBox: (() -> (min: SCNVector3, max: SCNVector3)?)?

    private var didDragRight = false
    private var isDraggingRight = false

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Left Mouse (Orbit)
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            cameraController?.pan(deltaX: Double(event.deltaX), deltaY: Double(event.deltaY))
        } else {
            cameraController?.orbit(deltaX: Double(event.deltaX), deltaY: Double(event.deltaY))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 {
            cameraController?.applyPreset(.fitToView, boundingBox: getBoundingBox?())
        }
    }

    // MARK: - Right Mouse (Pan / Move)
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        didDragRight = false
        isDraggingRight = true
    }

    override func rightMouseDragged(with event: NSEvent) {
        if !didDragRight {
            didDragRight = true
            NSCursor.closedHand.push()
        }
        cameraController?.pan(deltaX: Double(event.deltaX), deltaY: Double(event.deltaY))
    }

    override func rightMouseUp(with event: NSEvent) {
        isDraggingRight = false
        if didDragRight {
            NSCursor.pop()
        } else {
            super.rightMouseUp(with: event)
        }
    }

    // MARK: - Middle Mouse (Pan / Move)
    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func otherMouseDragged(with event: NSEvent) {
        cameraController?.pan(deltaX: Double(event.deltaX), deltaY: Double(event.deltaY))
    }

    // MARK: - Wheel (Zoom)
    override func scrollWheel(with event: NSEvent) {
        cameraController?.zoom(
            deltaY: Double(event.scrollingDeltaY),
            isPrecise: event.hasPreciseScrollingDeltas
        )
    }

    // MARK: - Trackpad Pinch (Zoom)
    override func magnify(with event: NSEvent) {
        cameraController?.zoomByMagnification(Double(event.magnification))
    }

    // MARK: - Context Menu
    override func menu(for event: NSEvent) -> NSMenu? {
        if isDraggingRight || didDragRight {
            return nil
        }
        let menu = NSMenu(title: "Viewport")
        let fitItem = NSMenuItem(title: "Fit to View", action: #selector(fitToViewMenuAction), keyEquivalent: "f")
        fitItem.target = self
        menu.addItem(fitItem)

        let resetItem = NSMenuItem(title: "Reset Camera", action: #selector(resetCameraMenuAction), keyEquivalent: ".")
        resetItem.target = self
        menu.addItem(resetItem)

        return menu
    }

    @objc private func fitToViewMenuAction() {
        cameraController?.applyPreset(.fitToView, boundingBox: getBoundingBox?())
    }

    @objc private func resetCameraMenuAction() {
        cameraController?.applyPreset(.reset, boundingBox: getBoundingBox?())
    }
}

import AppKit
import Combine
import Foundation
import SceneKit
import SwiftUI
import UniformTypeIdentifiers
import simd
import URDFCore

@MainActor
final class AppModel: ObservableObject {
    @Published var openedURL: URL?
    @Published var document: URDFDocument?
    @Published var jointState: JointState = JointState()
    @Published var meshAudits: [MeshAudit] = []
    @Published var packageHints: [URL] = []
    @Published var selectedJointName: String?
    @Published var selectedLinkName: String?
    @Published var statusMessage: String = "Open a .urdf file to begin."
    @Published var displayedIssues: [URDFIssue] = []

    // Display & Render Settings
    @Published var renderMode: RenderMode = .visual {
        didSet { rebuildSceneStructure() }
    }
    @Published var showVisual: Bool = true
    @Published var showCollision: Bool = false
    @Published var showGrid: Bool = true {
        didSet { rebuildSceneStructure() }
    }
    @Published var showWorldAxes: Bool = true {
        didSet { rebuildSceneStructure() }
    }
    @Published var showCoordinateFrames: Bool = false {
        didSet { rebuildSceneStructure() }
    }
    @Published var viewportTheme: ViewportTheme = .darkSlate
    @Published var useZUpToYUp: Bool = true
    @Published var tealMeshTint: Bool = false
    @Published var showIssuesPanel: Bool = true
    @Published var invertOrbit: Bool = false

    // Units & Kinematics Control
    @Published var useDegrees: Bool = true
    @Published var isDemoAnimating: Bool = false
    @Published var rawXMLContent: String = ""

    // Scene & Camera Triggers
    @Published private(set) var sceneEpoch: Int = 0
    @Published var cameraTrigger: (preset: CameraPreset, epoch: Int)? = nil

    private let loader = URDFLoader()
    private let meshResolver = LocalMeshResolver()
    private let fk = ForwardKinematics()
    private let meshLoader = MeshLoader()

    private var meshNodeCache: [URL: SCNNode] = [:]
    private var securityScopedURLs: [URL] = []
    private var persistentPackageRoots: [URL] = []
    private var demoTimerCancellable: AnyCancellable?
    private var demoTime: Double = 0

    var linkTransforms: [String: simd_float4x4] {
        guard let doc = document else { return [:] }
        return fk.transforms(document: doc, state: jointState)
    }

    func triggerCamera(_ preset: CameraPreset) {
        let nextEpoch = (cameraTrigger?.epoch ?? 0) + 1
        cameraTrigger = (preset, nextEpoch)
    }

    // MARK: - Document Loading

    func openURDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.urdf, .xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select a URDF file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url, securityScoped: true)
        promptPackageRootAccess(suggestedNear: url)
    }

    func grantPackageFolderAccess() {
        let near = openedURL ?? persistentPackageRoots.first
        promptPackageRootAccess(suggestedNear: near)
    }

    func noteOpenedDocument(url: URL?) {
        guard let url else { return }
        load(url: url, securityScoped: true)
        promptPackageRootAccess(suggestedNear: url)
    }

    func loadSample(name: String) {
        let bundleURL = Bundle.main.bundleURL
        let candidates = [
            bundleURL.appendingPathComponent("Contents/Resources/fixtures/\(name)"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("fixtures/\(name)"),
            URL(fileURLWithPath: "/Users/acb/MacURDF/fixtures/\(name)")
        ]
        for c in candidates {
            if FileManager.default.fileExists(atPath: c.path) {
                loadFromFolder(c)
                return
            }
        }
        statusMessage = "Sample '\(name)' not found"
    }

    func load(url: URL, securityScoped: Bool = true) {
        stopDemoAnimation()
        releaseEphemeralSecurityScopedAccess()
        if securityScoped {
            beginSecurityScopedAccess(forDocument: url)
        }
        for root in persistentPackageRoots {
            retainSecurityScopedIfNeeded(root)
        }

        openedURL = url
        mergePackageHint(fromDocumentURL: url)
        for hint in packageHints {
            retainSecurityScopedIfNeeded(hint)
        }

        meshNodeCache.removeAll()

        do {
            if let data = try? Data(contentsOf: url) {
                rawXMLContent = String(data: data, encoding: .utf8) ?? ""
            }

            let raw = try loader.load(urdfURL: url)
            let (audited, audits) = raw.applyingMeshAudit(
                resolver: meshResolver,
                packageHints: packageHints
            )
            apply(document: audited, audits: audits)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            triggerCamera(.fitToView)
        } catch {
            document = nil
            meshAudits = []
            jointState = JointState()
            rawXMLContent = ""
            displayedIssues = [
                URDFIssue(
                    severity: .error,
                    file: url.lastPathComponent,
                    message: "Failed to load URDF: \(error.localizedDescription)",
                    hint: "Check XML well-formedness and path"
                ),
            ]
            statusMessage = "Load failed — \(url.lastPathComponent)"
            rebuildSceneStructure()
        }
    }

    func loadFromFolder(_ folderURL: URL) {
        rememberPackageRoot(folderURL)
        let urdfs = urdfFiles(in: folderURL)
        if urdfs.isEmpty {
            displayedIssues = [
                URDFIssue(
                    severity: .error,
                    file: folderURL.lastPathComponent,
                    message: "폴더에 .urdf 파일이 없습니다",
                    hint: "URDF가 있는 패키지 폴더(예: rbpodo_description)를 드롭하세요"
                ),
            ]
            statusMessage = "No .urdf in folder"
            return
        }
        if urdfs.count > 1 {
            load(url: urdfs[0], securityScoped: true)
            appendIssue(
                severity: .warning,
                file: folderURL.lastPathComponent,
                message: "폴더에 .urdf가 \(urdfs.count)개 있어 첫 파일만 로드했습니다: \(urdfs[0].lastPathComponent)",
                hint: "원하는 파일이면 File > Open으로 직접 선택하세요"
            )
            refreshStatusFromDocument()
            return
        }
        load(url: urdfs[0], securityScoped: true)
    }

    func reload() {
        guard let url = openedURL else {
            statusMessage = "Reload — no file open"
            return
        }
        load(url: url, securityScoped: true)
    }

    // MARK: - Joint State & Kinematics Control

    func setJoint(_ name: String, value: Double) {
        guard let doc = document else { return }
        var next = jointState
        next.values[name] = value
        next.clamp(to: doc)
        jointState = next
    }

    func displayValue(forJointName name: String, rawRadian: Double) -> Double {
        guard let doc = document, let j = doc.joints.first(where: { $0.name == name }) else {
            return rawRadian
        }
        if (j.type == .revolute || j.type == .continuous) && useDegrees {
            return rawRadian * 180.0 / .pi
        }
        return rawRadian
    }

    func setJointFromDisplay(_ name: String, displayValue: Double) {
        guard let doc = document, let j = doc.joints.first(where: { $0.name == name }) else {
            setJoint(name, value: displayValue)
            return
        }
        if (j.type == .revolute || j.type == .continuous) && useDegrees {
            let radians = displayValue * .pi / 180.0
            setJoint(name, value: radians)
        } else {
            setJoint(name, value: displayValue)
        }
    }

    func displayRange(forJoint joint: Joint) -> ClosedRange<Double> {
        let isAngle = (joint.type == .revolute || joint.type == .continuous)
        let mult = (isAngle && useDegrees) ? (180.0 / .pi) : 1.0

        switch joint.type {
        case .continuous:
            return (-Double.pi * mult)...(Double.pi * mult)
        case .revolute:
            if let limit = joint.limit, limit.lower < limit.upper {
                return (limit.lower * mult)...(limit.upper * mult)
            }
            return (-Double.pi * mult)...(Double.pi * mult)
        case .prismatic:
            if let limit = joint.limit, limit.lower < limit.upper {
                return limit.lower...limit.upper
            }
            return (-1.0)...1.0
        default:
            return (-1.0)...1.0
        }
    }

    func unitSuffix(forJoint joint: Joint) -> String {
        switch joint.type {
        case .revolute, .continuous:
            return useDegrees ? "°" : "rad"
        case .prismatic:
            return "m"
        default:
            return ""
        }
    }

    func resetAllJointsToZero() {
        guard let doc = document else { return }
        stopDemoAnimation()
        var next = JointState.zero(for: doc)
        next.clamp(to: doc)
        jointState = next
    }

    func randomizeJoints() {
        guard let doc = document else { return }
        stopDemoAnimation()
        var next = jointState
        for j in doc.joints {
            switch j.type {
            case .revolute:
                let lower = j.limit?.lower ?? -.pi
                let upper = j.limit?.upper ?? .pi
                next.values[j.name] = Double.random(in: lower...upper)
            case .continuous:
                next.values[j.name] = Double.random(in: -.pi...(.pi))
            case .prismatic:
                let lower = j.limit?.lower ?? -0.5
                let upper = j.limit?.upper ?? 0.5
                next.values[j.name] = Double.random(in: lower...upper)
            default:
                break
            }
        }
        next.clamp(to: doc)
        jointState = next
    }

    func toggleDemoAnimation() {
        if isDemoAnimating {
            stopDemoAnimation()
        } else {
            startDemoAnimation()
        }
    }

    func startDemoAnimation() {
        guard document != nil else { return }
        isDemoAnimating = true
        demoTime = 0
        demoTimerCancellable = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.stepDemoAnimation()
            }
    }

    func stopDemoAnimation() {
        isDemoAnimating = false
        demoTimerCancellable?.cancel()
        demoTimerCancellable = nil
    }

    private func stepDemoAnimation() {
        guard let doc = document else { return }
        demoTime += 0.04
        var next = jointState

        for (idx, j) in doc.joints.enumerated() {
            let phase = Double(idx) * 0.8
            let wave = sin(demoTime * 1.5 + phase)

            switch j.type {
            case .revolute:
                let lower = j.limit?.lower ?? -.pi / 2
                let upper = j.limit?.upper ?? .pi / 2
                let mid = (lower + upper) / 2
                let span = (upper - lower) / 2 * 0.8
                next.values[j.name] = mid + wave * span
            case .continuous:
                next.values[j.name] = wave * .pi
            case .prismatic:
                let lower = j.limit?.lower ?? -0.3
                let upper = j.limit?.upper ?? 0.3
                let mid = (lower + upper) / 2
                let span = (upper - lower) / 2 * 0.8
                next.values[j.name] = mid + wave * span
            default:
                break
            }
        }
        next.clamp(to: doc)
        jointState = next
    }

    // MARK: - Selection & Display Toggles

    func selectJoint(_ name: String?) {
        selectedJointName = name
        if let name, let doc = document,
           let joint = doc.joints.first(where: { $0.name == name }) {
            selectedLinkName = joint.child
        }
        rebuildSceneStructure()
    }

    func selectLink(_ name: String?) {
        selectedLinkName = name
        rebuildSceneStructure()
    }

    func setShowVisual(_ value: Bool) {
        showVisual = value
        renderMode = value ? (showCollision ? .both : .visual) : (showCollision ? .collision : .visual)
    }

    func setShowCollision(_ value: Bool) {
        showCollision = value
        renderMode = value ? (showVisual ? .both : .collision) : (showVisual ? .visual : .collision)
    }

    func setUseZUpToYUp(_ value: Bool) {
        useZUpToYUp = value
        rebuildSceneStructure()
    }

    func setTealMeshTint(_ value: Bool) {
        tealMeshTint = value
        meshNodeCache.removeAll()
        rebuildSceneStructure()
    }

    func setShowIssuesPanel(_ value: Bool) {
        showIssuesPanel = value
    }

    func toggleIssuesPanel() {
        showIssuesPanel.toggle()
    }

    // MARK: - Mesh Loading & Resolution

    func nodeForResolvedMesh(url: URL) -> SCNNode? {
        if let cached = meshNodeCache[url] {
            let clone = cached.clone()
            applyMeshTint(toNode: clone)
            return clone
        }
        let ext = url.pathExtension.lowercased()
        if ext == "dae" {
            if let node = loadDAENode(url: url) {
                meshNodeCache[url] = node
                let clone = node.clone()
                if tealMeshTint {
                    applyMeshTint(toNode: clone)
                }
                return clone
            }
            if let stlURL = collisionSTLSibling(ofVisualDAE: url) {
                retainSecurityScopedIfNeeded(stlURL)
                retainSecurityScopedIfNeeded(stlURL.deletingLastPathComponent())
                if let stlNode = loadSTLOrOBJNode(url: stlURL) {
                    let linkHint = stlURL.deletingPathExtension().lastPathComponent
                    appendIssue(
                        severity: .warning,
                        file: url.lastPathComponent,
                        message: "SceneKit이 DAE를 열 수 없어 collision STL로 표시 (\(linkHint))",
                        hint: "DAE: \(url.lastPathComponent) → STL: \(stlURL.path)"
                    )
                    meshNodeCache[url] = stlNode
                    meshNodeCache[stlURL] = stlNode
                    let clone = stlNode.clone()
                    applyMeshTint(toNode: clone)
                    return clone
                }
            }
            return nil
        }
        if let node = loadSTLOrOBJNode(url: url) {
            let clone = node.clone()
            applyMeshTint(toNode: clone)
            return clone
        }
        return nil
    }

    private func applyMeshTint(to geometry: SCNGeometry) {
        let color: NSColor = tealMeshTint ? .systemTeal : .lightGray
        geometry.firstMaterial?.diffuse.contents = color
    }

    private func applyMeshTint(toNode node: SCNNode) {
        let color: NSColor = tealMeshTint ? .systemTeal : .lightGray
        node.enumerateHierarchy { child, _ in
            if child.geometry != nil {
                child.geometry?.firstMaterial?.diffuse.contents = color
            }
        }
    }

    func geometryForResolvedMesh(url: URL) -> SCNGeometry? {
        nodeForResolvedMesh(url: url)?.geometry
    }

    private func loadSTLOrOBJNode(url: URL) -> SCNNode? {
        if let cached = meshNodeCache[url] {
            return cached
        }
        do {
            _ = try Data(contentsOf: url, options: [.mappedIfSafe])
            let buffer = try meshLoader.load(url: url)
            let geo = MeshBufferSceneKit.geometry(from: buffer)
            applyMeshTint(to: geo)
            let node = SCNNode(geometry: geo)
            meshNodeCache[url] = node
            return node
        } catch {
            return nil
        }
    }

    private func collisionSTLSibling(ofVisualDAE daeURL: URL) -> URL? {
        let stem = daeURL.deletingPathExtension().lastPathComponent
        let parent = daeURL.deletingLastPathComponent()
        var candidates: [URL] = []
        if parent.lastPathComponent.lowercased() == "visual" {
            let collisionDir = parent.deletingLastPathComponent().appendingPathComponent("collision", isDirectory: true)
            candidates.append(collisionDir.appendingPathComponent("\(stem).stl"))
            candidates.append(collisionDir.appendingPathComponent("\(stem).STL"))
        }
        candidates.append(parent.appendingPathComponent("\(stem).stl"))
        candidates.append(
            parent.deletingLastPathComponent()
                .appendingPathComponent("collision", isDirectory: true)
                .appendingPathComponent("\(stem).stl")
        )
        for root in persistentPackageRoots + packageHints {
            candidates.append(
                root.appendingPathComponent("meshes", isDirectory: true)
                    .appendingPathComponent("collision", isDirectory: true)
                    .appendingPathComponent("\(stem).stl")
            )
            let meshes = root.appendingPathComponent("meshes", isDirectory: true)
            if let kids = try? FileManager.default.contentsOfDirectory(
                at: meshes,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for kid in kids {
                    candidates.append(
                        kid.appendingPathComponent("collision", isDirectory: true)
                            .appendingPathComponent("\(stem).stl")
                    )
                }
            }
        }
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) {
                return url.standardizedFileURL
            }
        }
        return nil
    }

    private func loadDAENode(url: URL) -> SCNNode? {
        retainSecurityScopedIfNeeded(url.deletingLastPathComponent())
        retainSecurityScopedIfNeeded(url)

        do {
            let options: [SCNSceneSource.LoadingOption: Any] = [
                .assetDirectoryURLs: [url.deletingLastPathComponent()],
                .createNormalsIfAbsent: true,
                .checkConsistency: true,
            ]
            let scene = try SCNScene(url: url, options: options)
            let wrapper = SCNNode()
            wrapper.name = url.lastPathComponent
            for child in scene.rootNode.childNodes {
                wrapper.addChildNode(child.clone())
            }
            if wrapper.childNodes.isEmpty {
                if let geo = scene.rootNode.geometry {
                    wrapper.geometry = geo
                    wrapper.morpher = scene.rootNode.morpher
                } else {
                    return nil
                }
            }
            var hasGeometry = wrapper.geometry != nil
            wrapper.enumerateChildNodes { child, _ in
                if child.geometry != nil { hasGeometry = true }
            }
            return hasGeometry ? wrapper : nil
        } catch {
            return nil
        }
    }

    private func appendIssue(
        severity: URDFIssue.Severity,
        file: String?,
        message: String,
        hint: String?
    ) {
        let issue = URDFIssue(
            severity: severity,
            file: file,
            tag: "mesh",
            message: message,
            hint: hint
        )
        if !displayedIssues.contains(where: { $0.message == issue.message && $0.file == issue.file }) {
            displayedIssues = displayedIssues + [issue]
        }
    }

    private func refreshStatusFromDocument() {
        let name = document?.robotName ?? openedURL?.deletingPathExtension().lastPathComponent ?? "—"
        refreshStatusMessage(
            robotName: name,
            linkCount: document?.links.count ?? 0,
            jointCount: document?.joints.count ?? 0
        )
    }

    private func refreshStatusMessage(robotName: String, linkCount: Int, jointCount: Int) {
        let errN = displayedIssues.filter { $0.severity == .error }.count
        let warnN = displayedIssues.filter { $0.severity == .warning }.count
        statusMessage =
            "\(robotName) — \(linkCount) links, \(jointCount) joints"
            + (errN + warnN > 0 ? " · \(errN) errors, \(warnN) warnings" : "")
    }

    private func apply(document doc: URDFDocument, audits: [MeshAudit]) {
        document = doc
        meshAudits = audits
        jointState = .zero(for: doc)
        jointState.clamp(to: doc)
        selectedJointName = nil
        selectedLinkName = nil
        displayedIssues = doc.errors + doc.warnings
        for audit in audits {
            if case let .resolved(url) = audit.resolution {
                retainSecurityScopedIfNeeded(url.deletingLastPathComponent())
                retainSecurityScopedIfNeeded(url)
                _ = nodeForResolvedMesh(url: url)
            }
        }
        refreshStatusMessage(
            robotName: doc.robotName,
            linkCount: doc.links.count,
            jointCount: doc.joints.count
        )
        rebuildSceneStructure()
    }

    private func rebuildSceneStructure() {
        sceneEpoch &+= 1
    }

    // MARK: - Security-scoped access (App Sandbox)

    private func promptPackageRootAccess(suggestedNear url: URL?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Select package root folder (e.g. rbpodo_description) so visual/collision meshes load under App Sandbox"
        panel.prompt = "Grant Access"
        if let url {
            panel.directoryURL = url
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        rememberPackageRoot(dir)
        remountMeshesAfterPackageGrant()
    }

    private func rememberPackageRoot(_ url: URL) {
        let standardized = url.standardizedFileURL
        retainSecurityScopedIfNeeded(standardized)
        if !persistentPackageRoots.contains(standardized) {
            persistentPackageRoots.append(standardized)
        }
        addPackageHint(standardized)
        addPackageHint(standardized.appendingPathComponent("meshes", isDirectory: true))
    }

    private func remountMeshesAfterPackageGrant() {
        guard let url = openedURL else {
            refreshStatusFromDocument()
            rebuildSceneStructure()
            return
        }
        meshNodeCache.removeAll()
        do {
            let raw = try loader.load(urdfURL: url)
            let (audited, audits) = raw.applyingMeshAudit(
                resolver: meshResolver,
                packageHints: packageHints
            )
            apply(document: audited, audits: audits)
        } catch {
            refreshStatusFromDocument()
            rebuildSceneStructure()
        }
    }

    private func beginSecurityScopedAccess(forDocument url: URL) {
        retainSecurityScopedIfNeeded(url)
        retainSecurityScopedIfNeeded(url.deletingLastPathComponent())
        retainSecurityScopedIfNeeded(url.deletingLastPathComponent().deletingLastPathComponent())
    }

    @discardableResult
    private func retainSecurityScopedIfNeeded(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        if securityScopedURLs.contains(standardized) { return true }
        if standardized.startAccessingSecurityScopedResource() {
            securityScopedURLs.append(standardized)
            return true
        }
        return false
    }

    private func releaseEphemeralSecurityScopedAccess() {
        let keep = Set(persistentPackageRoots.map(\.standardizedFileURL))
        var kept: [URL] = []
        for url in securityScopedURLs {
            let s = url.standardizedFileURL
            if keep.contains(s) {
                kept.append(s)
            } else {
                url.stopAccessingSecurityScopedResource()
            }
        }
        securityScopedURLs = kept
    }

    private func mergePackageHint(fromDocumentURL url: URL) {
        let dir = url.deletingLastPathComponent()
        addPackageHint(dir)
        addPackageHint(dir.deletingLastPathComponent())
    }

    func addPackageHint(_ url: URL) {
        let standardized = url.standardizedFileURL
        if !packageHints.contains(standardized) {
            packageHints.append(standardized)
        }
        retainSecurityScopedIfNeeded(standardized)
    }

    private func urdfFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "urdf" {
                results.append(fileURL)
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    deinit {
        demoTimerCancellable?.cancel()
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

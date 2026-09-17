import AppKit
import Foundation
import SceneKit
import simd
import URDFCore

enum RenderMode: String, CaseIterable, Identifiable {
    case visual = "Visual"
    case collision = "Collision"
    case both = "Both"
    case wireframe = "Wireframe"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .visual: return "cube.fill"
        case .collision: return "shield.lefthalf.filled"
        case .both: return "square.2.layers.3d"
        case .wireframe: return "grid"
        }
    }
}

enum RobotSceneBuilder {
    static func buildScene(
        document: URDFDocument?,
        audits: [MeshAudit],
        transforms: [String: simd_float4x4],
        renderMode: RenderMode,
        selectedLinkName: String?,
        useZUpToYUp: Bool,
        tealMeshTint: Bool,
        showGrid: Bool,
        showWorldAxes: Bool,
        showCoordinateFrames: Bool,
        meshNode: (URL) -> SCNNode?
    ) -> SCNScene {
        let scene = ViewportScene.makeBaseEnvironment(showGrid: showGrid, showWorldAxes: showWorldAxes)
        guard let document else {
            return scene
        }
        scene.rootNode.addChildNode(
            makeRobotRoot(
                document: document,
                audits: audits,
                transforms: transforms,
                renderMode: renderMode,
                selectedLinkName: selectedLinkName,
                useZUpToYUp: useZUpToYUp,
                tealMeshTint: tealMeshTint,
                showCoordinateFrames: showCoordinateFrames,
                meshNode: meshNode
            )
        )
        return scene
    }

    static func makeRobotRoot(
        document: URDFDocument,
        audits: [MeshAudit],
        transforms: [String: simd_float4x4],
        renderMode: RenderMode,
        selectedLinkName: String?,
        useZUpToYUp: Bool,
        tealMeshTint: Bool,
        showCoordinateFrames: Bool,
        meshNode: (URL) -> SCNNode?
    ) -> SCNNode {
        let auditByLinkFile: [String: MeshResolution] = {
            var map: [String: MeshResolution] = [:]
            for a in audits {
                map["\(a.linkName)|\(a.filename)"] = a.resolution
            }
            return map
        }()

        let robotRoot = SCNNode()
        robotRoot.name = document.robotName

        let shouldShowVisual = (renderMode == .visual || renderMode == .both || renderMode == .wireframe)
        let shouldShowCollision = (renderMode == .collision || renderMode == .both)
        let isWireframe = (renderMode == .wireframe)

        for link in document.links {
            let linkNode = SCNNode()
            linkNode.name = link.name
            linkNode.simdTransform = transforms[link.name] ?? matrix_identity_float4x4

            // Visual geometries
            if shouldShowVisual {
                let visuals = link.visuals
                if visuals.isEmpty && !shouldShowCollision {
                    let geo = node(
                        for: .box(size: SIMD3(0.05, 0.05, 0.05)),
                        linkName: link.name,
                        link: link,
                        auditMap: auditByLinkFile,
                        color: .systemGray,
                        isWireframe: isWireframe,
                        meshNode: meshNode,
                        preserveMaterials: false
                    )
                    geo.name = "\(link.name)_visual_fallback"
                    linkNode.addChildNode(geo)
                } else {
                    for (idx, visual) in visuals.enumerated() {
                        let geo = node(
                            for: visual.geometry,
                            linkName: link.name,
                            link: link,
                            auditMap: auditByLinkFile,
                            color: tealMeshTint ? .systemTeal : .lightGray,
                            isWireframe: isWireframe,
                            meshNode: meshNode,
                            preserveMaterials: true
                        )
                        geo.name = "\(link.name)_visual_\(idx)"
                        geo.simdTransform = PoseMath.matrix(from: visual.origin)
                        linkNode.addChildNode(geo)
                    }
                }
            }

            // Collision geometries
            if shouldShowCollision {
                for (idx, collision) in link.collisions.enumerated() {
                    let geo = node(
                        for: collision.geometry,
                        linkName: link.name,
                        link: link,
                        auditMap: auditByLinkFile,
                        color: NSColor.systemOrange.withAlphaComponent(0.45),
                        isWireframe: false,
                        meshNode: meshNode,
                        preserveMaterials: false
                    )
                    geo.name = "\(link.name)_collision_\(idx)"
                    geo.simdTransform = PoseMath.matrix(from: collision.origin)
                    geo.enumerateHierarchy { child, _ in
                        child.geometry?.firstMaterial?.transparency = 0.45
                    }
                    linkNode.addChildNode(geo)
                }
            }

            // TF Coordinate Frame (Local XYZ axes)
            if showCoordinateFrames || selectedLinkName == link.name {
                let tfAxes = makeCoordinateFrameNode(scale: selectedLinkName == link.name ? 0.15 : 0.08)
                tfAxes.name = "TFAxes"
                linkNode.addChildNode(tfAxes)
            }

            // Selection Halo
            if selectedLinkName == link.name {
                let halo = SCNNode(geometry: SCNSphere(radius: 0.04))
                halo.geometry?.firstMaterial?.diffuse.contents = NSColor.systemYellow
                halo.geometry?.firstMaterial?.transparency = 0.5
                halo.name = "selectionHalo"
                linkNode.addChildNode(halo)
            }

            robotRoot.addChildNode(linkNode)
        }

        let world = SCNNode()
        world.name = "URDFWorldCorrection"
        if useZUpToYUp {
            world.simdOrientation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        }
        world.addChildNode(robotRoot)
        return world
    }

    static func makeCoordinateFrameNode(scale: Double) -> SCNNode {
        let frame = SCNNode()
        let axisRadius: CGFloat = CGFloat(scale * 0.04)
        let axisLength: CGFloat = CGFloat(scale)

        // X Axis: Red
        let xCyl = SCNCylinder(radius: axisRadius, height: axisLength)
        xCyl.firstMaterial?.diffuse.contents = NSColor.systemRed
        let xNode = SCNNode(geometry: xCyl)
        xNode.position = SCNVector3(scale / 2, 0, 0)
        xNode.eulerAngles = SCNVector3(0, 0, -Double.pi / 2)
        frame.addChildNode(xNode)

        // Y Axis: Green
        let yCyl = SCNCylinder(radius: axisRadius, height: axisLength)
        yCyl.firstMaterial?.diffuse.contents = NSColor.systemGreen
        let yNode = SCNNode(geometry: yCyl)
        yNode.position = SCNVector3(0, scale / 2, 0)
        frame.addChildNode(yNode)

        // Z Axis: Blue
        let zCyl = SCNCylinder(radius: axisRadius, height: axisLength)
        zCyl.firstMaterial?.diffuse.contents = NSColor.systemBlue
        let zNode = SCNNode(geometry: zCyl)
        zNode.position = SCNVector3(0, 0, scale / 2)
        zNode.eulerAngles = SCNVector3(Double.pi / 2, 0, 0)
        frame.addChildNode(zNode)

        return frame
    }

    static func collisionSTLURL(fromVisualDAE daeURL: URL) -> URL? {
        let stem = daeURL.deletingPathExtension().lastPathComponent
        let parent = daeURL.deletingLastPathComponent()
        var candidates: [URL] = []
        if parent.lastPathComponent.lowercased() == "visual" {
            let collisionDir = parent
                .deletingLastPathComponent()
                .appendingPathComponent("collision", isDirectory: true)
            candidates.append(collisionDir.appendingPathComponent("\(stem).stl"))
            candidates.append(collisionDir.appendingPathComponent("\(stem).STL"))
        }
        candidates.append(parent.appendingPathComponent("\(stem).stl"))
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url.standardizedFileURL
        }
        return nil
    }

    private static func collisionMeshFallback(
        link: Link,
        auditMap: [String: MeshResolution],
        meshNode: (URL) -> SCNNode?
    ) -> SCNNode? {
        for collision in link.collisions {
            guard case let .mesh(filename, scale) = collision.geometry else { continue }
            let key = "\(link.name)|\(filename)"
            if case let .resolved(url) = auditMap[key], let n = meshNode(url) {
                if let scale {
                    n.scale = SCNVector3(scale.x, scale.y, scale.z)
                }
                return n
            }
        }
        return nil
    }

    private static func node(
        for geometry: Geometry,
        linkName: String,
        link: Link?,
        auditMap: [String: MeshResolution],
        color: NSColor,
        isWireframe: Bool,
        meshNode: (URL) -> SCNNode?,
        preserveMaterials: Bool
    ) -> SCNNode {
        let resultNode: SCNNode
        switch geometry {
        case let .box(size):
            let box = SCNBox(
                width: CGFloat(size.x),
                height: CGFloat(size.y),
                length: CGFloat(size.z),
                chamferRadius: 0
            )
            box.firstMaterial?.diffuse.contents = color
            resultNode = SCNNode(geometry: box)

        case let .cylinder(radius, length):
            let cyl = SCNCylinder(radius: CGFloat(radius), height: CGFloat(length))
            cyl.firstMaterial?.diffuse.contents = color
            let n = SCNNode(geometry: cyl)
            n.eulerAngles = SCNVector3(Double.pi / 2, 0, 0)
            resultNode = n

        case let .sphere(radius):
            let sphere = SCNSphere(radius: CGFloat(radius))
            sphere.firstMaterial?.diffuse.contents = color
            resultNode = SCNNode(geometry: sphere)

        case let .mesh(filename, scale):
            let key = "\(linkName)|\(filename)"
            let resolution = auditMap[key]
            var loaded: SCNNode?

            if case let .resolved(url) = resolution {
                loaded = meshNode(url)
                if loaded == nil, url.pathExtension.lowercased() == "dae",
                   let stl = collisionSTLURL(fromVisualDAE: url) {
                    loaded = meshNode(stl)
                }
            }

            if loaded == nil,
               filename.lowercased().hasSuffix(".dae"),
               let link,
               let fallback = collisionMeshFallback(
                link: link,
                auditMap: auditMap,
                meshNode: meshNode
               ) {
                loaded = fallback
            }

            if let n = loaded {
                if !preserveMaterials {
                    n.enumerateHierarchy { child, _ in
                        child.geometry?.firstMaterial?.diffuse.contents = color
                    }
                }
                if let scale {
                    n.scale = SCNVector3(
                        n.scale.x * CGFloat(scale.x),
                        n.scale.y * CGFloat(scale.y),
                        n.scale.z * CGFloat(scale.z)
                    )
                }
                resultNode = n
            } else {
                let placeholderColor: NSColor
                switch resolution {
                case .resolved?: placeholderColor = .systemYellow
                case .unsupported?: placeholderColor = .systemOrange
                case .missing?, .none: placeholderColor = .systemRed
                }
                let box = SCNBox(width: 0.15, height: 0.15, length: 0.15, chamferRadius: 0.01)
                box.firstMaterial?.diffuse.contents = placeholderColor
                let n = SCNNode(geometry: box)
                n.name = "meshPlaceholder"
                if let scale {
                    n.scale = SCNVector3(scale.x, scale.y, scale.z)
                }
                resultNode = n
            }
        }

        if isWireframe {
            resultNode.enumerateHierarchy { child, _ in
                child.geometry?.firstMaterial?.fillMode = .lines
            }
        }

        return resultNode
    }
}

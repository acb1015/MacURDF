import SwiftUI
import URDFCore

typealias RobotLink = URDFCore.Link

enum LinkTreeTab: String, CaseIterable, Identifiable {
    case hierarchy = "Hierarchy"
    case links = "Links"
    case joints = "Joints"

    var id: String { rawValue }
}

struct KinematicTreeNode: Identifiable {
    var id: String { link.name }
    let link: RobotLink
    let jointToParent: Joint?
    var children: [KinematicTreeNode]
}

struct LinkTreeView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTab: LinkTreeTab = .hierarchy
    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Model Tree")
                        .font(.headline)
                    Spacer()
                    if let doc = appModel.document {
                        Text(doc.robotName)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Tree View", selection: $selectedTab) {
                    ForEach(LinkTreeTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter...", text: $searchText)
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
            .padding(10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Tree Content
            if let doc = appModel.document {
                Group {
                    switch selectedTab {
                    case .hierarchy:
                        hierarchyView(doc: doc)
                    case .links:
                        flatLinksView(doc: doc)
                    case .joints:
                        flatJointsView(doc: doc)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "square.3.layers.3d.down.right")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No Robot Loaded")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Open a .urdf file to inspect its kinematic link tree.")
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

    // MARK: - Hierarchy Tree
    @ViewBuilder
    private func hierarchyView(doc: URDFDocument) -> some View {
        let roots = buildKinematicTree(doc: doc)
        List {
            ForEach(roots) { rootNode in
                KinematicNodeRow(node: rootNode, searchText: searchText)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Flat Links
    @ViewBuilder
    private func flatLinksView(doc: URDFDocument) -> some View {
        let filtered = doc.links.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
        List(filtered, id: \.name) { link in
            HStack(spacing: 8) {
                Image(systemName: "cube.fill")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.name)
                        .font(.caption.bold())
                    HStack(spacing: 4) {
                        Text("\(link.visuals.count) visuals")
                        Text("•")
                        Text("\(link.collisions.count) collisions")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if let geoBadge = primaryGeometryBadge(link: link) {
                    Text(geoBadge)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
            .listRowBackground(
                appModel.selectedLinkName == link.name
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .onTapGesture {
                appModel.selectLink(link.name)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Flat Joints
    @ViewBuilder
    private func flatJointsView(doc: URDFDocument) -> some View {
        let filtered = doc.joints.filter {
            searchText.isEmpty
                || $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.parent.localizedCaseInsensitiveContains(searchText)
                || $0.child.localizedCaseInsensitiveContains(searchText)
        }
        List(filtered, id: \.name) { joint in
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(joint.type == .fixed ? Color.secondary : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(joint.name)
                            .font(.caption.bold())
                        Spacer()
                        Text(joint.type.rawValue.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                (joint.type == .fixed ? Color.secondary : Color.orange).opacity(0.18)
                            )
                            .clipShape(Capsule())
                    }
                    Text("\(joint.parent) → \(joint.child)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .listRowBackground(
                appModel.selectedJointName == joint.name
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .onTapGesture {
                appModel.selectJoint(joint.name)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Tree Construction
    private func buildKinematicTree(doc: URDFDocument) -> [KinematicTreeNode] {
        let childLinks = Set(doc.joints.map(\.child))
        let rootLinks = doc.links.filter { !childLinks.contains($0.name) }
        let effectiveRoots = rootLinks.isEmpty ? Array(doc.links.prefix(1)) : rootLinks

        func buildSubtree(link: RobotLink, parentJoint: Joint?) -> KinematicTreeNode {
            let outgoingJoints = doc.joints.filter { $0.parent == link.name }
            var children: [KinematicTreeNode] = []
            for j in outgoingJoints {
                if let childLink = doc.links.first(where: { $0.name == j.child }) {
                    children.append(buildSubtree(link: childLink, parentJoint: j))
                }
            }
            return KinematicTreeNode(link: link, jointToParent: parentJoint, children: children)
        }

        return effectiveRoots.map { buildSubtree(link: $0, parentJoint: nil) }
    }

    private func primaryGeometryBadge(link: RobotLink) -> String? {
        guard let first = link.visuals.first else { return nil }
        switch first.geometry {
        case .box: return "BOX"
        case .cylinder: return "CYL"
        case .sphere: return "SPH"
        case .mesh: return "MESH"
        }
    }
}

private struct KinematicNodeRow: View {
    @EnvironmentObject private var appModel: AppModel
    let node: KinematicTreeNode
    let searchText: String

    var matchesSearch: Bool {
        if searchText.isEmpty { return true }
        if node.link.name.localizedCaseInsensitiveContains(searchText) { return true }
        if let j = node.jointToParent?.name, j.localizedCaseInsensitiveContains(searchText) { return true }
        return node.children.contains(where: { childMatches($0) })
    }

    private func childMatches(_ n: KinematicTreeNode) -> Bool {
        if n.link.name.localizedCaseInsensitiveContains(searchText) { return true }
        if let j = n.jointToParent?.name, j.localizedCaseInsensitiveContains(searchText) { return true }
        return n.children.contains(where: { childMatches($0) })
    }

    var body: some View {
        if matchesSearch {
            if node.children.isEmpty {
                leafRow
            } else {
                DisclosureGroup(isExpanded: .constant(true)) {
                    ForEach(node.children) { child in
                        KinematicNodeRow(node: child, searchText: searchText)
                    }
                } label: {
                    rowContent
                }
            }
        }
    }

    private var leafRow: some View {
        rowContent
            .padding(.leading, 4)
    }

    private var rowContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "cube")
                .foregroundStyle(Color.accentColor)
                .font(.caption)

            VStack(alignment: .leading, spacing: 1) {
                Text(node.link.name)
                    .font(.caption.bold())
                if let j = node.jointToParent {
                    Text("via: \(j.name) (\(j.type.rawValue))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let j = node.jointToParent, j.type != .fixed {
                Text(j.type.rawValue.prefix(3).uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .contentShape(Rectangle())
        .listRowBackground(
            appModel.selectedLinkName == node.link.name
                ? Color.accentColor.opacity(0.2)
                : Color.clear
        )
        .onTapGesture {
            appModel.selectLink(node.link.name)
        }
    }
}

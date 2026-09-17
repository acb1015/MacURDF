import AppKit
import SwiftUI
import URDFCore

enum BottomDrawerTab: String, CaseIterable, Identifiable {
    case diagnostics = "Diagnostics"
    case specs = "Robot Specs"
    case source = "URDF Source"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .diagnostics: return "exclamationmark.triangle"
        case .specs: return "info.circle"
        case .source: return "curlybraces"
        }
    }
}

struct BottomDrawerView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTab: BottomDrawerTab = .diagnostics
    @State private var issueFilter: IssueFilter = .all
    @State private var searchQuery: String = ""

    enum IssueFilter: String, CaseIterable {
        case all = "All"
        case errors = "Errors"
        case warnings = "Warnings"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drawer Header Bar
            HStack(spacing: 12) {
                Picker("Drawer Tab", selection: $selectedTab) {
                    ForEach(BottomDrawerTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)

                if selectedTab == .diagnostics {
                    let errCount = appModel.displayedIssues.filter { $0.severity == .error }.count
                    let warnCount = appModel.displayedIssues.filter { $0.severity == .warning }.count

                    Picker("Filter", selection: $issueFilter) {
                        Text("All (\(appModel.displayedIssues.count))").tag(IssueFilter.all)
                        Text("Errors (\(errCount))").tag(IssueFilter.errors)
                        Text("Warnings (\(warnCount))").tag(IssueFilter.warnings)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)

                    Spacer()

                    Button {
                        copyIssuesToClipboard()
                    } label: {
                        Label("Copy Diagnostics", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(appModel.displayedIssues.isEmpty)
                } else if selectedTab == .source {
                    Spacer()
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(appModel.rawXMLContent, forType: .string)
                    } label: {
                        Label("Copy XML", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(appModel.rawXMLContent.isEmpty)
                } else {
                    Spacer()
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appModel.setShowIssuesPanel(false)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderless)
                .help("Collapse Panel (⇧⌘I)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Drawer Content Area
            Group {
                switch selectedTab {
                case .diagnostics:
                    diagnosticsView
                case .specs:
                    specsView
                case .source:
                    sourceView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    // MARK: - Diagnostics View
    private var filteredIssues: [URDFIssue] {
        appModel.displayedIssues.filter { issue in
            switch issueFilter {
            case .all: break
            case .errors: if issue.severity != .error { return false }
            case .warnings: if issue.severity != .warning { return false }
            }
            if searchQuery.isEmpty { return true }
            let q = searchQuery.lowercased()
            return issue.message.lowercased().contains(q)
                || (issue.file?.lowercased().contains(q) ?? false)
                || (issue.hint?.lowercased().contains(q) ?? false)
        }
    }

    private var diagnosticsView: some View {
        Group {
            if filteredIssues.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.green)
                    Text(appModel.displayedIssues.isEmpty ? "No issues detected" : "No issues matching filter")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredIssues.indices, id: \.self) { idx in
                    IssueRow(issue: filteredIssues[idx])
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Specs View
    private var specsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let doc = appModel.document {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                        StatCard(title: "Robot Name", value: doc.robotName, icon: "cube.fill")
                        StatCard(title: "Total Links", value: "\(doc.links.count)", icon: "square.3.layers.3d")
                        StatCard(title: "Total Joints", value: "\(doc.joints.count)", icon: "arrow.triangle.2.circlepath")
                        StatCard(
                            title: "Movable Joints",
                            value: "\(doc.joints.filter { $0.type != .fixed }.count)",
                            icon: "slider.horizontal.3"
                        )
                        StatCard(
                            title: "Fixed Joints",
                            value: "\(doc.joints.filter { $0.type == .fixed }.count)",
                            icon: "pin.fill"
                        )
                        StatCard(
                            title: "Mesh Audits",
                            value: "\(appModel.meshAudits.count)",
                            icon: "shippingbox.fill"
                        )
                    }

                    Divider()

                    Text("Joint Breakdown")
                        .font(.headline)
                    let groups = Dictionary(grouping: doc.joints, by: { $0.type.rawValue.capitalized })
                    HStack(spacing: 16) {
                        ForEach(groups.keys.sorted(), id: \.self) { type in
                            HStack(spacing: 6) {
                                Text(type)
                                    .font(.caption.bold())
                                Text("\(groups[type]?.count ?? 0)")
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    if !appModel.meshAudits.isEmpty {
                        Divider()
                        Text("Resolved Mesh Assets")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(appModel.meshAudits.indices, id: \.self) { idx in
                                let audit = appModel.meshAudits[idx]
                                HStack {
                                    Image(systemName: audit.resolutionIcon)
                                        .foregroundStyle(audit.resolutionColor)
                                    Text(audit.filename)
                                        .font(.caption.monospaced())
                                    Spacer()
                                    Text(audit.linkName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                } else {
                    Text("No robot document loaded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Source View
    private var sourceView: some View {
        Group {
            if appModel.rawXMLContent.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Open a URDF file to inspect XML source.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(appModel.rawXMLContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func copyIssuesToClipboard() {
        let lines = appModel.displayedIssues.map { issue in
            "[\(issue.severity.rawValue.uppercased())] \(issue.file ?? "-")\(issue.line.map { ":L\($0)" } ?? ""): \(issue.message) (Hint: \(issue.hint ?? "-"))"
        }
        let text = lines.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct IssueRow: View {
    let issue: URDFIssue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(issue.severity.rawValue.uppercased())
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            (issue.severity == .error ? Color.red : Color.orange).opacity(0.15)
                        )
                        .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                        .clipShape(Capsule())

                    if let file = issue.file {
                        Text(file)
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                    }
                    if let line = issue.line {
                        Text("Line \(line)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let tag = issue.tag {
                        Text("<\(tag)>")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(issue.message)
                    .font(.caption)
                    .textSelection(.enabled)

                if let hint = issue.hint, !hint.isEmpty {
                    Text("💡 \(hint)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private extension MeshAudit {
    var resolutionIcon: String {
        switch resolution {
        case .resolved: return "checkmark.circle.fill"
        case .missing: return "xmark.circle.fill"
        case .unsupported: return "exclamationmark.circle.fill"
        }
    }

    var resolutionColor: Color {
        switch resolution {
        case .resolved: return .green
        case .missing: return .red
        case .unsupported: return .orange
        }
    }
}

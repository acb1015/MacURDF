import AppKit
import Foundation
import SceneKit
import UniformTypeIdentifiers

@MainActor
enum ExportManager {
    static func exportUSDZ(scene: SCNScene, defaultName: String) {
        let panel = NSSavePanel()
        panel.title = "Export 3D Model (USDZ)"
        panel.message = "Choose a location to save the USDZ file (compatible with QuickLook, iOS, and visionOS)."
        panel.prompt = "Export"
        panel.allowedContentTypes = [UTType.usdz]
        panel.nameFieldStringValue = "\(defaultName).usdz"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let success = scene.write(
            to: url,
            options: nil,
            delegate: nil,
            progressHandler: nil
        )

        if !success {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = "SceneKit was unable to export the scene to USDZ."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    static func exportSnapshot(from view: SCNView, defaultName: String) {
        let snapshot = view.snapshot()
        let panel = NSSavePanel()
        panel.title = "Export Viewport Snapshot"
        panel.message = "Save high-resolution PNG image of the current 3D viewport."
        panel.prompt = "Save Image"
        panel.allowedContentTypes = [UTType.png]
        panel.nameFieldStringValue = "\(defaultName)_snapshot.png"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let tiff = snapshot.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            let alert = NSAlert()
            alert.messageText = "Save Failed"
            alert.informativeText = "Could not convert viewport image to PNG."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        do {
            try png.write(to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Save Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    static func copySnapshotToClipboard(from view: SCNView) {
        let snapshot = view.snapshot()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([snapshot])
    }
}

import AppKit
import SwiftUI

@main
struct FileConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("File Converter", id: "main") {
            ContentView(model: .shared)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 600, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Files…") { ContentView.chooseFiles(model: .shared) }
                    .keyboardShortcut("o")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Files and folders dropped on the Dock icon land here.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in ConverterModel.shared.add(urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

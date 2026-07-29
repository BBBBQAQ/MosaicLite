import SwiftUI

@main
struct MosaicLiteApp: App {
    @StateObject private var model = EditorModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { model.undo() }
                    .keyboardShortcut("z")
                    .disabled(!model.canUndo)
                Button("重做") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
            }
            CommandGroup(after: .newItem) {
                Button(model.contextualImportBehavior == .add ? "添加图片…" : "更换图片…") {
                    model.requestImport()
                }
                    .keyboardShortcut("o")
                Button("导出图片…") { model.exportImage() }
                    .keyboardShortcut("s")
                    .disabled(model.outputImage == nil)
            }
        }
    }
}

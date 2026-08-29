import AppKit
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
                Button("撤销".localized) { model.undo() }
                    .keyboardShortcut("z")
                    .disabled(!model.canUndo)
                Button("重做".localized) { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("剪切".localized) {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x")
                Button("拷贝".localized) {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c")
                Button("粘贴".localized) {
                    if !model.pasteImages() {
                        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    }
                }
                .keyboardShortcut("v")
            }
            CommandGroup(after: .newItem) {
                Button((model.contextualImportBehavior == .add ? "添加图片…" : "更换图片…").localized) {
                    model.requestImport()
                }
                    .keyboardShortcut("o")
                Button("导出图片…".localized) { model.exportImage() }
                    .keyboardShortcut("s")
                    .disabled(model.outputImage == nil)
            }
        }
    }
}

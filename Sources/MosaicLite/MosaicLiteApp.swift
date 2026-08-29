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
                Button("撤销") { model.undo() }
                    .keyboardShortcut("z")
                    .disabled(!model.canUndo)
                Button("重做") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("剪切") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x")
                Button("拷贝") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c")
                Button("粘贴") {
                    if !model.pasteImages() {
                        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    }
                }
                .keyboardShortcut("v")
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

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        HStack(spacing: 0) {
            ToolSidebar()
                .frame(width: 86)

            Divider()

            VStack(spacing: 0) {
                TopBar()
                Divider()
                EditorCanvas()
            }

            if model.showInspector {
                Divider()
                InspectorPanel()
                    .frame(width: 292)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $model.presentImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: model.pendingImportBehavior == .add
        ) { result in
            if case .success(let urls) = result {
                model.importURLs(urls, behavior: model.pendingImportBehavior)
            }
        }
        .onChange(of: model.tool) { _, newTool in
            if newTool == .crop {
                model.showsCropSelection = false
            }
            model.refreshOutput()
        }
        .alert(
            "导出失败",
            isPresented: Binding(
                get: { model.exportErrorMessage != nil },
                set: { if !$0 { model.exportErrorMessage = nil } }
            )
        ) {
            Button("好") { model.exportErrorMessage = nil }
        } message: {
            Text(model.exportErrorMessage ?? "请稍后重试。")
        }
    }
}

private struct ToolSidebar: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        VStack(spacing: 10) {
            SidebarBrandMark()
                .frame(height: 40)
                .help("MosaicLite")

            ForEach(EditorTool.allCases) { tool in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { model.tool = tool }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 19, weight: .medium))
                        Text(tool.rawValue)
                            .font(.caption)
                    }
                    .frame(width: 64, height: 58)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(SidebarButtonStyle(selected: model.tool == tool))
                .disabled(
                    model.tool == .stitch
                    && model.images.count > 1
                    && tool != .stitch
                )
                .help(
                    model.tool == .stitch && model.images.count > 1 && tool != .stitch
                    ? "请先应用拼接，再继续其他处理"
                    : tool.rawValue
                )
            }

            Spacer()

            Button {
                model.requestImport()
            } label: {
                Image(
                    systemName: model.contextualImportBehavior == .add
                    ? "plus"
                    : "arrow.triangle.2.circlepath"
                )
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .help(model.contextualImportBehavior == .add ? "添加图片" : "更换图片")
            .padding(.bottom, 14)
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }
}

private struct SidebarBrandMark: View {
    var body: some View {
        Canvas { context, _ in
            let color = Color.secondary.opacity(0.72)
            let stroke = StrokeStyle(
                lineWidth: 1.65,
                lineCap: .round,
                lineJoin: .round
            )

            var corners = Path()
            corners.move(to: CGPoint(x: 3, y: 9))
            corners.addLine(to: CGPoint(x: 3, y: 3))
            corners.addLine(to: CGPoint(x: 9, y: 3))
            corners.move(to: CGPoint(x: 15, y: 21))
            corners.addLine(to: CGPoint(x: 21, y: 21))
            corners.addLine(to: CGPoint(x: 21, y: 15))
            context.stroke(corners, with: .color(color), style: stroke)

            let pixelRects = [
                CGRect(x: 9, y: 9, width: 3, height: 3),
                CGRect(x: 13, y: 9, width: 3, height: 3),
                CGRect(x: 9, y: 13, width: 3, height: 3),
                CGRect(x: 13, y: 13, width: 3, height: 3)
            ]
            for (index, rect) in pixelRects.enumerated() {
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 0.7),
                    with: .color(
                        index == pixelRects.count - 1
                            ? Color.accentColor.opacity(0.68)
                            : color
                    )
                )
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

private struct SidebarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.13) : Color.clear)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.42), lineWidth: 0.7)
                        }
                    }
                    .shadow(color: selected ? .black.opacity(0.08) : .clear, radius: 3, y: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.36)
    }
}

private struct TopBar: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            Text(model.tool.rawValue)
                .font(.headline)
                .contentTransition(.interpolate)
                .animation(.easeOut(duration: 0.16), value: model.tool)

            if !model.images.isEmpty {
                Text(showsImageCount ? "\(model.images.count) 张图片" : selectedName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button { model.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)
            .help("撤销")

            Button { model.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!model.canRedo)
            .help("重做")

            Divider().frame(height: 20)

            Button {
                model.requestImport()
            } label: {
                Label(
                    model.contextualImportBehavior == .add ? "添加图片" : "更换图片",
                    systemImage: model.contextualImportBehavior == .add ? "photo.badge.plus" : "arrow.triangle.2.circlepath"
                )
            }
            .help(model.contextualImportBehavior == .add ? "继续添加图片" : "使用另一张图片替换当前工作图")

            Button { model.showInspector.toggle() } label: {
                Image(systemName: "sidebar.right")
            }
            .help("显示或隐藏参数面板")

            Button { model.exportImage() } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.outputImage == nil)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(.bar)
    }

    private var selectedName: String {
        model.images.first(where: { $0.id == model.selectedID })?.name
            ?? model.images.first?.name
            ?? ""
    }

    private var showsImageCount: Bool {
        model.tool == .stitch
            || (model.tool == .resize && model.resizeBatchMode)
            || (model.tool == .watermark && model.watermarkBatchMode)
    }
}

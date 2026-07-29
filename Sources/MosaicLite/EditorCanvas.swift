@preconcurrency import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorCanvas: View {
    @EnvironmentObject private var model: EditorModel
    @State private var isTargeted = false
    @State private var zoom: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CanvasBackdrop()

                if let image = model.outputImage {
                    imageView(image, in: geometry.size)
                } else {
                    EmptyCanvas()
                }

                if isTargeted {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .padding(28)
                        .background(Color.accentColor.opacity(0.06))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .background {
                ScrollWheelMonitor { delta in
                    guard model.outputImage != nil, abs(delta) > 0.01 else { return }
                    let factor = exp(delta * 0.018)
                    withAnimation(.easeOut(duration: 0.12)) {
                        zoom = min(max(zoom * factor, 0.08), 6)
                    }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.importURLs(
                    urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true },
                    behavior: model.contextualImportBehavior
                )
                return true
            } isTargeted: {
                isTargeted = $0
            }
            .overlay(alignment: .bottomLeading) {
                if model.outputImage != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: $zoom, in: 0.08...6)
                            .labelsHidden()
                            .frame(width: 124)
                            .help("拖动滑块或使用滚轮缩放")
                        Image(systemName: "plus.magnifyingglass")
                        Text("\(Int(zoom * 100))%")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { zoom = 1 }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.plain)
                        .help("恢复画布缩放")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(14)
                }
            }
        }
        .onChange(of: model.selectedID) { _, _ in zoom = 1 }
        .onChange(of: model.tool) { _, _ in zoom = 1 }
    }

    @ViewBuilder
    private func imageView(_ image: NSImage, in available: CGSize) -> some View {
        let pixelSize = image.pixelSize
        let fitted = displayedSize(
            pixelSize,
            inside: CGSize(width: available.width - 80, height: available.height - 80)
        )

        ZStack {
            Checkerboard()
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: fitted.width, height: fitted.height)

            if model.tool == .mosaic, let source = model.selectedImage {
                MosaicDrawingOverlay(
                    canvasSize: fitted,
                    imagePixelSize: source.pixelSize,
                    brush: model.mosaicBrush,
                    displayBrushSize: model.brushSize * fitted.width / max(1, source.pixelSize.width)
                ) { stroke in
                    model.strokes.append(stroke)
                    model.previewMosaic()
                }
            }

            if model.tool == .crop {
                CropOverlay(
                    selection: $model.cropRect,
                    isActive: $model.showsCropSelection
                )
            }
        }
        .frame(width: fitted.width, height: fitted.height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .overlay(alignment: .bottomTrailing) {
            Text("\(Int(pixelSize.width)) × \(Int(pixelSize.height))")
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
                .allowsHitTesting(false)
        }
        .animation(.snappy(duration: 0.3, extraBounce: 0.03), value: model.tool)
        .animation(.easeInOut(duration: 0.22), value: pixelSize)
    }

    private func displayedSize(_ size: CGSize, inside bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let reference = model.tool == .resize
            ? (model.selectedImage?.pixelSize ?? size)
            : size
        let baseScale = min(bounds.width / reference.width, bounds.height / reference.height, 1)
        return CGSize(
            width: size.width * baseScale * zoom,
            height: size.height * baseScale * zoom
        )
    }
}

private struct ScrollWheelMonitor: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var onScroll: (CGFloat) -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(onScroll: @escaping (CGFloat) -> Void) {
            self.onScroll = onScroll
        }

        func install(on view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let delta = event.scrollingDeltaY
                DispatchQueue.main.async { @MainActor [weak self] in
                    guard let self,
                          let view = self.view,
                          let window = view.window
                    else { return }
                    let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
                    guard view.bounds.contains(view.convert(windowPoint, from: nil)) else { return }
                    self.onScroll(delta)
                }
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private struct CropOverlay: View {
    @Binding var selection: CGRect
    @Binding var isActive: Bool
    @State private var moveStart: CGRect?
    @State private var selectionStart: CGPoint?
    private let minimumSize: CGFloat = 0.045

    var body: some View {
        GeometryReader { geometry in
            let rect = displayRect(in: geometry.size)

            ZStack {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(newSelectionGesture(canvasSize: geometry.size))

                if isActive {
                    Canvas { context, size in
                        var shade = Path(CGRect(origin: .zero, size: size))
                        shade.addPath(Path(rect))
                        context.fill(shade, with: .color(.black.opacity(0.48)), style: FillStyle(eoFill: true))

                        context.stroke(
                            Path(rect),
                            with: .color(.white),
                            style: StrokeStyle(lineWidth: 1.5)
                        )

                        var grid = Path()
                        for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
                            grid.move(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
                            grid.addLine(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY))
                            grid.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
                            grid.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * fraction))
                        }
                        context.stroke(grid, with: .color(.white.opacity(0.55)), lineWidth: 0.7)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .onHover { hovering in
                            if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
                        }
                        .gesture(moveGesture(canvasSize: geometry.size))

                    ForEach(CropHandle.allCases) { handle in
                        CropHandleView(handle: handle)
                            .position(handle.point(in: rect))
                            .gesture(resizeGesture(handle: handle, canvasSize: geometry.size))
                    }

                    Text("\(Int(selection.width * 100))% × \(Int(selection.height * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.62), in: Capsule())
                        .position(x: rect.midX, y: max(14, rect.minY - 17))
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "cropCanvas")
            .animation(.easeOut(duration: 0.14), value: isActive)
        }
    }

    private func newSelectionGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("cropCanvas"))
            .onChanged { value in
                let current = normalized(value.location, in: canvasSize)
                if selectionStart == nil {
                    selectionStart = current
                    isActive = true
                }
                guard let start = selectionStart else { return }
                let width = min(1, max(minimumSize, abs(current.x - start.x)))
                let height = min(1, max(minimumSize, abs(current.y - start.y)))
                let minX = min(min(start.x, current.x), 1 - width)
                let minY = min(min(start.y, current.y), 1 - height)
                selection = CGRect(
                    x: minX,
                    y: minY,
                    width: width,
                    height: height
                )
            }
            .onEnded { value in
                if abs(value.translation.width) < 4, abs(value.translation.height) < 4 {
                    selection = CGRect(x: 0, y: 0, width: 1, height: 1)
                    isActive = true
                }
                selectionStart = nil
            }
    }

    private func displayRect(in size: CGSize) -> CGRect {
        CGRect(
            x: selection.minX * size.width,
            y: selection.minY * size.height,
            width: selection.width * size.width,
            height: selection.height * size.height
        )
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x / max(1, size.width)), 1),
            y: min(max(0, point.y / max(1, size.height)), 1)
        )
    }

    private func moveGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .named("cropCanvas"))
            .onChanged { value in
                if moveStart == nil { moveStart = selection }
                guard let start = moveStart else { return }
                let dx = value.translation.width / max(1, canvasSize.width)
                let dy = value.translation.height / max(1, canvasSize.height)
                selection.origin.x = min(max(0, start.minX + dx), 1 - start.width)
                selection.origin.y = min(max(0, start.minY + dy), 1 - start.height)
            }
            .onEnded { _ in moveStart = nil }
    }

    private func resizeGesture(handle: CropHandle, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("cropCanvas"))
            .onChanged { value in
                let point = CGPoint(
                    x: min(max(0, value.location.x / max(1, canvasSize.width)), 1),
                    y: min(max(0, value.location.y / max(1, canvasSize.height)), 1)
                )
                var minX = selection.minX
                var maxX = selection.maxX
                var minY = selection.minY
                var maxY = selection.maxY

                switch handle {
                case .topLeft:
                    minX = min(point.x, maxX - minimumSize)
                    minY = min(point.y, maxY - minimumSize)
                case .top:
                    minY = min(point.y, maxY - minimumSize)
                case .topRight:
                    maxX = max(point.x, minX + minimumSize)
                    minY = min(point.y, maxY - minimumSize)
                case .left:
                    minX = min(point.x, maxX - minimumSize)
                case .right:
                    maxX = max(point.x, minX + minimumSize)
                case .bottomLeft:
                    minX = min(point.x, maxX - minimumSize)
                    maxY = max(point.y, minY + minimumSize)
                case .bottom:
                    maxY = max(point.y, minY + minimumSize)
                case .bottomRight:
                    maxX = max(point.x, minX + minimumSize)
                    maxY = max(point.y, minY + minimumSize)
                }
                selection = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
    }
}

private enum CropHandle: CaseIterable, Identifiable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight
    var id: Self { self }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    var isHorizontalEdge: Bool {
        self == .top || self == .bottom
    }

    var isVerticalEdge: Bool {
        self == .left || self == .right
    }

    var cursor: NSCursor {
        if isHorizontalEdge { return .resizeUpDown }
        if isVerticalEdge { return .resizeLeftRight }
        return .crosshair
    }
}

private struct CropHandleView: View {
    let handle: CropHandle

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(.white)
            .frame(width: handleWidth, height: handleHeight)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .contentShape(Rectangle().inset(by: -8))
            .onHover { hovering in
                if hovering { handle.cursor.push() } else { NSCursor.pop() }
            }
    }

    private var handleWidth: CGFloat {
        handle.isHorizontalEdge ? 28 : (handle.isVerticalEdge ? 7 : 13)
    }

    private var handleHeight: CGFloat {
        handle.isVerticalEdge ? 28 : (handle.isHorizontalEdge ? 7 : 13)
    }
}

private struct MosaicDrawingOverlay: View {
    let canvasSize: CGSize
    let imagePixelSize: CGSize
    let brush: MosaicBrush
    let displayBrushSize: CGFloat
    let onComplete: (MosaicStroke) -> Void
    @State private var currentPoints: [CGPoint] = []

    var body: some View {
        Canvas { context, _ in
            guard !currentPoints.isEmpty else { return }
            var path = Path()
            path.move(to: currentPoints[0])
            if brush == .rectangle, let last = currentPoints.last {
                path = Path(CGRect(
                    x: min(currentPoints[0].x, last.x),
                    y: min(currentPoints[0].y, last.y),
                    width: abs(last.x - currentPoints[0].x),
                    height: abs(last.y - currentPoints[0].y)
                ))
                context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            } else {
                for point in currentPoints.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(.accentColor.opacity(0.68)), style: StrokeStyle(lineWidth: displayBrushSize, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = clipped(value.location)
                    if brush == .rectangle {
                        if currentPoints.isEmpty { currentPoints = [point] }
                        if currentPoints.count == 1 { currentPoints.append(point) }
                        else { currentPoints[1] = point }
                    } else {
                        currentPoints.append(point)
                    }
                }
                .onEnded { _ in
                    guard currentPoints.count > 1 else { currentPoints.removeAll(); return }
                    let converted = currentPoints.map(toImagePoint)
                    onComplete(MosaicStroke(points: converted, isRectangle: brush == .rectangle))
                    currentPoints.removeAll()
                }
        )
        .onHover { hovering in
            if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
        }
    }

    private func clipped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), canvasSize.width),
            y: min(max(0, point.y), canvasSize.height)
        )
    }

    private func toImagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x / max(1, canvasSize.width) * imagePixelSize.width,
            y: (1 - point.y / max(1, canvasSize.height)) * imagePixelSize.height
        )
    }
}

private struct EmptyCanvas: View {
    @EnvironmentObject private var model: EditorModel
    var body: some View {
        Button { model.requestImport() } label: {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 82, height: 70)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.tint)
                }
                Text("拖入图片开始编辑")
                    .font(.title3.weight(.medium))
                Text("支持 PNG、JPEG、HEIC、TIFF")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("选择图片")
                    .padding(.horizontal, 15)
                    .padding(.vertical, 7)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CanvasBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .controlBackgroundColor),
                Color(nsColor: .windowBackgroundColor).opacity(0.82)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            Canvas { context, size in
                let spacing: CGFloat = 24
                for x in stride(from: spacing, through: size.width, by: spacing) {
                    for y in stride(from: spacing, through: size.height, by: spacing) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.3, height: 1.3)), with: .color(.secondary.opacity(0.12)))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for row in 0...Int(size.height / cell) {
                for column in 0...Int(size.width / cell) where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                        with: .color(.gray.opacity(0.13))
                    )
                }
            }
        }
    }
}

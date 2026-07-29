import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class EditorModel: ObservableObject {
    @Published var tool: EditorTool = .resize
    @Published var images: [ImageItem] = []
    @Published var selectedID: UUID?
    @Published var presentImporter = false
    @Published var pendingImportBehavior: ImageImportBehavior = .replace
    @Published var showInspector = true

    @Published var resizeUnit: ResizeUnit = .pixels
    @Published var resizeBatchMode = false
    @Published var targetWidth: Double = 1200
    @Published var targetHeight: Double = 800
    @Published var percent: Double = 100
    @Published var lockAspect = true

    @Published var cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @Published var showsCropSelection = true

    @Published var mosaicStyle: MosaicStyle = .pixel
    @Published var mosaicBrush: MosaicBrush = .rectangle
    @Published var mosaicIntensity: Double = 18
    @Published var brushSize: Double = 42
    @Published var strokes: [MosaicStroke] = []

    @Published var stitchDirection: StitchDirection = .horizontal
    @Published var stitchSpacing: Double = 12
    @Published var stitchBackground = Color.white

    @Published var watermarkBatchMode = false
    @Published var watermarkKind: WatermarkKind = .text
    @Published var watermarkText = "CONFIDENTIAL"
    @Published var watermarkOpacity: Double = 0.22
    @Published var watermarkFontSize: Double = 34
    @Published var watermarkSpacing: Double = 90
    @Published var watermarkAngle: Double = -28
    @Published var watermarkLogo: NSImage?
    @Published var watermarkLogoName = "尚未选择 Logo"
    @Published var watermarkLogoScale: Double = 0.18
    @Published var watermarkPosition: WatermarkPosition = .bottomRight
    @Published var watermarkPadding: Double = 28

    @Published private(set) var outputImage: NSImage?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var exportErrorMessage: String?

    private struct EditorSnapshot {
        var images: [ImageItem]
        var selectedID: UUID?
    }

    private let historyLimit = 12
    private var history: [EditorSnapshot] = []
    private var future: [EditorSnapshot] = []
    private var previewTask: Task<Void, Never>?
    private var previewRequestID = UUID()

    var selectedImage: NSImage? {
        images.first(where: { $0.id == selectedID })?.image ?? images.first?.image
    }

    var sourcePixelSize: CGSize {
        selectedImage?.pixelSize ?? .zero
    }

    var contextualImportBehavior: ImageImportBehavior {
        if tool == .stitch
            || (tool == .resize && resizeBatchMode)
            || (tool == .watermark && watermarkBatchMode) {
            return .add
        }
        return .replace
    }

    func requestImport(_ behavior: ImageImportBehavior? = nil) {
        pendingImportBehavior = behavior ?? contextualImportBehavior
        presentImporter = true
    }

    func importURLs(_ urls: [URL], behavior: ImageImportBehavior? = nil) {
        let additions = urls.compactMap { url -> ImageItem? in
            guard let image = NSImage(contentsOf: url) else { return nil }
            return ImageItem(image: image, name: url.deletingPathExtension().lastPathComponent)
        }
        guard !additions.isEmpty else { return }
        let resolvedBehavior = behavior ?? contextualImportBehavior
        switch resolvedBehavior {
        case .replace:
            guard let replacement = additions.first else { return }
            images = [replacement]
            selectedID = replacement.id
            history.removeAll()
            future.removeAll()
            strokes.removeAll()
            updateUndoState()
        case .add:
            recordCurrentState()
            images.append(contentsOf: additions)
            selectedID = selectedID ?? additions.first?.id
        }
        if let image = selectedImage {
            outputImage = image
            targetWidth = image.pixelSize.width
            targetHeight = image.pixelSize.height
        }
        cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        showsCropSelection = false
        refreshOutput()
    }

    func remove(_ item: ImageItem) {
        recordCurrentState()
        images.removeAll { $0.id == item.id }
        if selectedID == item.id { selectedID = images.first?.id }
        strokes.removeAll()
        refreshOutput()
    }

    func select(_ item: ImageItem) {
        selectedID = item.id
        refreshOutput()
    }

    func reorderImage(from draggedID: UUID, onto targetID: UUID) {
        guard draggedID != targetID,
              let sourceIndex = images.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = images.firstIndex(where: { $0.id == targetID })
        else { return }

        recordCurrentState()
        let movingItem = images.remove(at: sourceIndex)
        images.insert(movingItem, at: min(targetIndex, images.count))
        previewStitch()
    }

    func updateWidth(_ value: Double) {
        targetWidth = max(1, value)
        if lockAspect, sourcePixelSize.width > 0 {
            targetHeight = targetWidth * sourcePixelSize.height / sourcePixelSize.width
        }
        previewResize()
    }

    func updateHeight(_ value: Double) {
        targetHeight = max(1, value)
        if lockAspect, sourcePixelSize.height > 0 {
            targetWidth = targetHeight * sourcePixelSize.width / sourcePixelSize.height
        }
        previewResize()
    }

    func refreshOutput() {
        switch tool {
        case .resize: previewResize()
        case .crop: previewCrop()
        case .mosaic: previewMosaic()
        case .watermark: previewWatermark()
        case .stitch: previewStitch()
        }
    }

    func previewResize() {
        guard let source = selectedImage, let sourceCG = source.cgImageValue else {
            cancelPreview()
            outputImage = nil
            return
        }
        let dimensions = resizeDimensions(for: source)
        schedulePreview {
            let backgroundSource = NSImage(
                cgImage: sourceCG,
                size: NSSize(width: sourceCG.width, height: sourceCG.height)
            )
            return ImageProcessor.resize(
                backgroundSource,
                width: dimensions.width,
                height: dimensions.height
            )?.cgImageValue
        }
    }

    private func resizeDimensions(for image: NSImage) -> (width: Int, height: Int) {
        if resizeUnit == .percent {
            return (
                max(1, Int(image.pixelSize.width * percent / 100)),
                max(1, Int(image.pixelSize.height * percent / 100))
            )
        }
        if lockAspect && resizeBatchMode {
            let width = max(1, Int(targetWidth))
            let height = max(1, Int(Double(width) * image.pixelSize.height / image.pixelSize.width))
            return (width, height)
        }
        return (max(1, Int(targetWidth)), max(1, Int(targetHeight)))
    }

    func applyResize() {
        guard resizeBatchMode, images.count > 1 else {
            cancelPreview()
            guard let source = selectedImage,
                  let index = images.firstIndex(where: { $0.id == selectedID })
            else { return }
            let dimensions = resizeDimensions(for: source)
            guard let resized = ImageProcessor.resize(
                source,
                width: dimensions.width,
                height: dimensions.height
            ) else { return }
            recordCurrentState()
            images[index].image = resized
            outputImage = resized
            return
        }
        cancelPreview()
        recordCurrentState()
        for index in images.indices {
            let dimensions = resizeDimensions(for: images[index].image)
            if let resized = ImageProcessor.resize(
                images[index].image,
                width: dimensions.width,
                height: dimensions.height
            ) {
                images[index].image = resized
            }
        }
        outputImage = selectedImage
        updateUndoState()
    }

    func previewWatermark() {
        guard let source = selectedImage, let sourceCG = source.cgImageValue else {
            cancelPreview()
            outputImage = nil
            return
        }
        let kind = watermarkKind
        let text = watermarkText
        let opacity = watermarkOpacity
        let fontSize = watermarkFontSize
        let spacing = watermarkSpacing
        let angle = watermarkAngle
        let logoCG = watermarkLogo?.cgImageValue
        let logoScale = watermarkLogoScale
        let position = watermarkPosition
        let padding = watermarkPadding

        schedulePreview {
            let backgroundSource = NSImage(
                cgImage: sourceCG,
                size: NSSize(width: sourceCG.width, height: sourceCG.height)
            )
            switch kind {
            case .text:
                return ImageProcessor.textWatermark(
                    backgroundSource,
                    text: text,
                    opacity: opacity,
                    fontSize: fontSize,
                    spacing: spacing,
                    angle: angle
                )?.cgImageValue
            case .logo:
                guard let logoCG else { return sourceCG }
                let backgroundLogo = NSImage(
                    cgImage: logoCG,
                    size: NSSize(width: logoCG.width, height: logoCG.height)
                )
                return ImageProcessor.logoWatermark(
                    backgroundSource,
                    logo: backgroundLogo,
                    opacity: opacity,
                    scale: logoScale,
                    position: position,
                    padding: padding
                )?.cgImageValue
            }
        }
    }

    private func renderWatermark(on image: NSImage) -> NSImage? {
        switch watermarkKind {
        case .text:
            return ImageProcessor.textWatermark(
                image,
                text: watermarkText,
                opacity: watermarkOpacity,
                fontSize: watermarkFontSize,
                spacing: watermarkSpacing,
                angle: watermarkAngle
            )
        case .logo:
            guard let watermarkLogo else { return image }
            return ImageProcessor.logoWatermark(
                image,
                logo: watermarkLogo,
                opacity: watermarkOpacity,
                scale: watermarkLogoScale,
                position: watermarkPosition,
                padding: watermarkPadding
            )
        }
    }

    func applyWatermark() {
        guard watermarkBatchMode, images.count > 1 else {
            cancelPreview()
            guard let source = selectedImage,
                  let index = images.firstIndex(where: { $0.id == selectedID }),
                  let result = renderWatermark(on: source)
            else { return }
            recordCurrentState()
            images[index].image = result
            outputImage = result
            return
        }
        cancelPreview()
        recordCurrentState()
        for index in images.indices {
            if let result = renderWatermark(on: images[index].image) {
                images[index].image = result
            }
        }
        outputImage = selectedImage
        updateUndoState()
    }

    func selectWatermarkLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url)
        else { return }
        watermarkLogo = image
        watermarkLogoName = url.lastPathComponent
        previewWatermark()
    }

    func clearWatermarkLogo() {
        watermarkLogo = nil
        watermarkLogoName = "尚未选择 Logo"
        previewWatermark()
    }

    func previewCrop() {
        cancelPreview()
        outputImage = selectedImage
    }

    func applyCrop() {
        cancelPreview()
        guard let source = selectedImage,
              let cropped = ImageProcessor.crop(source, normalizedRect: cropRect),
              let index = images.firstIndex(where: { $0.id == selectedID }) else { return }
        recordCurrentState()
        images[index].image = cropped
        outputImage = cropped
        targetWidth = cropped.pixelSize.width
        targetHeight = cropped.pixelSize.height
        showsCropSelection = false
        updateUndoState()
    }

    func resetCrop() {
        cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        showsCropSelection = true
    }

    func previewMosaic() {
        guard let source = selectedImage, let sourceCG = source.cgImageValue else {
            cancelPreview()
            outputImage = nil
            return
        }
        let currentStrokes = strokes
        let style = mosaicStyle
        let intensity = mosaicIntensity
        let size = brushSize
        schedulePreview(delayMilliseconds: 0) {
            let backgroundSource = NSImage(
                cgImage: sourceCG,
                size: NSSize(width: sourceCG.width, height: sourceCG.height)
            )
            return ImageProcessor.mosaic(
                backgroundSource,
                strokes: currentStrokes,
                style: style,
                intensity: intensity,
                brushSize: size
            )?.cgImageValue
        }
    }

    func applyMosaic() {
        cancelPreview()
        guard let source = selectedImage,
              let index = images.firstIndex(where: { $0.id == selectedID }),
              let result = ImageProcessor.mosaic(
                source,
                strokes: strokes,
                style: mosaicStyle,
                intensity: mosaicIntensity,
                brushSize: brushSize
              )
        else { return }
        recordCurrentState()
        images[index].image = result
        outputImage = result
        strokes.removeAll()
    }

    func previewStitch() {
        let sourceImages = images.compactMap(\.image.cgImageValue)
        guard !sourceImages.isEmpty else {
            cancelPreview()
            outputImage = nil
            return
        }
        let direction = stitchDirection
        let spacing = stitchSpacing
        let background = NSColor(stitchBackground).cgColor
        schedulePreview {
            let backgroundImages = sourceImages.map {
                NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
            }
            return ImageProcessor.stitch(
                backgroundImages,
                direction: direction,
                spacing: spacing,
                background: NSColor(cgColor: background) ?? .white
            )?.cgImageValue
        }
    }

    func applyStitch() {
        cancelPreview()
        guard images.count >= 2,
              let composite = ImageProcessor.stitch(
                images.map(\.image),
                direction: stitchDirection,
                spacing: stitchSpacing,
                background: NSColor(stitchBackground)
              )
        else { return }
        recordCurrentState()
        let item = ImageItem(image: composite, name: "拼接图")
        images = [item]
        selectedID = item.id
        outputImage = composite
        targetWidth = composite.pixelSize.width
        targetHeight = composite.pixelSize.height
        strokes.removeAll()
        showsCropSelection = false
        updateUndoState()
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        future.append(currentSnapshot())
        restore(previous)
        updateUndoState()
    }

    func redo() {
        guard let next = future.popLast() else { return }
        appendToHistory(currentSnapshot())
        restore(next)
        updateUndoState()
    }

    private func currentSnapshot() -> EditorSnapshot {
        EditorSnapshot(images: images, selectedID: selectedID)
    }

    private func recordCurrentState() {
        appendToHistory(currentSnapshot())
        future.removeAll()
        updateUndoState()
    }

    private func appendToHistory(_ snapshot: EditorSnapshot) {
        history.append(snapshot)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    private func restore(_ snapshot: EditorSnapshot) {
        cancelPreview()
        images = snapshot.images
        selectedID = snapshot.selectedID.flatMap { id in
            images.contains(where: { $0.id == id }) ? id : nil
        } ?? images.first?.id
        strokes.removeAll()
        showsCropSelection = false

        if tool == .stitch, images.count > 1 {
            previewStitch()
        } else {
            outputImage = selectedImage
        }
        if let image = selectedImage {
            targetWidth = image.pixelSize.width
            targetHeight = image.pixelSize.height
        }
    }

    private func updateUndoState() {
        canUndo = !history.isEmpty
        canRedo = !future.isEmpty
    }

    func exportImage() {
        if ((tool == .resize && resizeBatchMode)
            || (tool == .watermark && watermarkBatchMode))
            && images.count > 1 {
            exportBatchImages()
            return
        }
        cancelPreview()
        outputImage = renderCurrentSynchronously()
        guard let outputImage, let cgImage = outputImage.cgImageValue else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "MosaicLite-导出.png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let representation = NSBitmapImageRep(cgImage: cgImage)
        let isJPEG = url.pathExtension.lowercased().contains("jp")
        let data = representation.representation(
            using: isJPEG ? .jpeg : .png,
            properties: isJPEG ? [.compressionFactor: 0.92] : [:]
        )
        guard let data else {
            exportErrorMessage = "无法生成图片数据，请尝试更换导出格式。"
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            exportErrorMessage = "无法保存图片：\(error.localizedDescription)"
        }
    }

    private func exportBatchImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "选择导出文件夹"
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        var failedNames: [String] = []
        for (index, item) in images.enumerated() {
            guard let cgImage = item.image.cgImageValue else {
                failedNames.append(item.name)
                continue
            }
            let safeName = item.name.replacingOccurrences(of: "/", with: "-")
            let url = directory.appendingPathComponent("\(safeName)-处理后-\(index + 1).png")
            let representation = NSBitmapImageRep(cgImage: cgImage)
            guard let data = representation.representation(using: .png, properties: [:]) else {
                failedNames.append(item.name)
                continue
            }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                failedNames.append(item.name)
            }
        }
        if !failedNames.isEmpty {
            exportErrorMessage = "以下图片导出失败：\(failedNames.joined(separator: "、"))"
        }
    }

    private func renderCurrentSynchronously() -> NSImage? {
        guard let source = selectedImage else { return nil }
        switch tool {
        case .resize:
            let dimensions = resizeDimensions(for: source)
            return ImageProcessor.resize(source, width: dimensions.width, height: dimensions.height)
        case .crop:
            return source
        case .mosaic:
            return ImageProcessor.mosaic(
                source,
                strokes: strokes,
                style: mosaicStyle,
                intensity: mosaicIntensity,
                brushSize: brushSize
            )
        case .watermark:
            return renderWatermark(on: source)
        case .stitch:
            return ImageProcessor.stitch(
                images.map(\.image),
                direction: stitchDirection,
                spacing: stitchSpacing,
                background: NSColor(stitchBackground)
            )
        }
    }

    private func schedulePreview(
        delayMilliseconds: UInt64 = 45,
        render: @escaping @Sendable () -> CGImage?
    ) {
        cancelPreview()
        let requestID = UUID()
        previewRequestID = requestID
        previewTask = Task { [weak self] in
            if delayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .userInitiated) {
                render()
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.previewRequestID == requestID,
                  let rendered
            else { return }
            self.outputImage = NSImage(
                cgImage: rendered,
                size: NSSize(width: rendered.width, height: rendered.height)
            )
        }
    }

    private func cancelPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewRequestID = UUID()
    }
}

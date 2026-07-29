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

    private var history: [NSImage] = []
    private var future: [NSImage] = []

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
        guard let source = selectedImage else { outputImage = nil; return }
        let dimensions = resizeDimensions(for: source)
        outputImage = ImageProcessor.resize(
            source,
            width: dimensions.width,
            height: dimensions.height
        )
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
            commitCurrent()
            return
        }
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
        history.removeAll()
        future.removeAll()
        outputImage = selectedImage
        updateUndoState()
    }

    func previewWatermark() {
        guard let source = selectedImage else { outputImage = nil; return }
        outputImage = renderWatermark(on: source)
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
            commitCurrent()
            return
        }
        for index in images.indices {
            if let result = renderWatermark(on: images[index].image) {
                images[index].image = result
            }
        }
        history.removeAll()
        future.removeAll()
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
        outputImage = selectedImage
    }

    func applyCrop() {
        guard let source = selectedImage,
              let cropped = ImageProcessor.crop(source, normalizedRect: cropRect),
              let index = images.firstIndex(where: { $0.id == selectedID }) else { return }
        history.append(images[index].image)
        future.removeAll()
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
        guard let source = selectedImage else { outputImage = nil; return }
        outputImage = ImageProcessor.mosaic(
            source,
            strokes: strokes,
            style: mosaicStyle,
            intensity: mosaicIntensity,
            brushSize: brushSize
        )
    }

    func previewStitch() {
        let color = NSColor(stitchBackground)
        outputImage = ImageProcessor.stitch(
            images.map(\.image),
            direction: stitchDirection,
            spacing: stitchSpacing,
            background: color
        )
    }

    func applyStitch() {
        guard images.count >= 2, let composite = outputImage else { return }
        let item = ImageItem(image: composite, name: "拼接图")
        images = [item]
        selectedID = item.id
        outputImage = composite
        targetWidth = composite.pixelSize.width
        targetHeight = composite.pixelSize.height
        strokes.removeAll()
        showsCropSelection = false
        history.removeAll()
        future.removeAll()
        updateUndoState()
    }

    func commitCurrent() {
        guard let outputImage, let index = images.firstIndex(where: { $0.id == selectedID }) else { return }
        history.append(images[index].image)
        future.removeAll()
        images[index].image = outputImage
        strokes.removeAll()
        updateUndoState()
    }

    func undo() {
        guard let previous = history.popLast(),
              let index = images.firstIndex(where: { $0.id == selectedID }) else { return }
        future.append(images[index].image)
        images[index].image = previous
        outputImage = previous
        updateUndoState()
    }

    func redo() {
        guard let next = future.popLast(),
              let index = images.firstIndex(where: { $0.id == selectedID }) else { return }
        history.append(images[index].image)
        images[index].image = next
        outputImage = next
        updateUndoState()
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
        try? data?.write(to: url)
    }

    private func exportBatchImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "选择导出文件夹"
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        for (index, item) in images.enumerated() {
            guard let cgImage = item.image.cgImageValue else { continue }
            let safeName = item.name.replacingOccurrences(of: "/", with: "-")
            let url = directory.appendingPathComponent("\(safeName)-处理后-\(index + 1).png")
            let representation = NSBitmapImageRep(cgImage: cgImage)
            try? representation.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}

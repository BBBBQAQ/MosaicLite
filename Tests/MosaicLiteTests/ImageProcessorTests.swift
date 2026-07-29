import AppKit
import Testing
@testable import MosaicLite

@Suite("图片处理核心能力", .serialized)
struct ImageProcessorTests {
    @Test("按像素调整尺寸")
    func resizeByPixels() throws {
        let source = makeImage(width: 80, height: 40, color: .systemBlue)
        let result = try #require(ImageProcessor.resize(source, width: 160, height: 80))
        #expect(result.pixelSize == CGSize(width: 160, height: 80))
    }

    @Test("横向拼接尺寸正确")
    func horizontalStitch() throws {
        let images = [
            makeImage(width: 30, height: 40, color: .systemRed),
            makeImage(width: 50, height: 20, color: .systemGreen)
        ]
        let result = try #require(
            ImageProcessor.stitch(images, direction: .horizontal, spacing: 10, background: .white)
        )
        #expect(result.pixelSize == CGSize(width: 90, height: 40))
    }

    @Test("纵向拼接尺寸正确")
    func verticalStitch() throws {
        let images = [
            makeImage(width: 30, height: 40, color: .systemRed),
            makeImage(width: 50, height: 20, color: .systemGreen)
        ]
        let result = try #require(
            ImageProcessor.stitch(images, direction: .vertical, spacing: 6, background: .white)
        )
        #expect(result.pixelSize == CGSize(width: 50, height: 66))
    }

    @Test("横向拼接图片不会互相覆盖")
    func stitchKeepsImagesSeparated() throws {
        let images = [
            makeImage(width: 10, height: 10, color: .systemRed),
            makeImage(width: 10, height: 10, color: .systemGreen)
        ]
        let result = try #require(
            ImageProcessor.stitch(images, direction: .horizontal, spacing: 3, background: .white)
        )
        let cgImage = try #require(result.cgImageValue)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let left = try #require(bitmap.colorAt(x: 8, y: 5))
        let gap = try #require(bitmap.colorAt(x: 11, y: 5))
        let right = try #require(bitmap.colorAt(x: 15, y: 5))

        #expect(left.redComponent > left.greenComponent)
        #expect(gap.redComponent > 0.9 && gap.greenComponent > 0.9)
        #expect(right.greenComponent > right.redComponent)
    }

    @Test("应用拼接后收束为一张工作图")
    @MainActor
    func applyingStitchCreatesSingleWorkingImage() {
        let model = EditorModel()
        model.images = [
            ImageItem(image: makeImage(width: 30, height: 20, color: .systemRed), name: "左图"),
            ImageItem(image: makeImage(width: 40, height: 20, color: .systemBlue), name: "右图")
        ]
        model.selectedID = model.images.first?.id
        model.stitchDirection = .horizontal
        model.stitchSpacing = 5
        model.previewStitch()

        model.applyStitch()

        #expect(model.images.count == 1)
        #expect(model.selectedImage?.pixelSize == CGSize(width: 75, height: 20))
        #expect(model.images.first?.name == "拼接图")
    }

    @Test("拖拽拼接图片会更新排列顺序")
    @MainActor
    func reorderingStitchImages() {
        let model = EditorModel()
        model.images = [
            ImageItem(image: makeImage(width: 10, height: 10, color: .systemRed), name: "A"),
            ImageItem(image: makeImage(width: 10, height: 10, color: .systemGreen), name: "B"),
            ImageItem(image: makeImage(width: 10, height: 10, color: .systemBlue), name: "C")
        ]
        let firstID = model.images[0].id
        let lastID = model.images[2].id

        model.reorderImage(from: firstID, onto: lastID)

        #expect(model.images.map(\.name) == ["B", "C", "A"])
    }

    @Test("批量尺寸按百分比处理所有图片")
    @MainActor
    func batchResizeProcessesEveryImage() {
        let model = EditorModel()
        model.images = [
            ImageItem(image: makeImage(width: 100, height: 80, color: .systemRed), name: "A"),
            ImageItem(image: makeImage(width: 60, height: 40, color: .systemBlue), name: "B")
        ]
        model.selectedID = model.images.first?.id
        model.resizeBatchMode = true
        model.resizeUnit = .percent
        model.percent = 50

        model.applyResize()

        #expect(model.images[0].image.pixelSize == CGSize(width: 50, height: 40))
        #expect(model.images[1].image.pixelSize == CGSize(width: 30, height: 20))
    }

    @Test("批量模式使用追加导入逻辑")
    @MainActor
    func batchModeUsesAddImportBehavior() {
        let model = EditorModel()
        model.tool = .resize
        model.resizeBatchMode = true
        #expect(model.contextualImportBehavior == .add)

        model.tool = .watermark
        model.watermarkBatchMode = true
        #expect(model.contextualImportBehavior == .add)
    }

    @Test("满图文字水印保持图片尺寸")
    func tiledTextWatermarkPreservesSize() throws {
        let source = makeImage(width: 180, height: 120, color: .systemIndigo)
        let result = try #require(
            ImageProcessor.textWatermark(
                source,
                text: "TEST",
                opacity: 0.3,
                fontSize: 24,
                spacing: 40,
                angle: -25
            )
        )
        #expect(result.pixelSize == source.pixelSize)
    }

    @Test("Logo 水印保持图片尺寸")
    func logoWatermarkPreservesSize() throws {
        let source = makeImage(width: 180, height: 120, color: .systemIndigo)
        let logo = makeImage(width: 40, height: 20, color: .white)
        let result = try #require(
            ImageProcessor.logoWatermark(
                source,
                logo: logo,
                opacity: 0.5,
                scale: 0.2,
                position: .bottomRight,
                padding: 12
            )
        )
        #expect(result.pixelSize == source.pixelSize)
    }

    @Test("清除 Logo 会恢复未选择状态")
    @MainActor
    func clearingWatermarkLogoResetsState() {
        let model = EditorModel()
        model.watermarkLogo = makeImage(width: 40, height: 20, color: .white)
        model.watermarkLogoName = "logo.png"

        model.clearWatermarkLogo()

        #expect(model.watermarkLogo == nil)
        #expect(model.watermarkLogoName == "尚未选择 Logo")
    }

    @Test("下居中 Logo 水印保持图片尺寸")
    func bottomCenterLogoWatermarkPreservesSize() throws {
        let source = makeImage(width: 180, height: 120, color: .systemIndigo)
        let logo = makeImage(width: 40, height: 20, color: .white)
        let result = try #require(
            ImageProcessor.logoWatermark(
                source,
                logo: logo,
                opacity: 0.6,
                scale: 0.2,
                position: .bottomCenter,
                padding: 10
            )
        )
        #expect(result.pixelSize == source.pixelSize)
    }

    @Test("马赛克保持原图尺寸")
    func mosaicPreservesDimensions() throws {
        let source = makeImage(width: 100, height: 60, color: .systemPurple)
        let stroke = MosaicStroke(
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 70, y: 45)],
            isRectangle: true
        )
        let result = try #require(
            ImageProcessor.mosaic(
                source,
                strokes: [stroke],
                style: .pixel,
                intensity: 12,
                brushSize: 20
            )
        )
        #expect(result.pixelSize == source.pixelSize)
    }

    @Test("柔和模糊会平滑颜色边界")
    func softBlurBlendsEdges() throws {
        let source = NSImage(size: NSSize(width: 100, height: 20))
        source.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 50, height: 20).fill()
        NSColor.systemBlue.setFill()
        NSRect(x: 50, y: 0, width: 50, height: 20).fill()
        source.unlockFocus()

        let result = try #require(
            ImageProcessor.mosaic(
                source,
                strokes: [
                    MosaicStroke(
                        points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 20)],
                        isRectangle: true
                    )
                ],
                style: .blur,
                intensity: 21,
                brushSize: 20
            )
        )
        let cgImage = try #require(result.cgImageValue)
        let boundaryColor = try #require(NSBitmapImageRep(cgImage: cgImage).colorAt(x: 49, y: 10))
        #expect(boundaryColor.redComponent > 0.1)
        #expect(boundaryColor.blueComponent > 0.1)
    }

    @Test("按拖动选区裁切")
    func cropByNormalizedSelection() throws {
        let source = makeImage(width: 200, height: 100, color: .systemOrange)
        let result = try #require(
            ImageProcessor.crop(
                source,
                normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6)
            )
        )
        #expect(result.pixelSize == CGSize(width: 100, height: 60))
    }

    @Test("应用裁切后隐藏裁切框")
    @MainActor
    func applyingCropClearsSelection() {
        let model = EditorModel()
        let source = makeImage(width: 200, height: 100, color: .systemOrange)
        let item = ImageItem(image: source, name: "裁切测试")
        model.images = [item]
        model.selectedID = item.id
        model.cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        model.showsCropSelection = true

        model.applyCrop()

        #expect(model.showsCropSelection == false)
        #expect(model.selectedImage?.pixelSize == CGSize(width: 160, height: 80))
    }

    private func makeImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }
}

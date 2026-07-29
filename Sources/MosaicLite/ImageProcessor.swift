import AppKit
import Accelerate

enum ImageProcessor {
    static func resize(_ image: NSImage, width: Int, height: Int) -> NSImage? {
        guard width > 0, height > 0, let source = image.cgImageValue else { return nil }
        let colorSpace = source.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else { return nil }
        return NSImage(cgImage: output, size: NSSize(width: width, height: height))
    }

    static func crop(_ image: NSImage, normalizedRect: CGRect) -> NSImage? {
        guard let source = image.cgImageValue else { return nil }
        let normalized = normalizedRect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard normalized.width > 0, normalized.height > 0 else { return nil }

        // 画布坐标从左上角开始，CGImage 裁切坐标从左下角开始。
        let pixelRect = CGRect(
            x: (normalized.minX * CGFloat(source.width)).rounded(),
            y: ((1 - normalized.maxY) * CGFloat(source.height)).rounded(),
            width: (normalized.width * CGFloat(source.width)).rounded(),
            height: (normalized.height * CGFloat(source.height)).rounded()
        )
        guard let cropped = source.cropping(to: pixelRect) else { return nil }
        return NSImage(
            cgImage: cropped,
            size: NSSize(width: cropped.width, height: cropped.height)
        )
    }

    static func textWatermark(
        _ image: NSImage,
        text: String,
        opacity: Double,
        fontSize: Double,
        spacing: Double,
        angle: Double
    ) -> NSImage? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let source = image.cgImageValue,
              let output = makeOutputContext(for: source)
        else { return image }

        let extent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        output.draw(source, in: extent)
        output.saveGState()
        output.translateBy(x: extent.midX, y: extent.midY)
        output.rotate(by: angle * .pi / 180)
        output.translateBy(x: -extent.midX, y: -extent.midY)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(10, fontSize), weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(min(max(opacity, 0.03), 1)),
            .strokeColor: NSColor.black.withAlphaComponent(min(max(opacity * 0.35, 0), 0.5)),
            .strokeWidth: -1.2
        ]
        let value = text as NSString
        let textSize = value.size(withAttributes: attributes)
        let stepX = max(textSize.width + CGFloat(spacing), 60)
        let stepY = max(textSize.height + CGFloat(spacing) * 0.55, 42)
        let diagonal = hypot(extent.width, extent.height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: output, flipped: false)
        var row = 0
        for y in stride(from: -diagonal, through: diagonal * 1.5, by: stepY) {
            let offset = row.isMultiple(of: 2) ? CGFloat.zero : stepX / 2
            for x in stride(from: -diagonal + offset, through: diagonal * 1.5, by: stepX) {
                value.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
            }
            row += 1
        }
        NSGraphicsContext.restoreGraphicsState()
        output.restoreGState()

        guard let result = output.makeImage() else { return nil }
        return NSImage(cgImage: result, size: image.size)
    }

    static func logoWatermark(
        _ image: NSImage,
        logo: NSImage,
        opacity: Double,
        scale: Double,
        position: WatermarkPosition,
        padding: Double
    ) -> NSImage? {
        guard let source = image.cgImageValue,
              let logoSource = logo.cgImageValue,
              let output = makeOutputContext(for: source)
        else { return nil }

        let extent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        output.draw(source, in: extent)
        let targetWidth = max(16, CGFloat(source.width) * min(max(scale, 0.03), 0.8))
        let targetHeight = targetWidth * CGFloat(logoSource.height) / CGFloat(max(1, logoSource.width))
        let inset = CGFloat(max(0, padding))
        let origin: CGPoint
        switch position {
        case .topLeft:
            origin = CGPoint(x: inset, y: extent.height - targetHeight - inset)
        case .topRight:
            origin = CGPoint(x: extent.width - targetWidth - inset, y: extent.height - targetHeight - inset)
        case .center:
            origin = CGPoint(x: (extent.width - targetWidth) / 2, y: (extent.height - targetHeight) / 2)
        case .bottomLeft:
            origin = CGPoint(x: inset, y: inset)
        case .bottomCenter:
            origin = CGPoint(x: (extent.width - targetWidth) / 2, y: inset)
        case .bottomRight:
            origin = CGPoint(x: extent.width - targetWidth - inset, y: inset)
        }
        output.saveGState()
        output.setAlpha(min(max(opacity, 0.03), 1))
        output.interpolationQuality = .high
        output.draw(logoSource, in: CGRect(origin: origin, size: CGSize(width: targetWidth, height: targetHeight)))
        output.restoreGState()

        guard let result = output.makeImage() else { return nil }
        return NSImage(cgImage: result, size: image.size)
    }

    private static func makeOutputContext(for source: CGImage) -> CGContext? {
        CGContext(
            data: nil,
            width: source.width,
            height: source.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    static func mosaic(
        _ image: NSImage,
        strokes: [MosaicStroke],
        style: MosaicStyle,
        intensity: Double,
        brushSize: Double
    ) -> NSImage? {
        guard let source = image.cgImageValue, !strokes.isEmpty else { return image }
        let extent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        guard let filteredCG = stylizedImage(source, style: style, intensity: intensity) else { return nil }
        let colorSpace = source.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let output = CGContext(
            data: nil,
            width: source.width,
            height: source.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        output.draw(source, in: extent)
        output.saveGState()
        let maskPath = CGMutablePath()
        for stroke in strokes where !stroke.points.isEmpty {
            if stroke.isRectangle, let first = stroke.points.first, let last = stroke.points.last {
                maskPath.addRect(CGRect(
                    x: min(first.x, last.x),
                    y: min(first.y, last.y),
                    width: abs(last.x - first.x),
                    height: abs(last.y - first.y)
                ))
            } else {
                let line = CGMutablePath()
                line.move(to: stroke.points[0])
                for point in stroke.points.dropFirst() { line.addLine(to: point) }
                maskPath.addPath(line.copy(strokingWithWidth: brushSize, lineCap: .round, lineJoin: .round, miterLimit: 1))
            }
        }
        output.addPath(maskPath)
        output.clip()
        output.draw(filteredCG, in: extent)
        output.restoreGState()

        guard let result = output.makeImage() else { return nil }
        return NSImage(cgImage: result, size: image.size)
    }

    private static func stylizedImage(
        _ source: CGImage,
        style: MosaicStyle,
        intensity: Double
    ) -> CGImage? {
        if style == .blur {
            return smoothBlur(source, radius: intensity)
        }

        let block = max(3, Int(intensity))
        let sampleWidth = max(1, Int(ceil(Double(source.width) / Double(block))))
        let sampleHeight = max(1, Int(ceil(Double(source.height) / Double(block))))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let rowBytes = sampleWidth * 4
        var pixels = [UInt8](repeating: 0, count: sampleHeight * rowBytes)

        let sample = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let sampleContext = CGContext(
                data: buffer.baseAddress,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: rowBytes,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            sampleContext.interpolationQuality = .medium
            sampleContext.draw(source, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
            return sampleContext.makeImage()
        }
        guard let sample,
              let output = CGContext(
                data: nil,
                width: source.width,
                height: source.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        let fullRect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        switch style {
        case .pixel:
            output.interpolationQuality = .none
            output.draw(sample, in: fullRect)
        case .blur:
            break
        case .crystal:
            output.setFillColor(NSColor.black.cgColor)
            output.fill(fullRect)
            let cellWidth = CGFloat(source.width) / CGFloat(sampleWidth)
            let cellHeight = CGFloat(source.height) / CGFloat(sampleHeight)
            pixels.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for row in 0..<sampleHeight {
                    for column in 0..<sampleWidth {
                        let index = row * rowBytes + column * 4
                        let color = CGColor(
                            colorSpace: colorSpace,
                            components: [
                                CGFloat(base[index]) / 255,
                                CGFloat(base[index + 1]) / 255,
                                CGFloat(base[index + 2]) / 255,
                                CGFloat(base[index + 3]) / 255
                            ]
                        ) ?? NSColor.gray.cgColor
                        let center = CGPoint(
                            x: (CGFloat(column) + 0.5) * cellWidth,
                            y: (CGFloat(row) + 0.5) * cellHeight
                        )
                        let diamond = CGMutablePath()
                        diamond.move(to: CGPoint(x: center.x, y: center.y - cellHeight * 0.72))
                        diamond.addLine(to: CGPoint(x: center.x + cellWidth * 0.72, y: center.y))
                        diamond.addLine(to: CGPoint(x: center.x, y: center.y + cellHeight * 0.72))
                        diamond.addLine(to: CGPoint(x: center.x - cellWidth * 0.72, y: center.y))
                        diamond.closeSubpath()
                        output.addPath(diamond)
                        output.setFillColor(color)
                        output.fillPath()
                    }
                }
            }
        }
        return output.makeImage()
    }

    private static func smoothBlur(_ source: CGImage, radius: Double) -> CGImage? {
        let width = source.width
        let height = source.height
        let rowBytes = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var inputPixels = [UInt8](repeating: 0, count: height * rowBytes)
        var outputPixels = [UInt8](repeating: 0, count: height * rowBytes)

        let didDraw = inputPixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: rowBytes,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }

        var kernel = max(3, min(101, Int(radius.rounded())))
        if kernel.isMultiple(of: 2) { kernel += 1 }
        let error = inputPixels.withUnsafeMutableBytes { inputBuffer in
            outputPixels.withUnsafeMutableBytes { outputBuffer in
                var sourceBuffer = vImage_Buffer(
                    data: inputBuffer.baseAddress!,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: rowBytes
                )
                var destinationBuffer = vImage_Buffer(
                    data: outputBuffer.baseAddress!,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: rowBytes
                )
                return vImageTentConvolve_ARGB8888(
                    &sourceBuffer,
                    &destinationBuffer,
                    nil,
                    0,
                    0,
                    UInt32(kernel),
                    UInt32(kernel),
                    nil,
                    vImage_Flags(kvImageEdgeExtend)
                )
            }
        }
        guard error == kvImageNoError else { return nil }

        let data = Data(outputPixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: rowBytes,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    static func stitch(
        _ images: [NSImage],
        direction: StitchDirection,
        spacing: CGFloat,
        background: NSColor
    ) -> NSImage? {
        let cgImages = images.compactMap(\.cgImageValue)
        guard !cgImages.isEmpty else { return nil }

        // 所有位置使用整数像素，避免连续导入不同尺寸图片时因小数取整产生覆盖。
        let gap = max(0, Int(spacing.rounded()))
        let width = direction == .horizontal
            ? cgImages.reduce(0) { $0 + $1.width } + gap * max(0, cgImages.count - 1)
            : cgImages.map(\.width).max()!
        let height = direction == .vertical
            ? cgImages.reduce(0) { $0 + $1.height } + gap * max(0, cgImages.count - 1)
            : cgImages.map(\.height).max()!

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        var offset = 0
        for image in cgImages {
            let origin: CGPoint
            if direction == .horizontal {
                origin = CGPoint(x: CGFloat(offset), y: CGFloat((height - image.height) / 2))
                offset += image.width + gap
            } else {
                origin = CGPoint(
                    x: CGFloat((width - image.width) / 2),
                    y: CGFloat(height - offset - image.height)
                )
                offset += image.height + gap
            }
            context.draw(
                image,
                in: CGRect(
                    origin: origin,
                    size: CGSize(width: image.width, height: image.height)
                )
            )
        }
        guard let result = context.makeImage() else { return nil }
        return NSImage(cgImage: result, size: NSSize(width: CGFloat(width), height: CGFloat(height)))
    }
}

extension NSImage {
    var cgImageValue: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    var pixelSize: CGSize {
        guard let cgImageValue else { return size }
        return CGSize(width: cgImageValue.width, height: cgImageValue.height)
    }
}

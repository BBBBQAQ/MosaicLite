import AppKit
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case resize = "尺寸"
    case crop = "裁切"
    case mosaic = "打码"
    case watermark = "水印"
    case stitch = "拼接"

    var id: String { rawValue }
    var localizedName: String { rawValue.localized }

    var icon: String {
        switch self {
        case .resize: "arrow.up.left.and.arrow.down.right"
        case .crop: "crop"
        case .mosaic: "square.grid.3x3.fill"
        case .watermark: "signature"
        case .stitch: "rectangle.3.group"
        }
    }
}

enum ResizeUnit: String, CaseIterable, Identifiable, Sendable {
    case pixels = "像素"
    case percent = "百分比"
    var id: String { rawValue }
    var localizedName: String { rawValue.localized }
}

enum CropRatioPreset: String, CaseIterable, Identifiable, Sendable {
    case free = "自由"
    case original = "原始"
    case square = "1:1"
    case fourThree = "4:3"
    case threeFour = "3:4"
    case sixteenNine = "16:9"
    case nineSixteen = "9:16"
    case custom = "自定义"

    var id: String { rawValue }
    var localizedName: String { rawValue.localized }

    func aspectRatio(sourceSize: CGSize, customWidth: Double, customHeight: Double) -> CGFloat? {
        switch self {
        case .free:
            nil
        case .original:
            sourceSize.height > 0 ? sourceSize.width / sourceSize.height : nil
        case .square:
            1
        case .fourThree:
            4 / 3
        case .threeFour:
            3 / 4
        case .sixteenNine:
            16 / 9
        case .nineSixteen:
            9 / 16
        case .custom:
            customWidth > 0 && customHeight > 0 ? customWidth / customHeight : nil
        }
    }
}

enum CropGeometry {
    static func maximumCenteredRect(normalizedAspectRatio ratio: CGFloat) -> CGRect {
        guard ratio.isFinite, ratio > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        if ratio >= 1 {
            let height = 1 / ratio
            return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        }
        let width = ratio
        return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
    }
}

enum MosaicStyle: String, CaseIterable, Identifiable, Sendable {
    case pixel = "经典像素"
    case crystal = "晶格"
    case blur = "柔和模糊"
    var id: String { rawValue }
    var localizedName: String { rawValue.localized }
}

enum MosaicBrush: String, CaseIterable, Identifiable, Sendable {
    case rectangle = "框选"
    case freehand = "手涂"
    var id: String { rawValue }
    var localizedName: String { rawValue.localized }

    var icon: String {
        self == .rectangle ? "rectangle.dashed" : "scribble"
    }
}

enum StitchDirection: String, CaseIterable, Identifiable, Sendable {
    case horizontal = "横向"
    case vertical = "纵向"
    var id: String { rawValue }
    var localizedName: String { rawValue.localized }
}

enum ImageImportBehavior: Equatable {
    case replace
    case add
}

enum WatermarkKind: String, CaseIterable, Identifiable, Sendable {
    case text = "满图文字"
    case logo = "自定义 Logo"
    var id: String { rawValue }
    var localizedName: String { rawValue.localized }
}

enum WatermarkPosition: String, CaseIterable, Identifiable, Sendable {
    case topLeft = "左上"
    case topRight = "右上"
    case center = "居中"
    case bottomLeft = "左下"
    case bottomCenter = "下居中"
    case bottomRight = "右下"
    var id: String { rawValue }
    var localizedName: String { rawValue.localized }
}

struct ImageItem: Identifiable {
    let id = UUID()
    var image: NSImage
    var name: String
}

struct MosaicStroke: Identifiable, Sendable {
    let id = UUID()
    var points: [CGPoint]
    var isRectangle: Bool
}

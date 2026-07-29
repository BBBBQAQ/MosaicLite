import SwiftUI

struct InspectorPanel: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        ScrollView {
            controls
                .id(model.tool)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
            .padding(20)
        }
        .background(.thinMaterial)
        .animation(.snappy(duration: 0.34, extraBounce: 0.04), value: model.tool)
    }

    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch model.tool {
            case .resize: ResizeControls()
            case .crop: CropControls()
            case .mosaic: MosaicControls()
            case .watermark: WatermarkControls()
            case .stitch: StitchControls()
            }
        }
    }
}

private struct ResizeControls: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        Group {
            PanelHeader(title: "调整尺寸", subtitle: "高质量等比例缩放")

            Toggle("批量处理", isOn: $model.resizeBatchMode)

            if model.resizeBatchMode {
                BatchImageList(title: "待处理图片")
            }

            Picker("单位", selection: $model.resizeUnit) {
                ForEach(ResizeUnit.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.resizeUnit) { _, _ in model.previewResize() }

            if model.resizeUnit == .pixels {
                VStack(spacing: 12) {
                    NumberField(
                        title: "宽度",
                        value: Binding(
                            get: { model.targetWidth },
                            set: { model.updateWidth($0) }
                        ),
                        suffix: "px"
                    )
                    NumberField(
                        title: "高度",
                        value: Binding(
                            get: { model.targetHeight },
                            set: { model.updateHeight($0) }
                        ),
                        suffix: "px"
                    )
                }

                Toggle(isOn: $model.lockAspect) {
                    Label("锁定宽高比", systemImage: model.lockAspect ? "link" : "link.badge.plus")
                }
            } else {
                NumberField(
                    title: "缩放比例",
                    value: Binding(
                        get: { model.percent },
                        set: {
                            model.percent = min(max($0, 1), 1000)
                            model.previewResize()
                        }
                    ),
                    suffix: "%"
                )
                Text("输入 1–1000 之间的百分比")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            InfoCard(
                icon: "photo",
                text: "\(Int(model.sourcePixelSize.width)) × \(Int(model.sourcePixelSize.height)) px"
            )

            PrimaryAction(
                title: model.resizeBatchMode ? "批量应用尺寸" : "应用尺寸",
                icon: "checkmark"
            ) {
                model.applyResize()
            }
            .disabled(model.selectedImage == nil)
        }
    }
}

private struct CropControls: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        Group {
            PanelHeader(title: "自由裁切", subtitle: "在图片上点击或拖拽即可开始")

            InfoCard(
                icon: "crop",
                text: model.showsCropSelection
                    ? "\(cropWidth) × \(cropHeight) px"
                    : "点击图片创建裁切区域"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("操作提示")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label("点击图片默认框选整张图片", systemImage: "cursorarrow.click")
                Label("在图片上拖拽可直接框选", systemImage: "rectangle.dashed")
                Label("拖动选区内部可移动裁切区域", systemImage: "hand.draw")
                Label("拖动四条边或四角调整范围", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .font(.subheadline)

            PrimaryAction(title: "应用裁切", icon: "crop") {
                model.applyCrop()
            }
            .disabled(model.selectedImage == nil || !model.showsCropSelection)
        }
    }

    private var cropWidth: Int {
        model.showsCropSelection ? Int(model.sourcePixelSize.width * model.cropRect.width) : 0
    }

    private var cropHeight: Int {
        model.showsCropSelection ? Int(model.sourcePixelSize.height * model.cropRect.height) : 0
    }
}

private struct MosaicControls: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        Group {
            PanelHeader(title: "隐私打码", subtitle: "框选区域或直接涂抹")

            Picker("方式", selection: $model.mosaicBrush) {
                ForEach(MosaicBrush.allCases) {
                    Label($0.rawValue, systemImage: $0.icon).tag($0)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text("马赛克风格").font(.subheadline).foregroundStyle(.secondary)
                ForEach(MosaicStyle.allCases) { style in
                    Button {
                        model.mosaicStyle = style
                        model.previewMosaic()
                    } label: {
                        HStack {
                            MosaicSwatch(style: style)
                            Text(style.rawValue)
                            Spacer()
                            if model.mosaicStyle == style {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(model.mosaicStyle == style ? Color.accentColor.opacity(0.1) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            LabeledSlider(title: "强度", value: $model.mosaicIntensity, range: 5...60)
                .onChange(of: model.mosaicIntensity) { _, _ in model.previewMosaic() }

            if model.mosaicBrush == .freehand {
                LabeledSlider(title: "笔刷大小", value: $model.brushSize, range: 12...160)
            }

            HStack {
                Button("清除选区") {
                    model.strokes.removeAll()
                    model.previewMosaic()
                }
                .disabled(model.strokes.isEmpty)
                Spacer()
                Text("\(model.strokes.count) 个区域")
                    .foregroundStyle(.secondary)
            }

            PrimaryAction(title: "应用打码", icon: "checkmark.shield") {
                model.commitCurrent()
            }
            .disabled(model.strokes.isEmpty)
        }
    }
}

private struct WatermarkControls: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        Group {
            PanelHeader(title: "添加水印", subtitle: "文字满图或自定义 Logo")

            Toggle("批量处理", isOn: $model.watermarkBatchMode)

            if model.watermarkBatchMode {
                BatchImageList(title: "待处理图片")
            }

            Picker("类型", selection: $model.watermarkKind) {
                ForEach(WatermarkKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.watermarkKind) { _, _ in model.previewWatermark() }

            if model.watermarkKind == .text {
                VStack(alignment: .leading, spacing: 8) {
                    Text("水印文字").font(.subheadline).foregroundStyle(.secondary)
                    TextField("输入水印文字", text: $model.watermarkText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.watermarkText) { _, _ in model.previewWatermark() }
                }

                LabeledSlider(title: "文字大小", value: $model.watermarkFontSize, range: 12...120, suffix: " px")
                    .onChange(of: model.watermarkFontSize) { _, _ in model.previewWatermark() }
                LabeledSlider(title: "水印间距", value: $model.watermarkSpacing, range: 30...260, suffix: " px")
                    .onChange(of: model.watermarkSpacing) { _, _ in model.previewWatermark() }
                LabeledSlider(title: "倾斜角度", value: $model.watermarkAngle, range: -60...60, suffix: "°")
                    .onChange(of: model.watermarkAngle) { _, _ in model.previewWatermark() }
            } else {
                HStack(spacing: 8) {
                    Button {
                        model.selectWatermarkLogo()
                    } label: {
                        HStack {
                            Image(systemName: "photo.badge.plus")
                            Text(model.watermarkLogoName).lineLimit(1)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if model.watermarkLogo != nil {
                        Button {
                            model.clearWatermarkLogo()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .help("清除 Logo")
                    }
                }

                Picker("位置", selection: $model.watermarkPosition) {
                    ForEach(WatermarkPosition.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: model.watermarkPosition) { _, _ in model.previewWatermark() }

                LabeledSlider(
                    title: "Logo 大小",
                    value: Binding(
                        get: { model.watermarkLogoScale * 100 },
                        set: { model.watermarkLogoScale = $0 / 100 }
                    ),
                    range: 5...50,
                    suffix: "%"
                )
                .onChange(of: model.watermarkLogoScale) { _, _ in model.previewWatermark() }
                LabeledSlider(title: "边缘距离", value: $model.watermarkPadding, range: 0...160, suffix: " px")
                    .onChange(of: model.watermarkPadding) { _, _ in model.previewWatermark() }
            }

            LabeledSlider(
                title: "不透明度",
                value: Binding(
                    get: { model.watermarkOpacity * 100 },
                    set: { model.watermarkOpacity = $0 / 100 }
                ),
                range: 5...100,
                suffix: "%"
            )
            .onChange(of: model.watermarkOpacity) { _, _ in model.previewWatermark() }

            InfoCard(
                icon: "square.and.arrow.up",
                text: model.watermarkBatchMode && model.images.count > 1
                    ? "右上角导出将保存全部 \(model.images.count) 张图片"
                    : "应用后可从右上角导出"
            )

            PrimaryAction(
                title: model.watermarkBatchMode ? "批量应用水印" : "应用水印",
                icon: "signature"
            ) {
                model.applyWatermark()
            }
            .disabled(
                model.selectedImage == nil
                || (model.watermarkKind == .logo && model.watermarkLogo == nil)
            )
        }
    }
}

private struct BatchImageList: View {
    @EnvironmentObject private var model: EditorModel
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.images.count) 张").foregroundStyle(.tertiary)
                Button { model.requestImport(.add) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("添加图片")
            }

            ForEach(model.images) { item in
                HStack(spacing: 8) {
                    Button {
                        model.select(item)
                    } label: {
                        HStack(spacing: 8) {
                        Image(nsImage: item.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(item.name).lineLimit(1)
                        Spacer()
                        if model.selectedID == item.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        }
                        }
                    }
                    .buttonStyle(.plain)
                    Button { model.remove(item) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(model.selectedID == item.id ? Color.accentColor.opacity(0.09) : .clear)
                )
            }
        }
    }
}

private struct StitchControls: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        Group {
            PanelHeader(title: "图片拼接", subtitle: "拖动列表调整顺序，再合并为一张工作图")

            Picker("方向", selection: $model.stitchDirection) {
                ForEach(StitchDirection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.stitchDirection) { _, _ in model.previewStitch() }

            LabeledSlider(title: "图片间距", value: $model.stitchSpacing, range: 0...80, suffix: " px")
                .onChange(of: model.stitchSpacing) { _, _ in model.previewStitch() }

            ColorPicker("背景颜色", selection: $model.stitchBackground, supportsOpacity: true)
                .onChange(of: model.stitchBackground) { _, _ in model.previewStitch() }

            Divider()

            HStack {
                Text("图片列表").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.requestImport(.add)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }

            ForEach(model.images) { item in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                        .help("拖动调整顺序")
                    Image(nsImage: item.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text(item.name).lineLimit(1)
                    Spacer()
                    Button { model.remove(item) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .draggable(item.id.uuidString)
                .dropDestination(for: String.self) { identifiers, _ in
                    guard let value = identifiers.first,
                          let draggedID = UUID(uuidString: value)
                    else { return false }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0.03)) {
                        model.reorderImage(from: draggedID, onto: item.id)
                    }
                    return true
                }
            }

            InfoCard(
                icon: "arrow.triangle.branch",
                text: "应用后多张图片会合并为一张，可继续尺寸、裁切和打码"
            )

            PrimaryAction(title: "应用拼接", icon: "checkmark") {
                model.applyStitch()
            }
            .disabled(model.images.count < 2)
        }
    }
}

private struct PanelHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct NumberField: View {
    let title: String
    @Binding var value: Double
    let suffix: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            TextField("", value: $value, format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .frame(width: 90)
            Text(suffix).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 9).fill(.background.opacity(0.65)))
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var suffix = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value))\(suffix)").foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}

private struct InfoCard: View {
    let icon: String
    let text: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(.quaternary.opacity(0.4)))
    }
}

private struct PrimaryAction: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

private struct MosaicSwatch: View {
    let style: MosaicStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.6)
                }

            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.monochrome)
                .blur(radius: style == .blur ? 0.7 : 0)
        }
        .frame(width: 32, height: 26)
    }

    private var symbolName: String {
        switch style {
        case .pixel: "square.grid.3x3.fill"
        case .crystal: "diamond.fill"
        case .blur: "circle.dotted"
        }
    }
}

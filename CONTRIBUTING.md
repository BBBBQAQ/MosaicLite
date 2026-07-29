# 为 MosaicLite 做贡献

感谢你愿意参与 MosaicLite。

## 开发环境

- macOS 15 或更高版本
- Xcode 16 或更高版本
- Swift 6

克隆项目后，可直接使用 Xcode 打开 `Package.swift`。提交修改前请运行：

```bash
swift test
./scripts/build-app.sh
```

## 提交建议

- 一个提交集中解决一个问题。
- 新功能或图片处理逻辑变更应尽量补充测试。
- UI 修改请同时检查浅色、深色模式以及窗口缩放状态。
- 请勿提交 `.build`、`work`、`outputs` 或其他本机构建文件。

提交 Issue 时，请附上 macOS 版本、操作步骤、预期结果和实际结果；界面问题建议附截图。


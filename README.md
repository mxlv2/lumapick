# 留影 · LumaPick

轻盈的 macOS 原生照片选片器：从一整次拍摄，到值得精修的几张。

原生 macOS 照片选片工具。支持 macOS 14+，当前打包产物面向 Apple Silicon。

## 主要功能

- 本地文件夹浏览、图片格式筛选与 RAW/JPEG 配对。
- 不限轮次的保留筛选、轮次恢复与撤销。
- 多图隔离、双图对比、联动缩放及固定参考图。
- 自动保存当前任务，批量命名并复制原文件到新目录。
- SwiftUI + AppKit + ImageIO/Core Image，无第三方运行时依赖。

## 下载安装

在 [GitHub Releases](https://github.com/mxlv2/lumapick/releases/latest) 下载 `LumaPick-1.0.0-macOS-arm64.dmg`，打开后将「留影」拖入 Applications。也提供 ZIP 便携包与 SHA-256 校验文件。适用于 macOS 14+、Apple Silicon（M 系列）；当前不提供 Intel 安装包。

应用尚未进行 Developer ID 签名和 Apple 公证。首次打开可能被系统拦截；确认来自本仓库后，按 [Apple 官方说明](https://support.apple.com/102445) 在「系统设置 → 隐私与安全性」中选择「仍要打开」。

## 预览与界面

- 按 Retina 显示尺寸生成缩略图；内嵌预览像素不足时生成更清晰的版本。
- 渐进预览、相邻照片预加载；网格和大图使用独立解码队列，重复请求合并。
- 内存缓存与最多约 256 MB 的本地缩略图磁盘缓存；照片文件变化后重新生成。
- 100% 按原图像素与显示器比例显示，升级清晰度时保留已有画面；未获得原尺寸时明确提示。
- 轻盈侧栏、格式胶囊、窗口内对比，支持拖动、双击定位与捏合缩放。动效遵循系统「减少动态效果」。

预览缓存位于 `~/Library/Caches/LumaPick/Previews`，可删除后自动重建。RAW 的首次解码速度仍取决于文件大小、压缩方式、磁盘与系统支持。

## 从源码运行

需要 macOS 14 或更新版本，以及 Swift 6.0+ 工具链（Xcode 或 Command Line Tools）。

```sh
git clone https://github.com/mxlv2/lumapick.git
cd lumapick
./scripts/build-app.sh
open dist/留影.app
```

## 使用

运行 `dist/留影.app`，或执行 `./scripts/build-app.sh` 重新打包。本地使用的应用采用 ad-hoc 签名，尚未做 Developer ID 签名和公证。

1. 选择或拖入照片文件夹，可包含子文件夹。
2. 点选照片浏览；Command 多选、Shift 范围选择、⌘A 全选。卡片右上角圆圈标记保留。`P` 保留，`U` 取消保留，空格查看大图。
3. 多选后进入隔离选片，组内标记同步当前轮。多图对比中选择两张检查细节。双图可联动平移、切换适应/100%，固定左图并连续切换右图。
4. 点击进入下一轮，只有已保留照片进入下一轮，新轮标记从空开始。轮次历史可恢复旧轮，⌘Z 撤销。
5. 任意轮点击命名并导出，预览全部名称，再选择目标父文件夹。导出成功才完成任务。

格式筛选只影响显示；推进和导出始终使用全轮保留集合。RAW+JPEG 仅在同目录、同主文件名且配对无歧义时合并。配对文件共用编号；配对导出选项不改变独立单文件照片的格式。

输出示例：`嘉定湖 精选/嘉定湖 1.ARW`。同名目录自动递增。原文件不修改、不删除；导出失败或取消只清理本次创建的临时目录。

当前任务自动保存到 `~/Library/Application Support/XuanPian/session.json`，重启恢复。打开另一文件夹会开始新任务，替换自动保存记录。存储卡路径变化时使用工具栏的“重新定位来源”。

## 开发与验证

```sh
./scripts/test.sh
./scripts/build-app.sh
```

脚本为当前 Command Line Tools 补充 Swift Testing 插件路径，并使用工作区构建缓存。`ViewState` 是系统 `SwiftUI.State` 属性包装器的别名，用于避开当前 SDK 中同名宏的插件依赖。Release 构建关闭调试符号，以便在受限环境中打包。

测试覆盖多轮筛选、配对与递归、中文编号、文件内容一致性、目录冲突、失败/取消清理、会话编码，以及 3000 文件扫描、预览分辨率、EXIF 旋转、请求合并、缓存命中/失效与取消加载。实际窗口已验证打开、两轮筛选、中文命名、成功导出、重启恢复与双图预览；导出样本已核对 SHA-1 与源文件一致。

## 格式验证范围

图片读取使用 ImageIO/Core Image，RAW 兼容性取决于运行系统的解码支持。无法预览的文件保留在列表并明确提示。预览不用于转码导出。

A7C II ARW、Z6 II NEF、Action 3 RAW、iPhone 15 Pro ProRAW/HEIC 的实际拍摄样片尚未提供，相关压缩方式、色彩和焦点细节需实机验收。3000 文件测试验证目录扫描和排序，不能替代大量真实 RAW 的解码/内存压力测试。

## 贡献

欢迎通过 Issues 报告问题或提交 Pull Request。报告图片兼容问题时请提供 macOS 版本、相机型号、文件格式和压缩方式；只有在拥有分享权限时才上传样片。

修改后请运行 `./scripts/test.sh`，并使用 `./scripts/build-app.sh` 验证打包。源码仓库不包含照片、会话记录、构建缓存或本地应用包。

## 许可证

[MIT](LICENSE) © 2026 mxlv2

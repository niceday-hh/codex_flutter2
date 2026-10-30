# 公有仓库 APK 构建恢复验证

2026-10-19 实际确认 `niceday-hh/codex_flutter2` 为公有仓库，GitHub API 返回 `private: false`、`visibility: public`。

## 本次新运行

- 工作流：[Public repository APK build check / 39252580940](https://github.com/niceday-hh/codex_flutter2/actions/runs/39252580940)，第 1 次运行，结果 success。
- 执行器：GitHub 标准 `ubuntu-24.04`，新分配 runner ID 1000000233。
- 时间：2026-10-19 20:30:25 至 20:36:58（北京时间），约 6 分 33 秒。
- 源码提交：`900212aff4825e66ec1b65e1438bba5f197b6321`，基于 main 的 `3dbb07bf0237d9643c5463c8c4bf2bf9041748d4`，只增加独立验证工作流。
- 应用版本：`0.9.1+12`，应用功能源码未改变。
- 工具链：Flutter 3.35.7 / Dart 3.9.2、Java 17，沿用原 Android 包装工程与模型准备脚本。

本次新运行完成源码检出、Java/Flutter 安装、最小 Dart 实际执行、固定版本项目依赖和模型准备、arm64 Debug APK 编译、APK 必需资源及 ZIP 完整性检查，并成功上传构建产物。不是复用 10 月 17 日的编译结果。

## APK 收据

| 项目 | 值 |
| --- | --- |
| APK 文件 | `app-debug.apk` |
| APK 大小 | 411,330,784 字节，约 392.28 MiB |
| APK SHA-256 | `f3141d8c7279211f6565e71c9d37eb070e47545dd13a0e37a61d7aa30d8cbbbe` |
| 架构 / 构建类型 | arm64-v8a / Debug |
| 签名 | 调试签名，未使用固定发布签名 |
| Actions 产物 | `public-check-debug-arm64`，ID `12186700568` |
| 产物内容 | APK 与 `PUBLIC_BUILD_INFO.json` |
| 产物保留 | 3 天，至 2026-10-22 20:36 左右（北京时间） |

[下载 Actions 产物](https://github.com/niceday-hh/codex_flutter2/actions/runs/39252580940/artifacts/12186700568)，或进入本次运行页面底部 Artifacts 下载 `public-check-debug-arm64`。产物外层 ZIP 的摘要与 APK 摘要不同，应以解压后的 APK 对照上表。

归档检查确认 `lib/arm64-v8a/libflutter.so`、ASR 模型与 tokens、Silero VAD 和 TTS manifest 存在，ZIP CRC 检查通过。

## 验证范围

本次验证了当前公有仓库能实际编译并上传 APK。未运行完整 Flutter/原生单元测试或设备回归，没有启动模拟器、没有发布 Release，也不以 KVM 或固定发布签名作为 Debug 编译条件。调试 APK 不是正式升级包。

独立工作流只读仓库，push 触发限定于验证分支 `build-check/public-actions-20261019`，另提供 `workflow_dispatch`。正常新版本正式发布仍应保留原有完整检查及固定签名流程。

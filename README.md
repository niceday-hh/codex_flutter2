# 定时备忘录

根据六屏 UI 概念设计实现的 Flutter Android 定时备忘录，面向荣耀100等 arm64 手机。源码、云端构建和 APK 版本发布均在本仓库。

## 下载

从 [Releases](https://github.com/niceday-hh/codex_flutter2/releases) 下载 APK；每版附中文说明、SHA-256 校验和构建信息。首版为体验版，不宣称已通过荣耀100真机验证。

## 功能

- 备忘录、日历、语音、设置四个页面；中文、紫色简约主题。
- 日期时间、仅一次、每天、每周选定星期。
- 离线中文 Paraformer int8 语音输入；识别后确认日期和内容再保存。
- 锁屏通知隐藏正文，使用系统小型通知，不展示全屏提醒。
- 默认5分钟后重提醒，总共3次（含首次），可逐条调整。手动划掉通知／App 中滑动确认停止本周期剩余重提醒。
- 系统铃声选择、振动预设、可选亮屏。
- 原生 AlarmManager、BroadcastReceiver、SharedPreferences 持久化，独立于 Flutter 生命周期。
- 本地保存，无服务器、无账户、无网络权限，录音识别后清理。

## 工程结构

| 路径 | 内容 |
| --- | --- |
| `lib/main.dart` | Flutter 页面、编辑和权限引导 |
| `lib/reminder.dart` | 数据模型与原生桥接 |
| `lib/asr.dart` | Sherpa ONNX 离线识别，后台 isolate |
| `lib/voice_parser.dart` | 中文时间规则解析 |
| `native/` | Android 原生实现与 Gradle 覆盖配置 |
| `tool/bootstrap.sh` | 用固定 Flutter 版本生成标准 Android 平台壳并合并原生实现 |
| `tool/fetch_model.py` | 校验固定 SHA-256 后准备模型 |
| `test/`、`tool/ScheduleTest.java` | 页面、解析、日期和重提醒测试 |
| `.github/workflows/android.yml` | 静态检查、测试、云构建、APK 校验与 Release |

## 本地构建

安装 Flutter **3.35.7**、JDK **17** 和 Android SDK，然后执行：

```bash
bash tool/bootstrap.sh
flutter analyze
flutter test
mkdir -p tool/out
javac -d tool/out native/app/src/main/java/com/niceday/memo/Schedule.java tool/ScheduleTest.java
java -cp tool/out ScheduleTest
python3 tool/fetch_model.py
flutter build apk --release --target-platform android-arm64
```

生成的 `android/` 是标准平台包装；可重复使用 `bootstrap.sh` 合并 `native/` 的源码。修改安卓功能请改 `native/`。模型不进入 Git 历史，通过官方 Release 下载；已安装 APK 内置模型，运行时不联网。

## 云端构建与签名

推送 `main` 自动执行 GitHub Actions。全部验证和 APK 构建成功后，若 `.release-version` 指定的版本尚不存在，则发布体验版 Release；已有版本不会被覆盖。

发布新版本时须同步更新 `pubspec.yaml`、`.release-version`、页面版本、工作流产物名称／构建信息及相应版本说明。首版工作流明确固定为 v0.1.0。

若要使用固定正式签名，在仓库 Actions Secrets 配置：`ANDROID_KEYSTORE_BASE64`、`ANDROID_STORE_PASSWORD`、`ANDROID_KEY_PASSWORD`、`ANDROID_KEY_ALIAS`。无签名 Secrets 时使用 CI 测试签名，并在 Release 说明中标注；测试签名不能保证后续版本可覆盖升级。私钥和密码不进入源码、日志或发布附件。

## 提醒与隐私行为

“读取”以用户确认操作为准，不尝试推测眼睛是否看到内容。Android 通知 `deleteIntent` 记录手动移除；通知点击不自动清除。未读重提醒的次数包含第一次，达到上限仍可确认。每条提醒只保留最新周期，旧周期的延迟确认不会取消新周期。

锁屏时不仅使用 `VISIBILITY_PRIVATE` 和公开占位通知，而且从实际通知正文中移除敏感内容；即使系统设置允许显示所有通知，也不泄露正文。锁屏发出的占位通知在解锁后可能仍显示占位文本，请点击进入 App 查看。App 不使用全屏 Intent、悬浮窗或免解锁显示页面，任务预览受 `FLAG_SECURE` 保护。

安卓休眠、通知频道设置、精确定时权限、勿扰和厂商后台策略仍影响可靠性。未授权精确定时会降级近似定时，页面显示状态。荣耀系统的应用启动管理及锁屏通知亮屏请按设备实况设置。详细验收步骤见 [真机验收](docs/device-testing.md)。

## 模型与依赖

Sherpa ONNX `1.13.8`，Apache-2.0；模型为 `sherpa-onnx-paraformer-zh-int8-2025-10-07`，固定归档 SHA-256：`a071ee5419e14adb34d7f970ab98105a45e6608018b168f023ca2e4810744abe`。上游模型与许可说明见 [Sherpa Paraformer 文档](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-paraformer/paraformer-models.html) 与 [上游仓库](https://github.com/k2-fsa/sherpa-onnx)。

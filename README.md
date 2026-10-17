## v0.7.0 · VITS-MNN 与任务收纳

离线播报已替换为 [Voine/VITS-MNN](https://github.com/Voine/VITS-MNN)，804个音色条目，可搜索角色名和试听。主页自动收起已完成任务，任务收纳支持搜索、归档和编辑复用；左滑任务选择归档或删除，划掉提醒通知后显示静默整理选项。详见 [版本说明](docs/releases/v0.7.0.md)、[播报使用说明](docs/speech.md) 和 [模型来源及许可](docs/third-party-vits.md)。

升级会将旧AISHELL-3音色重置为琪亚娜228，保留提醒时间、循环和播报开关。固定签名支持覆盖更新。当前常规CI不执行手机或模拟器重启测试。

## v0.5.0

支持相对时间语音指令、秒级确认和保存、缺失时间校验、正文隔离、语音模型预热复用，以及可选的解锁亮屏提醒卡片。更新后请在“设置 → 亮屏弹窗增强”开启并授予系统悬浮窗权限。详见 [版本说明](docs/releases/v0.5.0.md)。

# 定时备忘录

面向荣耀100等 arm64 安卓手机的 Flutter 离线语音定时备忘录。四个 Tab：备忘录、日历、语音、设置。

当前工程版本 v0.7.0。源码、GitHub Actions 构建与已发布 APK 位于本仓库；下载见 [Releases](https://github.com/niceday-hh/codex_flutter2/releases)。未经验证的 unsigned 构建不作为安装包发布。

## 本版修复与功能

- 新增默认开启、可关闭的“可靠提醒模式”：有待触发任务时使用可见的静默前台状态通知维护排程；最近任务移除及系统正常回收进程后恢复，任务用完即停止。关闭后仍保留独立的原生系统闹钟路径。不轮询、不长期持有唤醒锁，不能绕过强行停止或厂商限制。
- 设置 → 提醒自检可导出诊断 JSON：包含打开应用恢复前的快照、系统进程退出原因码、排程／触发／通知／确认记录；不含正文、录音或自定义铃声 URI。待处理令牌存在不等于闹钟仍在系统队列，退出原因码不能单独证明强行停止。

- 通知使用私有正文与锁屏占位双版本，系统随解锁自动切换，不依赖 App 进程；重启后首次解锁会静默更新仍在显示的通知，不增加提醒次数。隐藏正文需配合系统关闭“显示敏感内容”，系统隐私选择拥有最终控制。
- 振动模式增加前台试振和节奏说明；自检显示系统通道实际记录的振动段数，并检测与应用偏好的差异。系统默认不保证次数，从系统选择铃声不包含振动导入。
- 创建／编辑提醒可选择横幅和通知栏、仅通知栏；锁屏可选择隐藏正文、完全不显示。设置页可保存新建默认值，默认保持横幅及锁屏隐藏正文。
- 自检只有一个系统通知总入口；高级通知样式按展示、锁屏、振动与有效铃声分组，显示关联记录数和系统差异，隐藏无引用的历史通道。默认样式即使没有提醒也保留入口。
- 编辑器可直接打开当前所选样式的系统通知设置，无须先保存提醒；相同样式共用系统设置。15秒测试使用当前默认样式，单次提醒。
- 升级沿用 v0.2 原有通知通道以保留系统手动设置；旧备份缺失新字段时采用兼容默认值，新字段参与导出导入，本机通道 ID 不进入备份。
- 再次编辑已完成任务后，保存会重新启用并注册系统闹钟。主页显示未启用任务，避免出现仅在日历可见的记录。
- 使用 Android `setAlarmClock`，原生 `BroadcastReceiver` 与持久排程，不依赖 Flutter 界面存活。
- Android 13+ 使用 `USE_EXACT_ALARM`；Android 12使用用户授权的 `SCHEDULE_EXACT_ALARM`。缺少精确权限会明确报错，不静默降级。
- 开机及升级恢复排程；Direct Boot 排程镜像不包含提醒正文，正文仍在凭据加密存储中。
- 设置页提供15秒后台提醒自检、实际触发记录、排程恢复记录和通知通道入口。
- 默认5分钟未读重提醒、共3次含首次，可逐条设置；手动划掉通知或 App 中滑动确认取消剩余提醒。
- 锁屏隐藏正文、非全屏；铃声可从系统选择，振动可选默认／一次／多次，亮屏尽力遵循系统设置。
- 离线 Paraformer 中文 int8 模型内置 APK，识别后确认再保存；录音不上传、识别后删除。
- JSON 导出与合并导入，不覆盖现有数据；校验失败不改动原提醒，过去的单次任务归档，铃声在新设备恢复为默认。备份含正文，请按个人数据保管。

## 固定签名与旧版迁移

v0.1.0 使用临时测试签名，私钥没有保留，因此新签名不能覆盖它。本版使用新包名 `com.niceday.memo.stable`，名称“定时备忘录·新版”，可与旧版并存，保护旧数据。旧版没有导出入口，Android 禁止新版直接读取旧版私有存储；请先保留旧版，查看并迁移重要提醒。

固定密钥备份由应用所有者私下保管，不进入仓库或 Release。证书 SHA-256 已固定在 `docs/signing-certificate.sha256`；后续相同密钥、包名和更大 versionCode 的新版可覆盖升级。

在仓库 Settings → Secrets and variables → Actions 配置四项 Secret：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

值来自交付给所有者的签名备份。配置后运行 Android build and release 工作流。缺失签名时继续执行构建与测试，但不会将 unsigned APK 发布为可安装版本；不会生成新的临时签名来伪装覆盖更新。

## 本地构建

Flutter **3.35.7**、JDK **17**、Android SDK：

```bash
bash tool/bootstrap.sh
flutter analyze
flutter test
mkdir -p tool/out
javac -d tool/out native/app/src/main/java/com/niceday/memo/Schedule.java tool/ScheduleTest.java
java -cp tool/out ScheduleTest
python3 tool/fetch_model.py
flutter build apk --release --target-platform android-arm64
cd android && ./gradlew :app:testReleaseUnitTest
```

发布签名放在本地 `android/key.properties`，`storeFile` 指向固定 PKCS12 密钥，另有 `storePassword`、`keyPassword`、`keyAlias`。这些文件不能提交。

`native/` 保存 Android 自定义源码和配置；`tool/bootstrap.sh` 生成标准 Android 平台包装后合并它。修改原生功能请修改 `native/`。模型由 `tool/fetch_model.py` 从官方版本下载并检查固定 SHA-256，不进入 Git。

## 云端验证和发布

推送 main 后执行两条验证路径：

1. Flutter 静态检查、UI／语音规则测试、JVM 排程边界、原生状态／通知／备份／Direct Boot 测试、arm64 APK 编译及固定证书检查。
2. Android 13／15 x86_64 模拟器分别运行：仅 debug APK 包含测试探针，验证进程被结束且 UI 不在前台、屏幕熄灭和系统休眠时原生闹钟仍触发；重启后不用打开 Flutter Activity 即恢复排程；安全锁屏、解锁及再锁屏时系统切换通知正文，且不依赖 App 进程。另外验证真实任务移除、SIGKILL 后 Android 自动重建 START_STICKY 前台服务、重启后实际到点通知，以及强行停止后必须显式打开才能恢复的边界。探针不进入 Release，模拟器不验证荣耀策略或真实振动马达触感。

两条路径均通过且固定签名配置齐全才发布 `.release-version` 指定版本，附版本说明、构建信息和 SHA-256。新版本只需同步 pubspec、版本标记及版本说明；文件名与构建信息自动从版本生成。已有版本不会被覆盖。

## 系统限制

从最近任务划掉与系统“强行停止”不同。标准 Android 的正常进程结束不取消系统注册的闹钟；荣耀清理器可能施加更强限制，可靠模式可提高存活与恢复机会但不保证厂商行为。强行停止会阻止闹钟和广播，需用户重新打开应用。第三方 App 无法保证拥有系统预装时钟的厂商特殊权限。

系统通知横幅与锁屏显示、勿扰和荣耀后台策略仍有最终控制。应用不会主动解锁，不使用全屏提醒；亮屏受设备策略影响。隐藏正文需在系统通知设置中关闭“显示敏感内容”。请先用提醒自检观察实际到达与通道状态。真机步骤见 [设备测试](docs/device-testing.md)，修改说明见 [v0.4.0](docs/releases/v0.4.0.md)。

## 模型

Sherpa ONNX `1.13.8`；中文模型 `sherpa-onnx-paraformer-zh-int8-2025-10-07`。归档 SHA-256 为 `a071ee5419e14adb34d7f970ab98105a45e6608018b168f023ca2e4810744abe`。模型与许可信息见 [上游文档](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-paraformer/paraformer-models.html)。

前台服务使用 `systemExempted` 类型，基于应用已声明并获得的精确闹钟资格；Android 14+ 同时声明对应前台服务权限。启动被系统拒绝时，设置页显示错误并保留系统闹钟路径，不反复重启。常驻通知不显示任何备忘正文。

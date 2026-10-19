# Codex 云端 Android 开发环境

这套配置准备与当前 GitHub CI 对齐的开发工具链，不依赖 GitHub Actions 执行器，也不读取签名密钥或自动发布 APK。

**当前状态：配置已准备，但账号内环境尚未创建；本次工作区的 Flutter 和模拟器启动受阻。** 具体通过项与阻塞见 [2026-10-19 验证记录](cloud-environment-verification.md)。不要把配置已写入仓库理解为构建已通过。

## 版本依据

| 组件 | 版本或来源 |
| --- | --- |
| 操作系统 | Ubuntu 24.04，x86_64 |
| Flutter / Dart | 3.35.7 stable / 3.9.2 |
| Java | Temurin 17；本配置固定 17.0.20.1+1，CI 原配置为主版本 17 |
| Android compile / target SDK | 36，来自 Flutter 3.35.7 的默认值 |
| Android Build Tools | 36.0.0 |
| Android NDK | 27.0.12077973，来自 Flutter 3.35.7 默认值 |
| CMake | 3.22.1，来自 native/app/build.gradle.kts |
| Android 命令行工具 | 19.0 |
| Gradle / Android Gradle Plugin / Kotlin | 由固定 Flutter 3.35.7 生成标准包装工程，与原 tool/bootstrap.sh 一致 |
| ASR / VAD / MNN / VITS | 沿用仓库已有版本、模型锁和校验脚本 |
| 模拟器 | API 33 / 35，Google APIs，x86_64，与现有 CI 测试矩阵一致 |

下载地址与摘要存于 `tool/cloud-environment.lock.json`。模拟器、platform-tools 与系统镜像补丁版本原 CI 未锁定，本配置使用 SDK 仓库对应稳定包，实际安装版本应在环境报告中记录。

## 安装

需要 Python 3.12，以及 curl、git、tar、unzip、xz-utils 等基础系统工具。安装目录默认位于仓库内 `.codex/toolchain/`；可以通过 `MEMO_CLOUD_ROOT` 改到其他可写目录。不要把工具链和缓存提交到 Git。

安装 JDK、Flutter、Android 命令行工具及构建依赖：

```bash
python3 tool/setup_cloud_environment.py --sdk-packages --accept-android-licenses
source tool/cloud_env.sh
python3 tool/check_cloud_environment.py
```

`--accept-android-licenses` 表示接受本次安装所需的 Android SDK 许可；不提供该参数时不会自动接受。密钥和发布凭据不属于工具链安装。

安装模拟器与两套镜像，并创建 `memo-api33`、`memo-api35`：

```bash
python3 tool/setup_cloud_environment.py --emulators --accept-android-licenses
source tool/cloud_env.sh
python3 tool/check_cloud_environment.py --emulator
```

每个新的终端都先运行 `source tool/cloud_env.sh`。该脚本只设置工具路径、缓存位置及禁止重启测试，不包含任何凭据。

## 项目检查

```bash
bash tool/check_cloud_project.sh
bash tool/check_cloud_project.sh --android
```

第一条沿用静态分析、Flutter 测试（包含真实 VAD 推理）、Java 排程和 Python 回归；第二条还执行原生 Android 单元测试。检查失败时必须保留失败记录，不以已安装工具代替项目验证。

完整 APK 构建前仍需执行仓库现有模型准备：

```bash
source tool/cloud_env.sh
bash tool/bootstrap.sh
python3 tool/fetch_model.py
python3 tool/fetch_tts.py
flutter build apk --debug --target-platform android-arm64
```

Debug APK 仅用于开发。正式发布仍需后续配置原固定签名，并校验原证书；本次安装不会生成新发布密钥。

## 模拟器边界

`emulator -accel-check` 用于检查 KVM 是否可用。安装成功、AVD 创建成功、系统实际启动及设备回归成功是四个不同状态，报告中需分别列出。

有可用 KVM 时，可启动单个模拟器，然后运行原设备测试；本轮不执行任何重启测试：

```bash
source tool/cloud_env.sh
emulator -avd memo-api33 -no-window -gpu software -noaudio -no-boot-anim -no-snapshot
```

另一个终端连接设备并准备好 CI 专用 debug APK 后，按 `docs/device-testing.md` 运行 `MEMO_RUN_REBOOT_TESTS=0 python3 tool/device_test_suite.py`。API 35 单独运行，避免同时争用内存。缺少 KVM 时，软件模拟可能极慢或受宿主限制，不能因此宣称设备测试通过。

## 保存为账号内可复用云环境

在 ChatGPT 的“设置 → Codex Cloud → Environments → Create environment”中选择本仓库，并使用包含本配置的分支。名称建议 `codex_flutter2-android`，先保持私有。

安装阶段运行上述安装命令，并在新终端加载 `tool/cloud_env.sh`。允许访问依赖所需的官方地址：`storage.googleapis.com`、`pub.dev`、`dl.google.com`、`maven.google.com`、`repo.maven.apache.org`、`repo1.maven.org`、`services.gradle.org`、`downloads.gradle.org`、`plugins.gradle.org`、`plugins-artifacts.gradle.org`、`github.com`、`raw.githubusercontent.com`、`codeload.github.com` 和 GitHub 官方发布资产下载域名。实际重定向域名以失败日志及官方来源为准，不关闭 TLS 校验。

准备和测试完成后，发布云环境快照供新任务复用。把配置文件写入仓库并不等于已在账号内创建或发布云环境，必须以云环境页面显示的状态为准。

固定签名及未来 Release 上传授权需在环境的凭据配置中另行提供，不写入此文档、仓库或普通聊天。当前 `tool/publish_release.py` 验证 GitHub Actions 运行记录；采用外部云构建时需独立适配来源与测试证明，不应直接绕过现有校验。

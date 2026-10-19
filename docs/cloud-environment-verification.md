# 2026-10-19 云端环境准备与验证记录

## 创建状态

账号内的可复用 Codex Cloud 环境尚未创建或发布。云浏览器没有现成的 ChatGPT 登录会话，安全登录流程未完成；本记录不能作为环境创建成功的证明。

以下安装和检查在本次聊天的受限云工作区执行。可复用安装配置已准备到仓库独立分支；普通工作区安装并不等于账号内环境快照已保存。

源码基线：`3dbb07bf0237d9643c5463c8c4bf2bf9041748d4`，应用版本仍为 `0.9.1+12`。本次只添加环境配置和说明，没有修改应用功能、签名、发布工作流或版本号。

## 实际验证结果

| 项目 | 结果 |
| --- | --- |
| 源码 | 完整取回并逐个核对 130 个 Git blob 摘要，恢复原始提交及目录树 |
| 操作系统 | Ubuntu 24.04.3 LTS，x86_64 |
| Temurin JDK / javac | 17.0.20.1+1，版本命令及编译运行通过 |
| Flutter / Dart | 3.35.7 / 3.9.2 官方包 SHA-256 通过，已安装；Dart VM 启动中止 |
| Android 命令行工具 | 19.0，版本命令通过 |
| Android SDK / Build Tools | API 36 / 36.0.0 官方包已校验安装；aapt2 可运行 |
| NDK | 27.0.12077973，附带 Clang 18.0.1，版本命令通过 |
| CMake | 3.22.1，版本命令通过 |
| ADB / platform-tools | 37.0.1，版本命令通过 |
| Android Emulator | 官方稳定包 37.2.12 已校验安装；版本启动崩溃、加速检查失败 |
| KVM | 当前工作区不存在 `/dev/kvm` |
| API 33 / 35 系统镜像及 AVD | 未完成安装与创建，未启动设备回归 |
| 原生 Java 排程辅助检查 | 14 项通过 |
| 既有 Python 回归 | 31 项通过 |
| Flutter 静态分析与测试 | 未能运行：Flutter 启动先失败 |
| 原生 Android / Gradle 单元测试 | 未运行：标准 Android 包装工程的生成依赖 Flutter |
| 固定签名 / Release 发布 | 未配置、未执行，等待后续提供原固定签名 |

## 已遇到的具体阻塞

Flutter/Dart 在运行版本命令、生成 Android 标准工程时均先于项目代码执行而中止，日志为：

```text
runtime/vm/os_thread.cc: 49: error: Failed to retrieve stack bounds
version=3.9.2 (stable) on linux_x64
Stack dump aborted because GetAndValidateThreadStackBounds failed.
```

因此，当前工作区不能被声明为“已验证可构建 Flutter APK”。没有更换 Dart/Flutter 版本、修改 VM 或关闭保护来绕过此问题，应在正式云环境的宿主中重新验证。

SDK Manager 能显示版本，但在本工作区的代理连接中无法获取远端包清单，提示 `Failed to download any source lists` 及 `Failed to find package 'platform-tools'`。本次 Android 核心组件改用 Google 官方仓库 XML 指定的稳定 ZIP 下载，并按官方摘要校验后解压；这不是一次 SDK Manager 全流程成功验证。镜像安装仍须在正式环境中完成。

模拟器的 `-version` 发生段错误，`-accel-check` 提示找不到 emulator-check。官方 ZIP 已通过摘要校验，但程序启动问题尚未完全定位；同时当前宿主无 KVM，不能宣称设备测试可用。没有修改宿主设备权限、挂载虚拟化设备或执行重启操作。

## 19:16（北京时间）当前聊天工作区复验

用户改为直接使用当前聊天工作区，不再创建 Codex Cloud 环境。本轮复用了仍然存在的已安装工具，没有重新下载多 GB 的同版本工具包。

- Java 17、javac、SDK Manager 19.0、ADB 37.0.1、CMake 3.22.1、NDK Clang 18.0.1、aapt2 再次启动通过。
- `sdkmanager --list_installed` 成功识别 SDK 36、Build Tools 36.0.0、platform-tools 37.0.1；手工解压的 NDK、CMake 等尚无 `package.xml`，未据此宣称 SDK Manager 完整安装成功。
- **Dart 3.9.2 的版本命令成功，但实际执行最小 Dart 程序仍以 SIGABRT 中止。** 检查器已增加真实执行检查，避免版本输出导致误判。
- `/proc/self/maps` 读取返回 ENOENT；直接调用主线程的 `pthread_getattr_np` 也返回 2（ENOENT）。这与 Dart 启动失败的位置一致，支持宿主兼容性阻塞的判断。Dart 维护者在 [SDK issue #40405](https://github.com/dart-lang/sdk/issues/40405) 解释了同类问题与该系统文件不可访问的关系。
- `bash tool/check_cloud_project.sh` 实际执行后，在 `flutter create` 阶段退出 134；尚未进入 Flutter 分析、测试或 Gradle 单元测试。
- `flutter build apk --debug --target-platform android-arm64` 实际执行后，同样在 VM 启动阶段中止（SIGABRT）；没有生成 APK。
- Java 排程检查再次 14 项通过，既有 Python 回归再次 31 项通过。
- 模拟器 `-version` 仍以 SIGSEGV 中止，启动器的 `-accel-check` 仍报找不到辅助程序；直接运行已存在的 `emulator-check accel` 可启动，返回 3 并报告 `KVM requires a CPU that supports vmx or svm`。同时未暴露 `/dev/kvm`。这不等于辅助程序损坏，也不足以认定底层物理 CPU 不支持虚拟化。
- `emulator -list-avds` 成功退出但返回空列表，API 33/35 AVD **没有就绪**。检查器已修正空列表误算通过的问题，并使 `--emulator` 检查失败时返回非零状态。

详细本地诊断位于 `.codex/state/environment-check.json`、`.codex/state/current-workspace-check.json`、`.codex/state/android-current-workspace-check.json` 和 `.codex/logs/`，均不提交缓存或机器路径日志。未配置固定签名，未执行 Release 发布。

## 后续完成条件

1. 当前工作区可继续编辑源码并运行已验证的 Java/Python 检查。完整 APK 构建需要宿主提供官方 Dart VM 所需的正常线程栈信息；普通目录、PATH 或项目依赖配置不能代替这一条件。
2. 首先验证 `flutter --version` 能正常返回，再运行项目检查；若仍有线程栈错误，应更换受支持的宿主环境。
3. 在该环境重新执行 SDK Manager 安装及本地包识别检查，完成 API 33 / 35 镜像和 AVD 配置。
4. 验证模拟器实际启动及原有双版本设备测试。缺少 KVM 或模拟器仍不能运行时，设备回归需使用另一可运行的测试环境。
5. 最后再通过环境凭据配置提供原固定签名；此记录与仓库不存储密钥。

可执行入口和独立主机安装步骤见 [cloud-environment.md](cloud-environment.md)。

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

## 后续完成条件

1. 在已登录的 Codex Cloud 中创建本仓库的私有环境，安装并发布环境快照。
2. 首先验证 `flutter --version` 能正常返回，再运行项目检查；若仍有线程栈错误，应更换受支持的宿主环境。
3. 在该环境重新执行 SDK Manager 安装及本地包识别检查，完成 API 33 / 35 镜像和 AVD 配置。
4. 验证模拟器实际启动及原有双版本设备测试。缺少 KVM 或模拟器仍不能运行时，设备回归需使用另一可运行的测试环境。
5. 最后再通过环境凭据配置提供原固定签名；此记录与仓库不存储密钥。

可执行入口和环境创建步骤见 [cloud-environment.md](cloud-environment.md)。

# 当前工作区 APK 编译继续排查记录

时间：2026-10-19T19:40:07.713723+08:00。

## 本轮结果

未生成 APK。以 `flutter build apk --debug --target-platform android-arm64` 实际尝试构建，外层命令退出 245；内部 Dart 在依赖准备期间收到 SIGSEGV（11），尚未进入 Gradle 编译。此次未启动模拟器、未配置发布签名。

## 有限进展与适用边界

当前进程主线程的 pthread_getattr_np 返回 ENOENT，而普通 pthread 能获得真实的 8 MiB 栈范围。本轮只在子进程中试用一个实验性启动适配器：通过标准动态链接入口将 Dart 的 main 放到真实 pthread 执行，不替换 pthread_getattr_np，不伪造线程栈数据，也不关闭 VM 校验。

适配后最小程序打印 dart-ok，Flutter 版本命令也通过；普通进程启动、Isolate.run、操作系统信息等独立探针通过。然而 Platform.resolvedExecutable 探针发生 SIGSEGV，flutter doctor、项目 bootstrap 和实际 APK 命令在依赖准备中复现同一类崩溃。该适配不能视为完整修复，未加入默认安装或终端配置。

本次环境读取 /proc/self/exe 同样返回 ENOENT。使用 SDK 自带 dart.sym 映射调用栈，偏移 0x2087109 落在 dart::bin::Builtin_Platform_ResolvedExecutableName；Dart 3.9.2 官方平台实现会通过 /proc/self/exe 解析可执行文件路径。这支持存在第二处与执行沙箱接口有关的阻塞，但尚未在正常 procfs 环境完成修复后的因果验证。

官方实现：[platform_linux.cc](https://github.com/dart-lang/sdk/blob/3.9.2/runtime/bin/platform_linux.cc) 与 [file_linux.cc](https://github.com/dart-lang/sdk/blob/3.9.2/runtime/bin/file_linux.cc)。本轮没有创建伪造 procfs 或符号链接，没有拦截文件系统查询来假装底层接口就绪，没有更换 Flutter/Dart 版本或修改其二进制。

## 已准备的资源

Paraformer 模型与 tokens 已经沿用原 fetch_model.py 校验安装（model.int8.onnx 为 238,429,929 字节）。VITS-MNN 原锁定资源 61,336,225 字节已校验，包含 804 音色配置。工具和模型安装不代表 APK 编译通过。

## Flutter 版本命令原始输出

```text
{
  "frameworkVersion": "3.35.7",
  "channel": "stable",
  "repositoryUrl": "https://github.com/flutter/flutter.git",
  "frameworkRevision": "adc901062556672b4138e18a4dc62a4be8f4b3c2",
  "frameworkCommitDate": "2025-10-21 14:16:03 -0400",
  "engineRevision": "035316565ad77281a75305515e4682e6c4c6f7ca",
  "engineCommitDate": "2025-10-21 14:28:01.000Z",
  "engineContentHash": "6b24e1b529bc46df7ff397667502719a2a8b6b72",
  "engineBuildDate": "2025-10-21 08:21:13.472",
  "dartSdkVersion": "3.9.2",
  "devToolsVersion": "2.48.0",
  "flutterVersion": "3.35.7",
  "flutterRoot": "/workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter"
}
```

## 实际 APK 命令与完整日志

终端依次加载 tool/cloud_env.sh 与本地实验适配环境，然后执行：

```bash
flutter build apk --debug --target-platform android-arm64
```

完整 stdout/stderr：

```text

===== CRASH =====
si_signo=Segmentation fault(11), si_code=?(128), si_addr=(nil)
version=3.9.2 (stable) (Wed Aug 27 03:49:40 2025 -0700) on "linux_x64"
pid=37, thread=42, isolate_group=dartdev(0x7fd028000df0), isolate=dartdev(0x7fd028009c80)
os=linux, arch=x64, comp=no, sim=no
isolate_instructions=7fd03c219000, vm_instructions=558cce7ecd80
fp=7fd0277fd620, sp=7fd0277fd610, pc=558cce9be666
  pc 0x0000558cce9be666 fp 0x00007fd0277fd620 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x2251666
  pc 0x0000558cce952e32 fp 0x00007fd0277fd640 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x21e5e32
  pc 0x0000558ccea3e2b7 fp 0x00007fd0277fd6a0 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x22d12b7
  pc 0x0000558cceca1b9f fp 0x00007fd0277fd750 Dart_NewStringFromCString+0x16f
  pc 0x0000558cce7f4109 fp 0x00007fd0277fd770 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x2087109
  pc 0x0000558cce9f620f fp 0x00007fd0277fd7c0 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x228920f
  pc 0x0000558cce9f5e83 fp 0x00007fd0277fddc0 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x2288e83
  pc 0x00007fd03c5830a4 fp 0x00007fd0277fde08 Unknown symbol
  pc 0x00007fd03c251a1a fp 0x00007fd0277fde38 Unknown symbol
  pc 0x00007fd03c251a91 fp 0x00007fd0277fde60 Unknown symbol
  pc 0x00007fd03c58808c fp 0x00007fd0277fde88 Unknown symbol
  pc 0x00007fd03c251d5c fp 0x00007fd0277fdeb0 Unknown symbol
  pc 0x00007fd03c251f7a fp 0x00007fd0277fded8 Unknown symbol
  pc 0x00007fd03c252671 fp 0x00007fd0277fdf40 Unknown symbol
  pc 0x00007fd03c264b31 fp 0x00007fd0277fdf68 Unknown symbol
  pc 0x00007fd03c5880dc fp 0x00007fd0277fdf90 Unknown symbol
  pc 0x00007fd03c25105c fp 0x00007fd0277fdfb8 Unknown symbol
  pc 0x00007fd03c264bb1 fp 0x00007fd0277fdfe0 Unknown symbol
  pc 0x00007fd03c5880dc fp 0x00007fd0277fe008 Unknown symbol
  pc 0x00007fd03c264c3c fp 0x00007fd0277fe030 Unknown symbol
  pc 0x00007fd03c270844 fp 0x00007fd0277fe070 Unknown symbol
  pc 0x00007fd03c270a0b fp 0x00007fd0277fe0b0 Unknown symbol
  pc 0x00007fd03c5880dc fp 0x00007fd0277fe0d8 Unknown symbol
  pc 0x00007fd03c270aec fp 0x00007fd0277fe100 Unknown symbol
  pc 0x00007fd03c271c65 fp 0x00007fd0277fe138 Unknown symbol
  pc 0x00007fd03c271db4 fp 0x00007fd0277fe178 Unknown symbol
  pc 0x00007fd03c5880dc fp 0x00007fd0277fe1a0 Unknown symbol
  pc 0x00007fd03c271efc fp 0x00007fd0277fe1c8 Unknown symbol
  pc 0x00007fd03c27206b fp 0x00007fd0277fe228 Unknown symbol
  pc 0x00007fd03c2724e8 fp 0x00007fd0277fe288 Unknown symbol
  pc 0x00007fd03c275da4 fp 0x00007fd0277fe320 Unknown symbol
  pc 0x00007fd03c2764af fp 0x00007fd0277fe3b8 Unknown symbol
  pc 0x00007fd03c27e6f5 fp 0x00007fd0277fe420 Unknown symbol
  pc 0x00007fd03c27e84c fp 0x00007fd0277fe458 Unknown symbol
  pc 0x00007fd03c27cc67 fp 0x00007fd0277fe4c8 Unknown symbol
  pc 0x00007fd03c27ce05 fp 0x00007fd0277fe518 Unknown symbol
  pc 0x00007fd03c27f044 fp 0x00007fd0277fe580 Unknown symbol
  pc 0x00007fd03c27f25c fp 0x00007fd0277fe5d8 Unknown symbol
  pc 0x00007fd03c583406 fp 0x00007fd0277fe650 Unknown symbol
  pc 0x0000558cce9a5543 fp 0x00007fd0277fe6c0 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x2238543
  pc 0x0000558cce9a6f0d fp 0x00007fd0277fe700 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x2239f0d
  pc 0x0000558cce9c576c fp 0x00007fd0277fec90 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x225876c
  pc 0x0000558cce9e8960 fp 0x00007fd0277fed00 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x227b960
  pc 0x0000558cce9e8d50 fp 0x00007fd0277fed50 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x227bd50
  pc 0x0000558cceac2ee7 fp 0x00007fd0277fedd0 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x2355ee7
  pc 0x0000558cceac3142 fp 0x00007fd0277fee00 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x2356142
  pc 0x0000558ccea73189 fp 0x00007fd0277feec0 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x2306189
  pc 0x00007fd03d474aa4 fp 0x00007fd0277fef70 /lib/x86_64-linux-gnu/libc.so.6+0x9caa4
-- End of DumpStackTrace

Failed to update packages.
```

## 后续需要的执行条件

先让官方 Dart 的最小程序以及可执行路径查询、pub 依赖命令正常运行，再继续 APK 构建。当前会话没有管理底层 procfs 或隔离策略的接口，也没有第二个可用的普通 Linux 构建执行器；继续调整项目业务代码或签名不会补齐这类底层接口。

SDK 版本与项目保持 Flutter 3.35.7 / Dart 3.9.2。模拟器、KVM 和正式签名不作为 Debug APK 编译前提。

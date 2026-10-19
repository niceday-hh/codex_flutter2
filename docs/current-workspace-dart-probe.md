# 当前执行环境最小 Dart 验证原始记录

时间：2026-10-19T19:29:44.450832+08:00。

直接调用 Flutter 3.35.7 随附的 Dart 3.9.2 SDK 二进制；未经过 Flutter/Dart 的 shell 包装器，未加载项目代码、插件或 pub 依赖。

`/tmp` 在本执行环境中不存在，因此使用已配置的可写 `TMPDIR` 保存探针。没有创建或模拟 procfs。

探针源代码：

```dart
void main() { print("dart-ok"); }
```

## 1. head -n 3 /proc/self/maps

退出状态：`1`。

完整 stdout：

```text
(empty)
```

完整 stderr：

```text
head: cannot open '/proc/self/maps' for reading: No such file or directory
```

## 2. /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart --version

退出状态：`0`。

完整 stdout：

```text
Dart SDK version: 3.9.2 (stable) (Wed Aug 27 03:49:40 2025 -0700) on "linux_x64"
```

完整 stderr：

```text
(empty)
```

## 3. /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/tmp/dart-minimal-probe/dart_probe.dart

退出状态：`-6`（Python 的 -6 表示 SIGABRT）。

完整 stdout：

```text
(empty)
```

完整 stderr：

```text
../../runtime/vm/os_thread.cc: 49: error: Failed to retrieve stack bounds
version=3.9.2 (stable) (Wed Aug 27 03:49:40 2025 -0700) on "linux_x64"
pid=10, thread=10, isolate_group=(nil)((nil)), isolate=(nil)((nil))
os=linux, arch=x64, comp=no, sim=no
isolate_instructions=0, vm_instructions=0
fp=7fff5cc39310, sp=7fff5cc392e0, pc=56537dd25e56
Stack dump aborted because GetAndValidateThreadStackBounds failed.
  pc 0x000056537dd25e56 fp 0x00007fff5cc39310 /workspace/scratch/22f1bfc18fba/codex_flutter2/.codex/toolchain/flutter/bin/cache/dart-sdk/bin/dart+0x2308e56
```

## 线程栈信息调用

同一执行环境的 Python 主线程调用 `pthread_getattr_np(pthread_self(), ...)`，返回 `2`（`No such file or directory`）。

## 结论与边界

本次实际结果是：`/proc/self/maps` 读取失败；SDK 版本命令成功；最小 Dart 程序启动即报 `Failed to retrieve stack bounds` 并中止。这将故障收敛到当前执行环境与 Dart VM 的兼容性，而非本项目的依赖解析或业务代码。缺失 procfs 与线程栈信息调用失败的关联是基于观测和 Dart 官方记录的诊断；没有通过修改底层隔离配置进行因果修复验证。

这里的“不可访问”只描述本会话进程可见的执行沙箱，不能推断物理主机没有 `/proc`，也未确认隔离层采用何种实现。本会话没有管理底层挂载或访问策略的接口；未尝试绕过该限制。

APK 编译与模拟器、KVM 分开处理。恢复 Dart 执行后应先按项目现有 `tool/bootstrap.sh` 生成 Android 包装工程、准备固定版本依赖和模型，再做静态分析、测试及 Debug APK 构建；不以模拟器就绪或固定发布签名为前提。当前的构建尝试已在 Dart 启动阶段失败，没有生成 APK。

官方同类问题：[dart-lang/sdk #40405](https://github.com/dart-lang/sdk/issues/40405)。本记录保留本次完整 stdout/stderr，不用版本查询或 Java/Python 检查代替 Flutter 验证。

# 自动发版与失败后补发

## 正常发布新版本

在 main 更新应用代码，同时更新 pubspec.yaml 的版本和 build 号、.release-version，以及 docs/releases/v版本号.md。推送后沿用 Android build and release 工作流，完成静态检查、Flutter/Java/Python 测试、固定签名构建、Android API 33/35 回归，最后自动发布。

正式发布与补发使用同一个 tool/publish_release.py。版本号、说明和签名校验依据都取自原始构建的提交，发布标签也指向那个已测试的提交。

发布需要 checks、prepare、build、emulator (33)、emulator (35) 全部成功。脚本重新校验下载文件的大小和 SHA-256、构建元数据、原生测试结果及 APK 的固定签名；直接发布原有 CI 草稿，保留所有原有资产，不重新上传 APK，不删除历史版本。

已经发布的版本不会被覆盖。若 main 的新提交沿用同一版本号，日志会明确提示跳过已有版本，需要提升版本号后才能发布这些修改。

## 只补发已经通过测试的构建

适用于应用已经构建并通过测试，而 publish 失败的情况。无需重新下载模型、编译 APK 或启动模拟器。

方法一：在 GitHub 的 Actions 中选择 Publish existing verified build，点击 Run workflow，选择 main，填写原 Android 构建的运行编号 source_run_id。

方法二：通过 GitHub 插件修改 main 上的 .github/release-request.json，例如：

```json
{
  "source_run_id": "39044382161",
  "request_id": "2026-10-18-01"
}
```

每次重试更新 request_id，使文件形成新提交。source_run_id 是 Actions 页面地址中 runs/ 后面的数字，不是任务 job 编号。这个文件的提交只启动补发工作流，不会重复触发完整 Android 构建。

补发任务先执行发布器单元测试，再验证原运行。只允许本仓库 main 上受信任的 Android 构建；失败、跳过、缺失的验证任务、未完成的外部构建、错误签名或资产变化都会阻止发布。两个发布入口共用并发组，避免同时发布。

补发不需要访问四个签名 secret；它校验已经签名的 APK。固定包名和证书不变。

## 如果任务没有启动

工作流代码不能解除 GitHub 对托管执行器的额度、预算、支付、账户或平台限制。若任务的执行器 ID 为 0、没有任何步骤和日志，应查看运行页 Annotations 中的原始错误，并核对账户 Actions 用量和适用预算。原始错误未确认前，不应把这些候选原因中的某一项当作最终结论。

在账户限制解除后，重新运行失败的发布任务，或通过上述补发入口请求同一个原始运行即可。现有已通过的测试和签名 APK 继续有效。

本次发布自动化调整不修改应用运行代码，不加载识别/播报模型，不执行手机或模拟器重启。

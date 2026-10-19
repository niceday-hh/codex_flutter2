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

## 2026-10-18 启动错误已确认

用户提供的任务截图明确显示：GitHub 因近期账户付款失败，或支出上限需要提高，而没有启动任务。这是 Actions 计费/预算层面的启动阻断；截图本身不能进一步区分付款失败、可用额度耗尽或哪一项预算生效，需在账户账单页核对。

Ubuntu 26 迁移和 2FA 横幅均不是本次红色启动错误。正常构建及通用补发已固定使用已验证的 ubuntu-24.04，避免 ubuntu-latest 自动迁移改变构建环境。此调整不解除账户计费限制。

账户所有者需打开 https://github.com/settings/billing，核对 Actions 的 Usage、Budgets and alerts 中的适用支出限制，以及付款/账单是否存在失败。涉及增加支出或支付的修改由账户所有者决定；如果仅为额度用尽且不希望新增费用，可等待额度周期重置。

账户限制处理后，使用 main 上 Publish existing verified build 的 Run workflow 输入原始构建编号，或更新 .github/release-request.json 的 request_id，启动当前配置的补发工作流。无需重新构建已经校验的 APK。

## 2026-10-19 公有仓库构建已恢复

仓库现已改为公有。新建的独立验证运行 [39252580940](https://github.com/niceday-hh/codex_flutter2/actions/runs/39252580940) 在北京时间 20:30 至 20:36 成功分配标准 `ubuntu-24.04` 执行器，并完成 Flutter/Dart 实测、项目准备、arm64 Debug APK 编译、资源/归档校验和产物上传；这不是复用旧构建的绿色状态。

独立工作流 `Public repository APK build check` 仅验证打包，使用只读仓库权限和调试签名，不运行正式发布器。编译成功不等于完整发布验证已通过；发布新版本仍按本文开头的测试、版本号和固定签名流程执行。

[GitHub Actions 计费规则](https://docs.github.com/en/billing/concepts/product-billing/github-actions)说明，公有仓库的标准 GitHub 托管执行器可免费使用。此前私有仓库的启动阻断属于历史记录，不能据此继续认定当前公有仓库不能构建。本次运行的 APK、SHA-256、来源提交与下载入口见 [public-actions-build-check.md](public-actions-build-check.md)。

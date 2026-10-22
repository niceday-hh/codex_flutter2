# 网页中文合成基准（v0.9.7 开发）

来源：zomehwh/vits-uma-genshin-honkai 的 app.py 与 text/cleaners.py。

- 正式合成 stage 5：保留原始预测时长，不施加标点上下限。stage 0–4 仅保留用于诊断对照。
- noise_scale 与 noise_scale_w 范围 0.1–1，默认 0.6/0.668；新生成随机，选定后复用同一 WAV。
- length_scale 范围 0.1–2，语速字段继续存倒数，避免破坏旧备份；按钮可精确选择网页中文默认 1.2。打开设置不改变旧参数。
- 中文分词从系统 BreakIterator 改为离线 jieba-analysis 1.0.2。它是 Jieba 的 Java 移植，并非保证与 Python 词典和 pypinyin 每个音素一致。
- 拉丁字母不再被清洗删除，沿用中文前端字母名称读法；这不是英语单词 G2P。
- 每段不超过约 100 个 Unicode 码点，优先句末、其次分句、再词边界；闭引号随前句。音素超过 960 时递归分段，JNI 仍限制 1024；不额外补静音。
- 日期/时间规范化保留提醒场景的正确读法，与网页通用数字规范化存在有意差异。
- 缓存版本升级为 web-baseline-v5，避免误用旧节奏文件。已有提醒需重新准备音频；随机种子保持。旧 WAV 不代表新基准的试听结果。

## 尚未宣称对齐的范围

日语与中日混合需要 OpenJTalk 对应前端，当前不支持；日语来源角色仍可朗读中文。尚未完成跨 PyTorch/MNN 相同噪声张量的逐层误差对照，也未完成全部中文音素的一致性验证。不能以自动测试通过替代主观听感验收。

## 依赖

新增 com.huaban:jieba-analysis:1.0.2，Apache-2.0：https://github.com/huaban/jieba-analysis 。词典随依赖离线打包，不在运行时下载。

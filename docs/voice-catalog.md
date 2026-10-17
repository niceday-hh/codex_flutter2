# 音色分组

音色顺序与模型固定为 Voine/VITS-MNN commit 6379f381b85f544a5debca3804bf300225c6729e 的804个speaker ID，不调整模型或编号。原模型资料：<https://huggingface.co/spaces/zomehwh/vits-uma-genshin-honkai>，MNN移植：<https://github.com/Voine/VITS-MNN>。

native/app/src/main/assets/voice_catalog.json 是原生随机选择和Flutter筛选共用的数据源，按ID数组排列。0～86及148（真弓快车）为赛马娘日配音色，300～364为上游明确标注“日语”的原神音色，其余为中文配音来源。分组按配音来源，不表示当前应用支持输入日文或翻译。

性别标签表示角色性别，不表示声优性别或声学上的音高。当前保守标注了232个女性角色、51个男性角色；其余521个NPC、混合或未核对角色保留unknown。不会根据中文姓名、角色配音声优的性别或音高自动猜测。unknown仅参与不限性别的随机，不进入男／女角色池。分组有误时可在后续更新中修正元数据，已保存任务的实际音色不受自动改写。

创建时从筛选条件的交集中抽取并保存speaker ID；触发提醒和恢复排程不重新抽取，音频缓存继续按实际speaker ID、正文和语速区分。保留原始模型和第三方许可；个人试听效果以实际设备为准。

import 'package:flutter/material.dart';

enum SettingsCategory { reminders, voiceInput, speech, background, data, help }

class SettingsSection {
  final SettingsCategory category;
  final String title, subtitle, keywords;
  final IconData icon;
  const SettingsSection(this.category, this.title, this.subtitle, this.icon, this.keywords);
  bool matches(String query) => '$title $subtitle $keywords'.toLowerCase().contains(query.toLowerCase());
}

const settingsSections = [
  SettingsSection(SettingsCategory.reminders, '提醒与通知', '铃声、振动与再次提醒', Icons.notifications_none_rounded,
    '默认展示方式 默认锁屏显示 默认样式 系统设置 振动模式 铃声 选择系统铃声 未读再次提醒间隔 提醒总次数 尝试亮屏 亮屏弹窗增强'),
  SettingsSection(SettingsCategory.voiceInput, '语音录入', '免手预听与自动停录', Icons.mic_none_rounded,
    '离线语音识别 打开应用后预听语音指令 连续安静后自动结束录音 自动停录等待 静音等待 试用免手输入 本机离线'),
  SettingsSection(SettingsCategory.speech, '语音播报', '音色、语速与角色组', Icons.volume_up_outlined,
    '我的角色组 音色 语速 随机 分组 锁屏播报 语音准备状态 重新准备提醒语音 VITS'),
  SettingsSection(SettingsCategory.background, '后台与权限', '可靠提醒与系统授权', Icons.shield_outlined,
    '可靠提醒模式 提醒服务状态 通知权限 锁屏内容保护 精确定时权限 后台运行 电池优化 应用系统设置 荣耀应用启动管理'),
  SettingsSection(SettingsCategory.data, '任务与数据', '历史记录、备份与导入', Icons.storage_outlined,
    '历史任务 划掉通知后询问整理方式 导出备忘录 合并导入备忘录 数据迁移'),
  SettingsSection(SettingsCategory.help, '帮助与诊断', '提醒自检与使用帮助', Icons.help_outline_rounded,
    '检查系统通知与锁屏设置 测试提醒完成后自动删除 15秒后发送测试提醒 系统闹钟排程 最近实际触发 最近恢复排程 导出提醒诊断 通知样式 固定发布签名 使用提示'),
];

class SettingsEntry {
  final String id, title, description, keywords, target;
  final SettingsCategory category;
  const SettingsEntry(this.id, this.category, this.title, this.description, this.keywords, {this.target = ''});
  SettingsSection get section => settingsSections.firstWhere((s) => s.category == category);
  String get anchor => target.isEmpty ? title : target;
  bool matches(String query) {
    final source = '$title $description $keywords ${section.title}'.toLowerCase();
    return query.toLowerCase().trim().split(RegExp(r'\s+')).every(source.contains);
  }
}

const settingsEntries = [
  SettingsEntry('presentation', SettingsCategory.reminders, '默认展示方式', '新建提醒使用横幅和通知栏，或仅在通知栏显示。', '横幅 通知 样式', target: '默认提醒'),
  SettingsEntry('lockscreen', SettingsCategory.reminders, '默认锁屏显示', '选择锁屏隐藏正文，或不在锁屏显示。', '隐私 正文', target: '默认提醒'),
  SettingsEntry('style', SettingsCategory.reminders, '默认样式的系统设置', '打开当前默认通知样式的系统设置。', '系统 通道 横幅 锁屏'),
  SettingsEntry('vibration', SettingsCategory.reminders, '振动模式', '选择提醒节奏，也可先试振；试振不会改变选择。', '震动 触感 试振 测试 一次 两次 三次'),
  SettingsEntry('sound', SettingsCategory.reminders, '铃声', '到时播放系统通知铃声。', '声音 静音'),
  SettingsEntry('ringtone', SettingsCategory.reminders, '选择系统铃声', '从手机系统中选择提醒铃声。', '声音 音乐'),
  SettingsEntry('interval', SettingsCategory.reminders, '未读再次提醒间隔', '没有确认已读时，隔多少分钟再次提醒。', '间隔 分钟 重试'),
  SettingsEntry('count', SettingsCategory.reminders, '提醒总次数', '包含首次提醒，达到次数后停止本轮重提醒。', '次数 重复 五次'),
  SettingsEntry('wake', SettingsCategory.reminders, '尝试亮屏', '提醒到达时尝试唤醒屏幕，实际效果由系统控制。', '亮屏 唤醒'),
  SettingsEntry('popup', SettingsCategory.reminders, '亮屏弹窗增强', '解锁亮屏时显示提醒小卡片，需要悬浮窗权限。', '悬浮窗 小卡片 弹窗'),
  SettingsEntry('handsFree', SettingsCategory.voiceInput, '打开应用后预听', '从桌面或其他应用返回后预听15秒；切换Tab不重新开麦。', '免手 自动 语音 指令 打开应用后预听语音指令'),
  SettingsEntry('autoStop', SettingsCategory.voiceInput, '静音后自动结束', '连续无有效人声时结束录音并进入确认。', '自动停录 连续安静后自动结束录音'),
  SettingsEntry('silence', SettingsCategory.voiceInput, '自动停录等待', '选择连续安静多少秒后结束录音。', '静音 等待 秒 无声'),
  SettingsEntry('offline', SettingsCategory.voiceInput, '本机离线', '录音只在本机识别，无需联网。', '识别 模型 隐私'),
  SettingsEntry('trial', SettingsCategory.voiceInput, '试用免手输入', '先说“开始录音”，再说时间和事项。', '语音 录入 试用'),
  SettingsEntry('groups', SettingsCategory.speech, '我的角色组', '创建和调整随机音色的角色范围。', '分组 随机 成员'),
  SettingsEntry('speechMode', SettingsCategory.speech, '语音播报开关', '控制新提醒默认是否朗读正文。', '开启 关闭 声音', target: '离线语音播报'),
  SettingsEntry('speechVoice', SettingsCategory.speech, '播报音色', '选择提醒使用的声音，也可按角色组随机。', '角色 声音 随机 音色', target: '离线语音播报'),
  SettingsEntry('speechRate', SettingsCategory.speech, '播报语速', '调整提醒朗读速度。', '快 慢 速度', target: '离线语音播报'),
  SettingsEntry('speechVariation', SettingsCategory.speech, '高级语音设置', '调整声音与节奏变化；新生成时随机，选定后保存并复用。', 'noise_scale noise_scale_w 噪声 声音 节奏 随机 高级', target: '离线语音播报'),
  SettingsEntry('speechRandom', SettingsCategory.speech, '新建任务随机音色', '创建时抽取并保存，同一任务的循环和重提醒保持相同音色。', '随机 开关', target: '离线语音播报'),
  SettingsEntry('speechGroup', SettingsCategory.speech, '随机角色组', '开启随机音色后，选择参与抽取的角色组。', '分组 范围', target: '离线语音播报'),
  SettingsEntry('speechSource', SettingsCategory.speech, '配音来源', '在随机音色中按角色配音来源筛选，不会自动翻译。', '来源 分组 语言', target: '离线语音播报'),
  SettingsEntry('speechGender', SettingsCategory.speech, '角色性别', '在随机音色中按角色性别筛选；未知性别仅参与不限性别随机。', '性别 男 女', target: '离线语音播报'),
  SettingsEntry('speechLock', SettingsCategory.speech, '锁屏时隐藏播报正文', '选择锁屏时隐藏播报正文，或允许朗读。', '隐私 正文 朗读 锁屏播报', target: '离线语音播报'),
  SettingsEntry('speechRepeat', SettingsCategory.speech, '重提醒时再次朗读', '选择再次提醒时是否继续朗读。', '重复 次数 播报', target: '离线语音播报'),
  SettingsEntry('speechPreview', SettingsCategory.speech, '试听当前音色', '用固定短句试听，实际播放受手机媒体音量控制。', '试听 随机音色 媒体 声音', target: '离线语音播报'),
  SettingsEntry('speechStatus', SettingsCategory.speech, '语音准备状态', '查看提醒音频的本机准备进度。', '音频 状态'),
  SettingsEntry('prepareSpeech', SettingsCategory.speech, '重新准备提醒语音', '补齐未完成的音频，不改变提醒时间。', '重试 音频 失败'),
  SettingsEntry('reliable', SettingsCategory.background, '可靠提醒模式', '有待触发任务时维护排程并显示静默状态通知。', '后台 常驻 保活'),
  SettingsEntry('service', SettingsCategory.background, '提醒服务状态', '查看当前是否在维护待触发提醒。', '后台 服务'),
  SettingsEntry('notifications', SettingsCategory.background, '通知权限', '查看系统是否允许本应用发送通知。', '授权 通知'),
  SettingsEntry('privacy', SettingsCategory.background, '锁屏内容保护', '系统随锁屏和解锁切换通知正文。', '隐私 正文'),
  SettingsEntry('exact', SettingsCategory.background, '精确定时权限', '打开精确定时授权，按时触发提醒。', '授权 闹钟 定时'),
  SettingsEntry('battery', SettingsCategory.background, '后台运行', '检查手机对应用的电池优化限制。', '电池 优化 后台'),
  SettingsEntry('appSettings', SettingsCategory.background, '应用系统设置', '打开手机应用详情，检查启动与后台权限。', '荣耀 启动 自启动'),
  SettingsEntry('history', SettingsCategory.data, '历史任务', '浏览、搜索和复用已完成或主动保留的记录。', '历史 归档 完成'),
  SettingsEntry('cleanup', SettingsCategory.data, '划掉通知后询问整理方式', '划掉通知后先结束本轮，再询问保留或删除。', '整理 删除 归档'),
  SettingsEntry('export', SettingsCategory.data, '导出备忘录', '把现有提醒备份到你选择的位置。', '备份 导出 数据'),
  SettingsEntry('import', SettingsCategory.data, '合并导入备忘录', '新增导入记录并保留现有数据；重复导入会新增重复记录。', '备份 恢复 导入 数据'),
  SettingsEntry('notificationSettings', SettingsCategory.help, '检查系统通知与锁屏设置', '打开应用通知总设置；各通知样式可以分别管理。', '通知 授权 锁屏'),
  SettingsEntry('testDelete', SettingsCategory.help, '测试提醒完成后自动删除', '仅影响新建的15秒自检提醒，普通备忘录不受影响。', '测试 自检 删除'),
  SettingsEntry('test', SettingsCategory.help, '15秒后发送测试提醒', '按当前默认样式创建一次测试提醒，成功后可返回桌面等待。', '测试 自检 15秒 备忘录 提醒'),
  SettingsEntry('schedule', SettingsCategory.help, '系统闹钟排程', '查看精确定时是否可用。', '闹钟 排程 定时'),
  SettingsEntry('lastReceived', SettingsCategory.help, '最近实际触发', '查看系统最近一次实际收到提醒的时间。', '触发 记录 时间'),
  SettingsEntry('lastRestored', SettingsCategory.help, '最近恢复排程', '查看最近一次恢复本机提醒排程的时间。', '恢复 记录 时间'),
  SettingsEntry('diagnostics', SettingsCategory.help, '导出提醒诊断', '导出排程和进程信息，不包含备忘正文或录音。', '诊断 排查 错误 报告'),
  SettingsEntry('styles', SettingsCategory.help, '通知样式', '按展示、振动和铃声分组查看系统通知设置。', '通道 样式 振动 铃声'),
  SettingsEntry('signing', SettingsCategory.help, '固定发布签名', '同一签名的新版可覆盖安装，数据保存在本机。', '升级 安装 签名'),
  SettingsEntry('help', SettingsCategory.help, '使用提示', '查看已读、循环、后台与系统通知限制的使用说明。', '帮助 说明'),
];


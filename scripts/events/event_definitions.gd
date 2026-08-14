# event_definitions.gd
# ★事件都在这里加★
# --------------------------------------------------------------------------
# 每个事件 = {
#     "messages": [ "文本key", ... ],   # 员工依次说的话；文本在 language/events.csv 里填中英文
#     "options":  [                       # 玩家可选的两句话（点假输入框后出现，最多两条）
#         { "text": "文本key", "stat": "efficiency"|"quality"|"experience", "amount": 整数 },
#         ...
#     ],
# }
#
# 选项里的 stat + amount 决定选它之后给【全体员工】加什么 buff：
#   stat   = 效率 efficiency / 质量 quality / 经验 experience
#   amount = 加几点（可正可负，比如 +1 / -1）
#   每份 buff 持续 3 分钟后自动消失（时长在 OfficeManager.EVENT_BUFF_DURATION 里改）。
#
# 加新事件的步骤：
#   1. 在下面 EVENTS 里再塞一个字典，写好 messages / options 的 key 和每个选项的 buff；
#   2. 到 language/events.csv 里，把这些 key 的中文、英文补上。
# --------------------------------------------------------------------------
class_name EventDefinitions
extends RefCounted

const EVENTS := [
	 #1｜裁员传闻
	{
		"messages": ["event_1_msg_1", "event_1_msg_2"],
		"options": [
			{"text": "event_1_opt_a", "stat": "efficiency", "amount": 1},
			{"text": "event_1_opt_b", "stat": "efficiency", "amount": -1},
		],
	},
	# 2｜方案被打回
	{
		"messages": ["event_2_msg_1", "event_2_msg_2"],
		"options": [
			{"text": "event_2_opt_a", "stat": "quality", "amount": 1},
			{"text": "event_2_opt_b", "stat": "efficiency", "amount": 1},
		],
	},
	# 3｜周末加班
	{
		"messages": ["event_3_msg_1", "event_3_msg_2"],
		"options": [
			{"text": "event_3_opt_a", "stat": "efficiency", "amount": 2},
			{"text": "event_3_opt_b", "stat": "quality", "amount": 1},
		],
	},
	# 4｜团建通知
	{
		"messages": ["event_4_msg_1", "event_4_msg_2"],
		"options": [
			{"text": "event_4_opt_a", "stat": "experience", "amount": 2},
			{"text": "event_4_opt_b", "stat": "quality", "amount": 1},
		],
	},
	# 5｜涨薪画饼
	{
		"messages": ["event_5_msg_1", "event_5_msg_2"],
		"options": [
			{"text": "event_5_opt_a", "stat": "efficiency", "amount": 2},
			{"text": "event_5_opt_b", "stat": "experience", "amount": 1},
		],
	},
	# 6｜空调坏了
	{
		"messages": ["event_6_msg_1", "event_6_msg_2"],
		"options": [
			{"text": "event_6_opt_a", "stat": "efficiency", "amount": 1},
			{"text": "event_6_opt_b", "stat": "efficiency", "amount": -1},
		],
	},
	# 7｜免费下午茶
	{
		"messages": ["event_7_msg_1", "event_7_msg_2"],
		"options": [
			{"text": "event_7_opt_a", "stat": "efficiency", "amount": 1},
			{"text": "event_7_opt_b", "stat": "quality", "amount": 1},
		],
	},
	# 8｜摸鱼被抓
	{
		"messages": ["event_8_msg_1", "event_8_msg_2"],
		"options": [
			{"text": "event_8_opt_a", "stat": "experience", "amount": 1},
			{"text": "event_8_opt_b", "stat": "efficiency", "amount": 2},
		],
	},
	# 9｜老板画大饼
	{
		"messages": ["event_9_msg_1", "event_9_msg_2"],
		"options": [
			{"text": "event_9_opt_a", "stat": "efficiency", "amount": 1},
			{"text": "event_9_opt_b", "stat": "quality", "amount": 1},
		],
	},
	# 10｜同事离职
	{
		"messages": ["event_10_msg_1", "event_10_msg_2"],
		"options": [
			{"text": "event_10_opt_a", "stat": "efficiency", "amount": 1},
			{"text": "event_10_opt_b", "stat": "efficiency", "amount": -1},
		],
	},
	# 11｜新人入职
	{
		"messages": ["event_11_msg_1", "event_11_msg_2"],
		"options": [
			{"text": "event_11_opt_a", "stat": "experience", "amount": 2},
			{"text": "event_11_opt_b", "stat": "efficiency", "amount": 1},
		],
	},
	# 12｜KPI 上调
	{
		"messages": ["event_12_msg_1", "event_12_msg_2"],
		"options": [
			{"text": "event_12_opt_a", "stat": "efficiency", "amount": 2},
			{"text": "event_12_opt_b", "stat": "quality", "amount": 1},
		],
	},
	# 13｜客户表扬
	{
		"messages": ["event_13_msg_1", "event_13_msg_2"],
		"options": [
			{"text": "event_13_opt_a", "stat": "quality", "amount": 2},
			{"text": "event_13_opt_b", "stat": "efficiency", "amount": 1},
		],
	},
	# 14｜网络卡顿
	{
		"messages": ["event_14_msg_1", "event_14_msg_2"],
		"options": [
			{"text": "event_14_opt_a", "stat": "efficiency", "amount": 1},
			{"text": "event_14_opt_b", "stat": "efficiency", "amount": -1},
		],
	},
	# 15｜强制晨会
	{
		"messages": ["event_15_msg_1", "event_15_msg_2"],
		"options": [
			{"text": "event_15_opt_a", "stat": "efficiency", "amount": 1},
			{"text": "event_15_opt_b", "stat": "experience", "amount": 1},
		],
	},
	# 16｜咖啡机
	{
		"messages": ["event_16_msg_1", "event_16_msg_2"],
		"options": [
			{"text": "event_16_opt_a", "stat": "efficiency", "amount": 2},
			{"text": "event_16_opt_b", "stat": "quality", "amount": 1},
		],
	},
	# 17｜背锅
	{
		"messages": ["event_17_msg_1", "event_17_msg_2"],
		"options": [
			{"text": "event_17_opt_a", "stat": "efficiency", "amount": 1},
			{"text": "event_17_opt_b", "stat": "quality", "amount": 1},
		],
	},
	# 18｜项目上线
	{
		"messages": ["event_18_msg_1", "event_18_msg_2"],
		"options": [
			{"text": "event_18_opt_a", "stat": "experience", "amount": 2},
			{"text": "event_18_opt_b", "stat": "efficiency", "amount": 2},
		],
	},
	# 19｜年终奖缩水
	{
		"messages": ["event_19_msg_1", "event_19_msg_2"],
		"options": [
			{"text": "event_19_opt_a", "stat": "efficiency", "amount": 1},
			{"text": "event_19_opt_b", "stat": "efficiency", "amount": -2},
		],
	},
	# 20｜弹性办公
	{
		"messages": ["event_20_msg_1", "event_20_msg_2"],
		"options": [
			{"text": "event_20_opt_a", "stat": "efficiency", "amount": 1},
			{"text": "event_20_opt_b", "stat": "quality", "amount": 2},
		],
	},
	# 21｜赶工大乱斗（长对话测试：6 条消息、多条很长，用来测换行和滚动）
	{
		"messages": [
			"event_21_msg_1", "event_21_msg_2", "event_21_msg_3",
			"event_21_msg_4", "event_21_msg_5", "event_21_msg_6",
		],
		"options": [
			{"text": "event_21_opt_a", "stat": "quality", "amount": 2},
			{"text": "event_21_opt_b", "stat": "efficiency", "amount": 2},
		],
	},
]

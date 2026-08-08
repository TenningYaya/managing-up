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
	{
		"messages": ["event_1_msg_1", "event_1_msg_2"],
		"options": [
			{"text": "event_1_opt_a", "stat": "efficiency", "amount": 1},   # 全体效率 +1
			{"text": "event_1_opt_b", "stat": "efficiency", "amount": -1},  # 全体效率 -1
		],
	},
	{
		"messages": ["event_2_msg_1", "event_2_msg_2"],
		"options": [
			{"text": "event_2_opt_a", "stat": "quality", "amount": 1},      # 全体质量 +1
			{"text": "event_2_opt_b", "stat": "efficiency", "amount": 1},   # 全体效率 +1
		],
	},
]

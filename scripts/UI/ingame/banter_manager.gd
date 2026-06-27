#banter_manager.gd
extends Node

# ==========================================
# 1. 吐槽台词库 (全部填入 CSV 的 Localization Key)
# ==========================================
const QUOTES = {
	"meeting_start": [
		"BANTER_MEET_START_1", "BANTER_MEET_START_2", "BANTER_MEET_START_3", "BANTER_MEET_START_4"
	],
	"meeting_end": [
		"BANTER_MEET_END_1", "BANTER_MEET_END_2", "BANTER_MEET_END_3", "BANTER_MEET_END_4"
	],
	"culture_change": [
		"BANTER_CULTURE_1", "BANTER_CULTURE_2", "BANTER_CULTURE_3", "BANTER_CULTURE_4"
	],
	"hired_ssr": [
		"BANTER_SSR_1", "BANTER_SSR_2", "BANTER_SSR_3", "BANTER_SSR_4"
	],
	"new_hire": [
		"BANTER_NEW_HIRE_01", "BANTER_NEW_HIRE_02", "BANTER_NEW_HIRE_03", "BANTER_NEW_HIRE_04", "BANTER_NEW_HIRE_05"
	],
	# [员工吐槽中心]:从等候区被拖动到工位上
	"seated": [
		"BANTER_SEATED_1", "BANTER_SEATED_2", "BANTER_SEATED_3", "BANTER_SEATED_4", "BANTER_SEATED_5", "BANTER_SEATED_6", "BANTER_SEATED_7"
	]
}

# ==========================================
# 2. 核心发射器：触发群体吐槽
# event_id: 事件名称（对应上面的字典的 key）
# count: 冒气泡的人数（默认随机2-3人）
# specific_pool: 如果提供，只让这批人吐槽（比如只让开会的人吐槽）
# ==========================================
func trigger_banter(event_id: String, count: int = 0, specific_pool: Array = []) -> void:
	if not QUOTES.has(event_id): return
	
	# 1. 确定人数 (如果没传，随机 2~3 个)
	var target_count = count if count > 0 else randi_range(2, 3)
	
	# 2. 拿到候选员工名单
	var candidates = []
	var pool = specific_pool if specific_pool.size() > 0 else get_tree().get_nodes_in_group("employees")
	
	for emp in pool:
		if not is_instance_valid(emp): continue   # 池里可能有已被释放(开除/退会)的员工,先挡住,否则调方法直接爆红
		if not emp.is_inside_tree(): continue
		if emp.is_slacking: continue # 摸鱼的没空吐槽
		if is_instance_valid(emp.get("_active_bubble")): continue # 头上已经有气泡的，不抢戏
		candidates.append(emp)
		
	# 3. 洗牌！防止老是前面几个人在说话
	candidates.shuffle()
	
	# 4. 提取对应的台词库并洗牌（保证这一次弹出的 3 句话绝不重复）
	var available_quotes = QUOTES[event_id].duplicate()
	available_quotes.shuffle()
	
	# 5. 开始发气泡！
	var actual_count = mini(target_count, candidates.size())
	actual_count = mini(actual_count, available_quotes.size()) # 确保台词够发
	
	var final_selected_emps = []
	var quote_index = 0
	
	# 🌟 修改：不再使用 range()，而是遍历所有候选人，直到挑够人数为止
	for emp in candidates:
		# 如果人数已经找够了，立刻下班
		if final_selected_emps.size() >= actual_count:
			break 
			
		# 🌟【防重叠核心检测】：挨个对比已经选中的人，看看离得近不近
		var too_close = false
		for selected in final_selected_emps:
			# 如果两人 X 轴距离小于 100 像素
			if abs(emp.global_position.x - selected.global_position.x) < 100:
				too_close = true
				break # 发现一个离得近的就不用往下比了
				
		# 如果太近了，就抛弃这个员工，直接看列表里的下一个人
		if too_close:
			continue 
			
		# 检查通过！正式录用！
		final_selected_emps.append(emp)
		
		var localized_text = tr(available_quotes[quote_index])
		
		if emp.has_method("_spawn_banter_bubble"):
			# 🌟 1. 核心需求：生成一个 0.0 到 3.0 秒之间的随机小数（比如 0.15s, 1.2s, 2.8s）
			var random_delay = randf_range(0.0, 1.0)
			
			# 🌟 2. 动态创建后台倒计时，时间到了自动触发冒泡
			# 它就像一个异步线程，每个人拿到的时间不同，互不打扰，绝不会卡住游戏
			get_tree().create_timer(random_delay).timeout.connect(func():
				# 🚨【生死锁】：因为最多会延迟 3 秒，万一在这 3 秒期间玩家正好把这个员工“优化”了呢？
				# 必须加上 is_instance_valid(emp) 判断，确认 3 秒后这个人还在内存里，防止爆红报错！
				if is_instance_valid(emp) and emp.has_method("_spawn_banter_bubble"):
					emp._spawn_banter_bubble(localized_text)
			)
		quote_index += 1

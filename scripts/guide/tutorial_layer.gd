# tutorial_layer.gd
extends CanvasLayer

# 🌟 在右侧编辑器里，把你建好的 tres 剧本文件按照顺序拖进这个数组里！
@export var steps: Array[TutorialStep] = []

@onready var dialogue_ui = $DialogueIntroUI
@onready var blocker_ui = $Blocker
@onready var tip_ui: Label = $TipUI # 或者你的 PanelContainer
@onready var end_label: Label = $FinishLabel # 假设你的 Label 叫这个，且它是 TutorialManager 的子节点

@onready var locked_ui_node: Node = null
var _global_flash_tween: Tween = null

var current_step_index: int = 0

# 用来记录当前正在监听的节点和信号，方便过关后“卸磨杀驴”断开连接
var current_target: Node = null
var current_signal_name: String = ""
var current_callable: Callable
var esc_hold_time := 0.0
var is_esc_pressing := false

var is_waiting_for_final_click := false


func _ready() -> void:
	# 1. 游戏一上来，第一时间藏起所有 UI，防止屏幕闪烁
	dialogue_ui.hide()
	blocker_ui.hide()
	tip_ui.hide()

	# 2. 🌟 核心魔法：强制暂停代码！让出控制权等下一帧
	# 这给了父节点 (Main) 足够的时间去执行它的 _ready() 并彻底完成 load_game()
	await get_tree().process_frame

	# 3. 此时 Main 已经读完档了，数据是最新的，再次检查大管家
	if Gamemanager.is_tutorial_completed:
		print("【TutorialLayer】读档确认教程已完成，直接拔管销毁！")
		queue_free()
		return

	# 4. 如果确实没完成（新游戏），则执行你原本真实的启动逻辑！
	if steps.size() > 0:
		play_step(0)
	else:
		printerr("老板，你还没往 TutorialManager 里塞剧本文件呢！")
# ==========================================
# 🧠 大脑核心：执行某一步骤
# ==========================================
func play_step(index: int) -> void:
	if index >= steps.size():
		_show_final_label()
		return
		
	current_step_index = index
	var step: TutorialStep = steps[current_step_index]
	
	print("正在执行教程第 ", index + 1, " 步：", TutorialStep.Type.keys()[step.step_type])
	
	if step.force_show_ui_group == "recruitment_panel":
		# 名字根据你项目的 Autoload 单例名来（假设你的单例叫 RecruitmentManager）
		if RecruitmentManager.has_method("load_tutorial_resumes"):
			RecruitmentManager.load_tutorial_resumes()
		
	if locked_ui_node and locked_ui_node.has_method("unlock_from_tutorial"):
		locked_ui_node.unlock_from_tutorial()
		locked_ui_node = null

	# 🌟 2. 检查这一步是否需要强行弹出某个界面
	if step.force_show_ui_group != "":
		var ui_node = get_tree().get_first_node_in_group(step.force_show_ui_group)
		if ui_node:
			ui_node.show() # 强行显示
			
			# 播提示音（你可以直接在这里播，或者让UI节点自己播）
			# AudioManager.play_se("tutorial_pop") 
			
			# 如果剧本要求控死它
			if step.lock_ui_lifecycle:
				locked_ui_node = ui_node
				if ui_node.has_method("lock_for_tutorial"):
					ui_node.lock_for_tutorial() # 开启“降智/霸体”模式
					
	match step.step_type:
		TutorialStep.Type.DIALOGUE:
			_handle_dialogue(step)
		TutorialStep.Type.FOCUS_CLICK:
			_handle_focus_click(step)
		TutorialStep.Type.WAIT_EVENT:
			_handle_wait_event(step)

# ==========================================
# 🎬 状态 1：处理纯对话
# ==========================================
func _handle_dialogue(step: TutorialStep) -> void:
	tip_ui.hide()
	
	# --- 🌟 新增的高亮与等待逻辑 ---
	if step.target_group != "":
		# 如果填了目标组名，找出节点并让黑布包围它
		var target = get_tree().get_first_node_in_group(step.target_group)
		if target:
			var target_rect = target.get_global_rect()
			blocker_ui.show()
			blocker_ui._arrange_curtains(target_rect)
			blocker_ui.hole_rect = target_rect
			# 【关键】告诉黑布：这个洞是纯视觉的，鼠标点不进去！
			blocker_ui.is_hole_clickable = false 
		else:
			printerr("KPI宝高亮失败：找不到组名 '", step.target_group, "' 的节点！")
			blocker_ui.hide()
	else:
		# 没填目标，就把黑布收起来，正常播对话
		blocker_ui.hide()
		
	# 如果配了等待时间，就让代码在这里挂起，让玩家干瞪眼看一会
	if step.delay_before_dialogue > 0.0:
		await get_tree().create_timer(step.delay_before_dialogue).timeout
	# --------------------------------
	
	# 时间到了，开始正常走你同学的对话 UI 逻辑
	current_target = dialogue_ui
	current_signal_name = "intro_dialogue_finished"
	current_callable = Callable(self, "_on_step_completed")
	
	dialogue_ui.intro_dialogue_finished.connect(current_callable)
	
	# 呼叫你同学的组件开始播片
	dialogue_ui.start_dialogue(step.dialogue_lines, step.dialogue_position, step.dialogue_offset_x, step.dialogue_offset_y, step.speaker)

# ==========================================
# 🎯 状态 2：处理强行挖洞点击
# ==========================================
func _handle_focus_click(step: TutorialStep) -> void:
	dialogue_ui.hide()
	
	if step.force_show_ui_group != "":
		var ui_node = get_tree().get_first_node_in_group(step.force_show_ui_group)
		if ui_node:
			if ui_node.has_method("lock_for_tutorial"):
				ui_node.lock_for_tutorial()
			else:
				ui_node.show() # 如果面板没有特殊的锁定逻辑，老老实实显示出来就行，别强求！
			# 🌟 关键：给展开动画留点时间，防止动画还没完就开始挖洞
			await get_tree().create_timer(0.5).timeout
			
	# 1. 抓取目标节点
	var target = get_tree().get_first_node_in_group(step.target_group)
	if not target:
		printerr("卡壳了！找不到组名为 '", step.target_group, "' 的节点！")
		return
		
	# 2. 呼叫 4 块黑布围攻这个目标
	var target_rect = target.get_global_rect()
	blocker_ui.show()
	blocker_ui._arrange_curtains(target_rect) # 调用你之前黑布脚本里的排布逻辑
	blocker_ui.hole_rect = target_rect        # 更新放行区域
	
	blocker_ui.is_hole_clickable = true
	
	if _global_flash_tween:
		_global_flash_tween.kill() # 干掉上一次的闪烁，防止套娃
	
	if target is Control:
		# 🌟【新增大小判定】：获取目标矩形的大小
		var rect_size = target.get_global_rect().size
		
		# 如果高亮区域的宽或高太大了（比如大于 300 像素），说明是大面板，直接不闪！
		if rect_size.x > 200 or rect_size.y > 200:
			print("【大总管】检测到目标是个庞然大物，为了老板的视力，关闭闪烁。")
			target.modulate.a = 1.0 # 确保它是完全亮起的就行
		else:
			# 只有小按钮才配享受呼吸灯待遇
			_global_flash_tween = create_tween().set_loops()
			_global_flash_tween.tween_property(target, "modulate:a", 0.2, 0.4)
			_global_flash_tween.tween_property(target, "modulate:a", 1.0, 0.4)
		
	# 3. 呼叫小字提示贴靠目标
	_arrange_tip(step, target_rect)
	
	# 4. 监听玩家点击目标的信号（比如 "pressed"）
	current_target = target
	current_signal_name = step.wait_signal
	current_callable = Callable(self, "_on_step_completed")
	
	# 🌟 替换区：加个防报错拦截！
	if current_signal_name == "all_preset_employees_hired":
		set_process(true) # 开启大总管雷达！不要去 target 上连信号！
	else:
		target.connect(current_signal_name, current_callable)

# ==========================================
# ⏳ 状态 3：处理纯逻辑等待 (支持高亮挖洞 + 禁用拒绝按钮)
# ==========================================
func _handle_wait_event(step: TutorialStep) -> void:
	# 1. 职场霸凌：强行灰掉所有拒绝按钮
	if step.disable_reject_buttons:
		var reject_btns = get_tree().get_nodes_in_group("reject_buttons")
		for btn in reject_btns:
			if btn is BaseButton:
				btn.disabled = true
	
	# 2. 视觉高亮：如果需要高亮整个面板（在 tres 里把 target_group 填为 recruitment_panel）
	if step.target_group != "":
		var target = get_tree().get_first_node_in_group(step.target_group)
		if target:
			var target_rect = target.get_global_rect()
			blocker_ui.show()
			blocker_ui._arrange_curtains(target_rect)
			blocker_ui.hole_rect = target_rect
			# 🌟 这里设置为 true，确保 YES 按钮可以被点到
			blocker_ui.is_hole_clickable = true 
	else:
		blocker_ui.hide()
	
	# 3. 挂起监听
	var target = get_tree().get_first_node_in_group(step.target_group)
	if target:
		current_target = target
		current_signal_name = step.wait_signal
		current_callable = Callable(self, "_on_step_completed")
		if current_signal_name == "all_colleagues_placed":
			print("【大总管】检测到 WAIT_EVENT 在等拖拽，开启 process 雷达，拦截物理连线。")
			set_process(true) # 确保雷达开着
		else:
			target.connect(current_signal_name, current_callable) # 正常信号才给连

# ==========================================
# 📍 小字位置计算逻辑 (支持自由像素微调！)
# ==========================================
func _arrange_tip(step: TutorialStep, target_rect: Rect2) -> void:
	if step.tip_text == "":
		tip_ui.hide()
		return
		
	tip_ui.text = step.tip_text
	tip_ui.show()
	
	# 等待一帧让 Label 根据文字自动撑开大小
	await get_tree().process_frame 
	
	var base_pos = Vector2.ZERO
	match step.tip_position:
		TutorialStep.TipPos.TOP:
			base_pos = Vector2(target_rect.position.x + (target_rect.size.x / 2.0) - (tip_ui.size.x / 2.0), target_rect.position.y - tip_ui.size.y - 10)
		TutorialStep.TipPos.BOTTOM:
			base_pos = Vector2(target_rect.position.x + (target_rect.size.x / 2.0) - (tip_ui.size.x / 2.0), target_rect.end.y + 10)
		TutorialStep.TipPos.LEFT:
			base_pos = Vector2(target_rect.position.x - tip_ui.size.x - 10, target_rect.position.y + (target_rect.size.y / 2.0) - (tip_ui.size.y / 2.0))
		TutorialStep.TipPos.RIGHT:
			base_pos = Vector2(target_rect.end.x + 10, target_rect.position.y + (target_rect.size.y / 2.0) - (tip_ui.size.y / 2.0))
			
	# 加上 Inspector 里的自由偏移量！
	tip_ui.global_position = Vector2(base_pos.x + step.tip_offset_x, base_pos.y + step.tip_offset_y)

func _on_step_completed() -> void:
	# 1. 每次点击，先停掉闪烁，复原透明度
	if _global_flash_tween:
		_global_flash_tween.kill()
		_global_flash_tween = null
		
	if current_target and current_target is Control:
		current_target.modulate.a = 1.0
	
	# 2. 🌟 核心拦截判定：如果是在等“招满三人”的步骤
	if current_signal_name == "all_preset_employees_hired":
		var remaining_count = RecruitmentManager.normal_pool.size()
		print("【大总管数人头】有员工入职了！当前简历池还剩：", remaining_count, " 人")
		
		# 只要池子里还有人，说明没招完
		if remaining_count > 0:
			print("【大总管】还没招满，继续留在第七步！")
			
			var target_panel = get_tree().get_first_node_in_group("recruitment_panel")
			if target_panel:
				blocker_ui._arrange_curtains(target_panel.get_global_rect())
				blocker_ui.hole_rect = target_panel.get_global_rect()
				blocker_ui.is_hole_clickable = true 
				
			return # 强行打断！
		else:
			# 🌟【移到这里】：只有在第七步判定真正通过、牛马全部抓齐时，才打印这句骚话！
			print("【大总管专用日志】3个预制牛马全部逮到！第七步完结！")
			
	# ====================================================
	# 3. 🌟 公共出口：任何步骤翻篇都会经过这里
	# ====================================================
	# 把这里的打印改成通用日志，这样前几步看着就正常了！
	print("【大总管】当前步骤 [", current_step_index + 1, "] 完成，正式拆线，进入下一步。")
	
	# 卸磨杀驴：断开当前的信号连接
	if current_target and current_target.has_signal(current_signal_name):
		current_target.disconnect(current_signal_name, current_callable)
	
	# 恢复所有拒绝按钮的禁用状态
	var reject_btns = get_tree().get_nodes_in_group("reject_buttons")
	for btn in reject_btns:
		if btn is BaseButton:
			btn.disabled = false
	
	# 继续下一步！
	play_step(current_step_index + 1)

func setup_tutorial_hiring():
	# 1. 这里填你的三个路径
	var paths = [
		"res://scenes/starter/tutorial_employees/tutemp1.tscn",
		"res://scenes/starter/tutorial_employees/tutemp2.tscn",
        "res://scenes/starter/tutorial_employees/tutemp3.tscn"
	]
	
	# 2. 清空并重新填入 RecruitmentManager 的队列
	RecruitmentManager.tutorial_recruits_queue.clear()
	
	for path in paths:
		var scene = load(path) # 这就是把路径变成 PackedScene 的魔法
		if scene:
			RecruitmentManager.tutorial_recruits_queue.append(scene)
			
	# 3. 告诉 Manager 执行加载
	RecruitmentManager.load_tutorial_resumes()

func _input(event: InputEvent) -> void:
	if is_waiting_for_final_click and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			queue_free()
			return # 销毁后就别执行后面的了
			
	# 🌟 修复后的 ESC 状态监听
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if event.pressed and not event.echo:
			is_esc_pressing = true  # 记录按下了
		elif not event.pressed:
			is_esc_pressing = false # 松开了
			esc_hold_time = 0.0     # 计时清零

func _process(delta: float) -> void:
	# 🌟 只要按下去了，就在每帧死磕累加时间
	if is_esc_pressing:
		esc_hold_time += delta
		if esc_hold_time >= 1.0: # 攒满1秒
			is_esc_pressing = false
			esc_hold_time = 0.0
			print("【教程跳过】长按满1秒，全局强行结束！")
			_finish_all_tutorials()
			
	if current_signal_name == "all_preset_employees_hired":
		# 盯着单例里的池子看
		if RecruitmentManager.normal_pool.size() == 0:
			print("【大总管雷达】牛马清零！自动放行！")
			current_signal_name = "" # 🌟 关掉雷达目标，防止每帧狂刷
			# 这里不要写 set_process(false)，因为你的 ESC 长按还需要它！
			_on_step_completed()     # 🌟 直接呼叫通关逻辑！
	
	if current_signal_name == "all_colleagues_placed":
		var working_count = 0
		
		# 直接去场景里抓所有员工（你在 employee.gd 的 _ready 里加了这个组）
		var all_emps = get_tree().get_nodes_in_group("employees")
		
		for emp in all_emps:
			# 安全读取：如果这个员工有 is_working 属性，并且是真的
			if "is_working" in emp and emp.is_working == true:
				working_count += 1
				
		# 如果打工的人达到了 3 个，通关！
		if working_count >= 3:
			print("【大总管雷达】3个牛马全部落座开工！拖拽教程圆满结束！")
			current_signal_name = "" # 🌟 关掉雷达
			_on_step_completed()     # 🌟 瞬间放行，拆线翻篇！
			
func _finish_all_tutorials() -> void:
	Gamemanager.is_tutorial_completed = true
	if SaveManager.has_method("save_game"):
		SaveManager.save_game()
		print("【教程】教程通关记录已保存到硬盘！")
		
	if _global_flash_tween:
		_global_flash_tween.kill()
		_global_flash_tween = null
		
	# 如果当前高亮的目标还在，强行复原它的透明度
	if current_target and current_target is Control:
		current_target.modulate.a = 1.0
	# 强制清理：断开所有逻辑，清空黑布
	if current_target and current_target.has_signal(current_signal_name):
		current_target.disconnect(current_signal_name, current_callable)
	
	# 彻底销毁教程 UI
	queue_free()

func _show_final_label() -> void:
	blocker_ui.hide()
	dialogue_ui.hide()
	tip_ui.hide()
	
	if locked_ui_node and locked_ui_node.has_method("unlock_from_tutorial"):
		locked_ui_node.unlock_from_tutorial()
		
	end_label.show() 
	
	# 等0.2秒防止点太快直接穿透
	await get_tree().create_timer(0.2).timeout
	# 🌟 打开终局开关，剩下的交给 _input 去管
	is_waiting_for_final_click = true

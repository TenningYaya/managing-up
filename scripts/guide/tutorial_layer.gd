# tutorial_layer.gd
extends CanvasLayer

# 🌟 在右侧编辑器里，把你建好的 tres 剧本文件按照顺序拖进这个数组里！
@export var steps: Array[TutorialStep] = []

@onready var dialogue_ui = $DialogueIntroUI
@onready var blocker_ui = $Blocker
@onready var tip_ui: Label = $TipUI # 或者你的 PanelContainer
@onready var end_label: Label = $FinishLabel # 假设你的 Label 叫这个，且它是 TutorialManager 的子节点

@onready var locked_ui_node: Node = null

var current_step_index: int = 0

# 用来记录当前正在监听的节点和信号，方便过关后“卸磨杀驴”断开连接
var current_target: Node = null
var current_signal_name: String = ""
var current_callable: Callable
var esc_hold_time := 0.0

var is_waiting_for_final_click := false


func _ready() -> void:
	# 游戏一上来，把所有教程组件都藏起来
	dialogue_ui.hide()
	blocker_ui.hide()
	tip_ui.hide()
	
	# 如果数组里有剧本，就开始播放第一步！
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
		print("【抓鬼行动】大总管到底找没找到 Sidebar？结果是：", ui_node)
		if ui_node:
			ui_node.lock_for_tutorial() # 触发 Sidebar 展开
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
	
	# 3. 呼叫小字提示贴靠目标
	_arrange_tip(step, target_rect)
	
	# 4. 监听玩家点击目标的信号（比如 "pressed"）
	current_target = target
	current_signal_name = step.wait_signal
	current_callable = Callable(self, "_on_step_completed")
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
		target.connect(current_signal_name, current_callable)

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

# ==========================================
# 🏁 某一步完成时的统一出口
# ==========================================
func _on_step_completed() -> void:
	# 1. 卸磨杀驴：断开当前的信号连接，防止重复触发
	if current_target and current_target.has_signal(current_signal_name):
		current_target.disconnect(current_signal_name, current_callable)
	
	var reject_btns = get_tree().get_nodes_in_group("reject_buttons")
	for btn in reject_btns:
		if btn is BaseButton:
			btn.disabled = false
	
	# 3. 继续下一步！
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
			
	# 监听 ESC 长按
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if event.pressed:
			esc_hold_time += get_process_delta_time()
			if esc_hold_time >= 1.0: # 按住1秒跳过
				print("【教程跳过】强制结束所有流程")
				_finish_all_tutorials()
		else:
			esc_hold_time = 0.0

func _finish_all_tutorials() -> void:
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

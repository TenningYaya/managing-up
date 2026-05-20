# tutorial_manager.gd
extends CanvasLayer

# 🌟 在右侧编辑器里，把你建好的 tres 剧本文件按照顺序拖进这个数组里！
@export var steps: Array[TutorialStep] = []

@onready var dialogue_ui = $DialogueIntroUI
@onready var blocker_ui = $Blocker
@onready var tip_ui: Label = $TipUI # 或者你的 PanelContainer

var current_step_index: int = 0

# 用来记录当前正在监听的节点和信号，方便过关后“卸磨杀驴”断开连接
var current_target: Node = null
var current_signal_name: String = ""
var current_callable: Callable

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
		print("🎉 新手教程全部通关！")
		queue_free() # 教程结束，自我销毁释放内存
		return
		
	current_step_index = index
	var step: TutorialStep = steps[current_step_index]
	
	print("正在执行教程第 ", index + 1, " 步：", TutorialStep.Type.keys()[step.step_type])
	
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
	blocker_ui.hide()
	tip_ui.hide()
	
	# 监听你同学 UI 发出的完毕信号
	current_target = dialogue_ui
	current_signal_name = "intro_dialogue_finished"
	current_callable = Callable(self, "_on_step_completed")
	
	dialogue_ui.intro_dialogue_finished.connect(current_callable)
	
	# 呼叫你同学的组件开始播片
	dialogue_ui.start_dialogue(step.dialogue_lines, step.dialogue_position, step.dialogue_offset_x, step.dialogue_offset_y)

# ==========================================
# 🎯 状态 2：处理强行挖洞点击
# ==========================================
func _handle_focus_click(step: TutorialStep) -> void:
	dialogue_ui.hide()
	
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
	blocker_ui.is_tutorial_finished = false
	
	# 3. 呼叫小字提示贴靠目标
	_arrange_tip(step, target_rect)
	
	# 4. 监听玩家点击目标的信号（比如 "pressed"）
	current_target = target
	current_signal_name = step.wait_signal
	current_callable = Callable(self, "_on_step_completed")
	target.connect(current_signal_name, current_callable)

# ==========================================
# ⏳ 状态 3：处理纯逻辑等待
# ==========================================
func _handle_wait_event(step: TutorialStep) -> void:
	# 隐藏所有教程 UI，放开全屏让玩家自由操作
	dialogue_ui.hide()
	blocker_ui.hide()
	tip_ui.hide()
	
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
	
	# 2. （未来可以在这里加上一句 SaveManager 的代码保存进度）
	
	# 3. 继续下一步！
	play_step(current_step_index + 1)

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
var current_callable_ghost: Callable

var current_step_index: int = 0
var yes_click_count: int = 0

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
	
	# ====================================================
	# 🌟【大总管全场员工总闸管理】
	# ====================================================
	if "disable_employee_interaction" in step:
		Gamemanager.is_employee_interaction_disabled = step.disable_employee_interaction
		print("【大总管总闸】当前步骤设定：禁用员工互动 = ", step.disable_employee_interaction)
			
	if step.force_show_ui_group == "recruitment_panel":
		# 名字根据你项目的 Autoload 单例名来（假设你的单例叫 RecruitmentManager）
		if RecruitmentManager.has_method("load_tutorial_resumes"):
			RecruitmentManager.load_tutorial_resumes()
		
	if locked_ui_node and locked_ui_node.has_method("unlock_from_tutorial"):
		locked_ui_node.unlock_from_tutorial()
		locked_ui_node = null

# ==== 修改这里：加入 Cleanup（清理）逻辑 ====
	if locked_ui_node:
			if locked_ui_node.has_method("unlock_from_tutorial"):
				locked_ui_node.unlock_from_tutorial()
			# 强行隐藏上一关遗留的 Node 界面！
			locked_ui_node.hide() 
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
# ==========================================
# 🎬 状态 1：处理纯对话（核心调度总闸，变短了！）
# ==========================================
func _handle_dialogue(step: TutorialStep) -> void:
	tip_ui.hide()
	
	# ====================================================
	# 🌟【大总管全场员工总闸管理】
	# ====================================================
	if "disable_employee_interaction" in step:
		Gamemanager.is_employee_interaction_disabled = step.disable_employee_interaction
		print("【大总管总闸】当前步骤设定：禁用员工互动 = ", step.disable_employee_interaction)
		
	# 1. 弹出面板的等待缓冲
	if step.force_show_ui_group != "":
		await get_tree().create_timer(0.2).timeout
		
	# 2. 抽出小函数：处理黑布和钢化玻璃保护罩
	_apply_dialogue_highlight_and_shield(step)
	
	# 3. 🌟 抽出小函数：专门生截图（带疯狂 Debug 日志）
	_spawn_illustration_if_presents(step)
	
	# 4. 延迟挂起
	if step.delay_before_dialogue > 0.0:
		await get_tree().create_timer(step.delay_before_dialogue).timeout
	
	# 5. 建立连线，通知你同学的组件开始播台词
	current_target = dialogue_ui
	current_signal_name = "intro_dialogue_finished"
	current_callable = Callable(self, "_on_step_completed")
	
	dialogue_ui.intro_dialogue_finished.connect(current_callable)
	dialogue_ui.start_dialogue(step.dialogue_lines, step.dialogue_position, step.dialogue_offset_x, step.dialogue_offset_y, step.speaker)


# ====================================================
# 📦 拆分出来的对话期小功能魔盒（通通挂在上面主函数底下）
# ====================================================

## 子功能 A：管理黑布挖洞与钢化玻璃物理隔绝
func _apply_dialogue_highlight_and_shield(step: TutorialStep) -> void:
	if step.target_group != "":
		var target = get_tree().get_first_node_in_group(step.target_group)
		if target:
			var target_rect = target.get_global_rect()
			blocker_ui.show()
			blocker_ui._arrange_curtains(target_rect)
			blocker_ui.hole_rect = target_rect
			blocker_ui.is_hole_clickable = false 
			
			# 如果没有玻璃，原地生成玻璃阻挡交互
			if not has_node("TutorialGlassShield"):
				var glass = Control.new()
				glass.name = "TutorialGlassShield"
				glass.global_position = target_rect.position
				glass.size = target_rect.size
				glass.mouse_filter = Control.MOUSE_FILTER_STOP 
				add_child(glass)
		else:
			printerr("KPI宝高亮失败：找不到组名 '", step.target_group, "' 的节点！")
			blocker_ui.hide()
	else:
		blocker_ui.hide()


## 子功能 B：🌟 截图生成器（带显形追踪雷达）
func _spawn_illustration_if_presents(step: TutorialStep) -> void:
	if step.illustration_texture == null:
		return # 没配图就直接滚粗，不废话
	
	var img_rect = TextureRect.new()
	img_rect.name = "TutorialScreenshot" 
	img_rect.texture = step.illustration_texture
	# 🌟 核心改动 1：既然图片真实尺寸很小，我们把它改成强行拉伸填充，别居中缩放了！
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.stretch_mode = TextureRect.STRETCH_SCALE # 强行平铺拉满方框
	img_rect.size = Vector2(500, 350) # 👈 物理体积直接放大，不信看不见它！
	
	# 🌟 核心改动 2：干掉 top_level，直接把图片挂在整个大总管的最上面（后渲染才能压住黑布）
	# 不写 img_rect.top_level = true 了
	img_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 算居中坐标（保持原样）
	var screen_size = get_viewport().get_visible_rect().size
	var center_x = (screen_size.x / 2.0) - (img_rect.size.x / 2.0)
	var center_y = (screen_size.y / 2.0) - (img_rect.size.y / 2.0) - 100 
	img_rect.global_position = Vector2(center_x, center_y) + step.illustration_offset
	
	# 🌟 核心改动 3：【重点】如果你脚本里有 blocker_ui（黑布）
	# 我们直接把图片 add_child 到黑布的下面！让黑布当它的垫脚石，它绝对能在最外层亮瞎眼！
	if has_node("Blocker"):
		get_node("Blocker").add_child(img_rect)
	else:
		add_child(img_rect)

# ==========================================
# 🎯 状态 2：处理强行挖洞点击
# ===========================play_step(current_step_index + 1)===============
func _handle_focus_click(step: TutorialStep) -> void:
	dialogue_ui.hide()
	
	# 1. 强行把页面显示出来
	if step.force_show_ui_group != "":
		var ui_node = get_tree().get_first_node_in_group(step.force_show_ui_group)
		if ui_node:
			if ui_node.has_method("lock_for_tutorial"):
				ui_node.lock_for_tutorial()
			else:
				ui_node.show()
				
	await get_tree().create_timer(0.2).timeout
			
	# 2. 抓取目标按钮
	var target = get_tree().get_first_node_in_group(step.target_group)
	if not target:
		printerr("卡壳了！找不到组名为 '", step.target_group, "' 的节点！")
		return
		
	var wait_timeout = 0.0
	while not target.is_visible_in_tree() and wait_timeout < 2.0:
		# 如果按钮还没在屏幕上可见（说明动画没完或者爹还没show完），强行等一帧再看！
		await get_tree().process_frame
		wait_timeout += 0.016 # 累计时间，防止死循环卡死游戏
		
	# 动画可能刚完，额外给 0.1 秒让它的物理坐标 (Global Rect) 彻底在当前帧刷新、停稳
	await get_tree().create_timer(0.1).timeout
	
	# 此时拿到的坐标，绝对是它滑入完成后的【真·人间坐标】！
	var target_rect = target.get_global_rect()
	
	print("【大总管雷达】体检报告修正版：")
	print(" -> 真正可见状态：", target.is_visible_in_tree())
	print(" -> 停稳后的物理矩形：", target_rect)
	
	# 3. 呼叫黑布挖洞
	blocker_ui.show()
	blocker_ui._arrange_curtains(target_rect) 
	blocker_ui.hole_rect = target_rect        
	blocker_ui.is_hole_clickable = true
	
	# 🌟【硬核补丁 3】：图层刺穿！
	# 为了防止按钮被黑布无脑压住，我们利用 CanvasItem 的 z_index 或者是强行把按钮的渲染层级提到黑布前面
	if target is Control:
		target.z_index = 999 # 强行把这个升级按钮的层级踢到天界！
		target.z_as_relative = false # 不继承手机老爹那卑微的层级
		
		# 顺便处理闪烁
		var rect_size = target_rect.size
		if rect_size.y <= 200:
			if _global_flash_tween: _global_flash_tween.kill()
			_global_flash_tween = create_tween().set_loops()
			_global_flash_tween.tween_property(target, "modulate:a", 0.3, 0.4)
			_global_flash_tween.tween_property(target, "modulate:a", 1.0, 0.4)
	
	# 4. 呼叫小字提示
	_arrange_tip(step, target_rect)
	
	# 5. 挂载物理连线，静静等待玩家点击翻篇
	current_target = target
	current_signal_name = step.wait_signal
	current_callable = Callable(self, "_on_step_completed")
	
	if current_signal_name == "all_preset_employees_hired":
		set_process(true) 
	else:
		# 🌟【硬核防御补丁】：先检查这个节点身上到底有没有这个信号！
		if target.has_signal(current_signal_name):
			if target.is_connected(current_signal_name, current_callable):
				target.disconnect(current_signal_name, current_callable)
			target.connect(current_signal_name, current_callable)
			print("【大总管】成功与节点 [", target.name, "] 建立物理信号线：", current_signal_name)
		else:
			# 💥 抓到现行：如果是个普通的 Control 且你填了 pressed，我们用系统的 gui_input 悄悄借尸还魂！
			if current_signal_name == "pressed" and target is Control:
				print("【大总管物理破局】检测到目标 [", target.name, "] 不是按钮但要求点击！强行植入 gui_input 监听...")
				
				# 借用 Control 的 gui_input 信号，当有鼠标事件触发时，我们内部判断是不是点击
				var gui_input_callable = func(event: InputEvent):
					if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
						print("【大总管】成功拦截到玩家在普通面板上的物理左键点击！翻篇！")
						# 别忘了把这层临时连线给断了，免得污染后续业务
						if target.is_connected("gui_input", current_callable_ghost):
							target.disconnect("gui_input", current_callable_ghost)
						_on_step_completed()
						
				# 存个临时变量方便等会儿注销
				current_callable_ghost = gui_input_callable 
				target.gui_input.connect(gui_input_callable)
			else:
				# 如果既没有信号，也不是 pressed，直接打印显眼报错并强行放行，绝不让游戏死锁！
				printerr("【大总管严重警告】节点 '", target.name, "' 压根没有 '", current_signal_name, "' 信号！已强行跳过此步防卡死！")
				_on_step_completed()

func _handle_wait_event(step: TutorialStep) -> void:
	# 1. 职场霸凌：强行灰掉所有拒绝按钮
	_disable_reject_buttons_if_needed(step)
	
	# 2. 视觉高亮：让黑布去目标区域挖洞
	_apply_wait_event_highlight(step)
	
	# 3. 🌟 关卡分流闸门：根据不同暗号，各回各家，各找各妈
	if step.illustration_texture != null:
		_setup_illustration_step(step)
		return # 带图关卡，到此为止
		
	var target = get_tree().get_first_node_in_group(step.target_group)
	if not target:
		return # 找不到节点，直接断后，防止崩溃
		
	current_target = target
	current_signal_name = step.wait_signal
	current_callable = Callable(self, "_on_step_completed")
	
	match current_signal_name:
		"tutorial_click_specific_employee":
			_setup_specific_employee_click_step()
			
		"all_colleagues_placed", "employee_panel_opened":
			_setup_radar_step()
			
		_:
			# 🌟 只有真正老实本分的普通 Godot 信号，才配走到这里连物理线
			target.connect(current_signal_name, current_callable)


# ====================================================
# 📦 拆分出来的专属功能小魔盒（通通贴在主函数下面）
# ====================================================

## 子函数 1：禁用拒绝按钮
func _disable_reject_buttons_if_needed(step: TutorialStep) -> void:
	if step.disable_reject_buttons:
		var reject_btns = get_tree().get_nodes_in_group("reject_buttons")
		for btn in reject_btns:
			if btn is BaseButton:
				btn.disabled = true

## 子函数 2：处理常规高亮挖洞
func _apply_wait_event_highlight(step: TutorialStep) -> void:
	if step.target_group != "":
		var target = get_tree().get_first_node_in_group(step.target_group)
		if target:
			var target_rect = target.get_global_rect()
			blocker_ui.show()
			blocker_ui._arrange_curtains(target_rect)
			blocker_ui.hole_rect = target_rect
			blocker_ui.is_hole_clickable = true 
	else:
		blocker_ui.hide()

## 子函数 3：第 20 步 - 弹属性截图与无敌叉号
func _setup_illustration_step(step: TutorialStep) -> void:
	print("【大总管】发现剧本带图！开始部署截图和关闭按钮...")
	current_target = null
	current_signal_name = step.wait_signal
	
	var img_rect = TextureRect.new()
	img_rect.name = "TutorialScreenshot"
	img_rect.texture = step.illustration_texture
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img_rect.size = Vector2(300, 200) 
	img_rect.global_position = dialogue_ui.global_position + Vector2(0, -220) + step.illustration_offset
	add_child(img_rect)
	
	var close_btn = Button.new()
	close_btn.name = "TutorialCloseBtn"
	close_btn.text = " X "
	close_btn.size = Vector2(30, 30)
	close_btn.position = Vector2(img_rect.size.x - 25, -10)
	img_rect.add_child(close_btn)
	
	close_btn.pressed.connect(func():
		print("【大总管】玩家点击了叉号，图片教学结束！")
		img_rect.queue_free() 
		_on_step_completed()  
	)

## 子函数 4：第 9 步 - 疯狂连点特定员工关卡（白框+隐身黑布）
func _setup_specific_employee_click_step() -> void:
	print("【大总管】启动透明护盾 + 白框锁定模式！")
	var employees = get_tree().get_nodes_in_group("employees")
	if employees.size() > 0:
		current_target = employees[0] 
		var target_rect = current_target.get_global_rect()
		
		blocker_ui.modulate.a = 0.0 
		blocker_ui._arrange_curtains(target_rect)
		blocker_ui.hole_rect = target_rect
		blocker_ui.is_hole_clickable = true 
		
		var frame = ReferenceRect.new()
		frame.name = "TutorialWhiteFrame"
		frame.border_color = Color.WHITE
		frame.border_width = 4.0
		frame.editor_only = false
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE 
		frame.global_position = target_rect.position
		frame.size = target_rect.size
		add_child(frame)

## 子函数 5：第 7、8 步 - 启动后台盯梢雷达
func _setup_radar_step() -> void:
	print("【大总管】捕捉到后台数据暗号 [", current_signal_name, "]，开启雷达，拒绝物理连线。")
	set_process(true)
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
	
	blocker_ui.hide()
	
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
	
	var glass = get_node_or_null("TutorialGlassShield")
	if glass:
		glass.queue_free()
	# 继续下一步！
	play_step(current_step_index + 1)
	
	# 1. 尝试清理直接挂在外面的图片
	var screenshot = get_node_or_null("TutorialScreenshot")
	if screenshot:
		screenshot.queue_free()
		
	# 2. ==== 新加的清理代码：使用明确的 Path（路径）去黑布上撕贴纸 ====
	var screenshot_on_blocker = get_node_or_null("Blocker/TutorialScreenshot")
	if screenshot_on_blocker:
		screenshot_on_blocker.queue_free()
	
	if current_target and is_instance_valid(current_target) and "z_index" in current_target:
		current_target.z_index = 0
		current_target.z_as_relative = true
		
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
	if current_signal_name == "tutorial_click_specific_employee":
		# 严格判定：必须是鼠标事件 + 左键 + 按下的那一瞬间
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			
			# 确保当前目标还活着
			if current_target and is_instance_valid(current_target):
				# 极其严谨的包围盒检测：哪怕透明遮罩放行了，也必须点在肉体上才算！
				if current_target.get_global_rect().has_point(event.global_position):
					
					yes_click_count += 1
					print("【大总管催促】精准命中！已点击：", yes_click_count, "/5 次")
					
					# 💎 附赠极致爽感：每次点中，让白框闪烁一下给予反馈！
					var frame = get_node_or_null("TutorialWhiteFrame")
					if frame:
						var tween = create_tween()
						tween.tween_property(frame, "modulate:a", 0.2, 0.05)
						tween.tween_property(frame, "modulate:a", 1.0, 0.05)
					
					# 点满 5 次，直接结案！
					if yes_click_count >= 5:
						print("【大总管】连点任务完成！准备拆线！")
						current_signal_name = "" 
						yes_click_count = 0 
						
						# 🌟 关键：走之前把场景打扫干净
						blocker_ui.modulate.a = 1.0 # 把黑布的透明度恢复，防止影响下一关
						if frame:
							frame.queue_free()      # 把白框销毁
							
						_on_step_completed()        # 丝滑翻篇！
						
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
		
	if current_signal_name == "employee_panel_opened":
		# 抓取你的面板（你 employee.gd 里写了找 employee_panel 组）
		var panel = get_tree().get_first_node_in_group("employee_panel")
		
		# is_visible_in_tree() 会精准判断这个 UI 目前是不是在屏幕上真实显示着
		if panel and panel.is_visible_in_tree():
			print("【大总管雷达】捕捉到员工面板已弹出！右键教学通关！")
			current_signal_name = "" # 关掉雷达
			_on_step_completed()     # 瞬间放行！
	
	if not is_instance_valid(current_target) or not current_target.is_visible_in_tree():
		return
		
	# 每一帧都重新抓取按钮在这一蝇秒的真实绝对位置
	var real_rect = current_target.get_global_rect()
	
	# 如果它终于进到屏幕里了（X坐标小于屏幕宽度，且体积不为0）
	if real_rect.position.x < get_viewport().get_visible_rect().size.x and real_rect.size.x > 0:
		blocker_ui.show()
		blocker_ui._arrange_curtains(real_rect)
		blocker_ui.hole_rect = real_rect
		blocker_ui.is_hole_clickable = true
		
		# 顺便给它拔高层级，不让它被黑幕盖住
		if "z_index" in current_target:
			current_target.z_index = 999
			current_target.z_as_relative = false
			
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
	Gamemanager.is_employee_interaction_disabled = false
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

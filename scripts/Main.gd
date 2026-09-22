class_name Main
extends Node2D
## 场景调度：开始界面 -> 关卡选择（5 张卡）-> 择战甲（四选二）-> 关卡 -> 结算
##
## 界面之间互不认识：Main 只负责 `_clear()` + 新建 + 连信号，
## 界面一律用 `signal xxx_pressed` / `back_pressed` 上报。
## 关卡号走 `Game.current_stage` 跨界面传递；`Level.stage` **必须在 add_child 之前**注入
## （`Level._ready()` 里就 `_start()`，晚一步就打成了第 1 关）。

var current: Node = null


func _ready() -> void:
	randomize()
	show_title()


func _clear() -> void:
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = null


## 开始界面：开始游戏 / 战甲库 / 作战手册
func show_title() -> void:
	_clear()
	get_tree().paused = false
	var s := TitleScreen.new()
	current = s
	add_child(s)
	s.start_pressed.connect(show_stage)
	s.gallery_pressed.connect(show_gallery)
	s.help_pressed.connect(show_help)


## 战甲库：翻阅四件战甲
func show_gallery() -> void:
	_clear()
	var s := ArmorGallery.new()
	current = s
	add_child(s)
	s.back_pressed.connect(show_title)


## 作战手册
func show_help() -> void:
	_clear()
	var s := HelpScreen.new()
	current = s
	add_child(s)
	s.back_pressed.connect(show_title)


## 关卡选择：五关卡片（只放行已解锁的关）
func show_stage() -> void:
	_clear()
	var s := StageSelect.new()
	current = s
	add_child(s)
	s.start_pressed.connect(_on_stage_picked)
	s.back_pressed.connect(show_title)


## 关卡选择 -> 记下关号 -> 择战甲
func _on_stage_picked(stage: int) -> void:
	Game.current_stage = clampi(stage, 1, StageCfg.STAGE_N)
	show_select()


## 择战甲：四选二
func show_select() -> void:
	_clear()
	var s := ArmorSelect.new()
	current = s
	add_child(s)
	s.start_pressed.connect(start_level)
	s.back_pressed.connect(show_stage)


func start_level() -> void:
	_clear()
	var s := Level.new()
	s.stage = Game.current_stage     # ★ 必须在 add_child 之前
	current = s
	add_child(s)
	s.finished.connect(show_result)
	s.restart_requested.connect(restart_level)


func show_result(_win: bool) -> void:
	_clear()
	get_tree().paused = false
	var s := ResultScreen.new()
	s.win = Game.result_win
	s.stage = Game.current_stage
	current = s
	add_child(s)
	s.again_pressed.connect(start_level)
	s.stage_pressed.connect(show_stage)
	s.swap_pressed.connect(show_select)   # 保留当前关卡，直接回择战甲界面
	s.next_pressed.connect(_on_next_stage)


## 结算 -> 「下一关」：关号 +1 直接推进（战甲沿用本局的两件）
func _on_next_stage() -> void:
	Game.current_stage = clampi(Game.current_stage + 1, 1, StageCfg.STAGE_N)
	start_level()


func restart_level() -> void:
	get_tree().paused = false
	start_level()

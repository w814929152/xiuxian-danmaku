class_name Main
extends Node2D
## 场景调度：开始界面 ->（道袍库 / 游戏说明 | 择难度 -> 择道袍）-> 关卡 -> 结算

var current: Node = null


func _ready() -> void:
	randomize()
	show_title()


func _clear() -> void:
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = null


## 开始界面：开始游戏 / 道袍库 / 游戏说明
func show_title() -> void:
	_clear()
	get_tree().paused = false
	var s := TitleScreen.new()
	current = s
	add_child(s)
	s.start_pressed.connect(show_difficulty)
	s.gallery_pressed.connect(show_gallery)
	s.help_pressed.connect(show_help)


## 道袍库：翻阅四件道袍
func show_gallery() -> void:
	_clear()
	var s := RobeGallery.new()
	current = s
	add_child(s)
	s.back_pressed.connect(show_title)


## 游戏说明
func show_help() -> void:
	_clear()
	var s := HelpScreen.new()
	current = s
	add_child(s)
	s.back_pressed.connect(show_title)


## 择难度：简单 / 普通 / 困难
func show_difficulty() -> void:
	_clear()
	var s := DifficultySelect.new()
	current = s
	add_child(s)
	s.start_pressed.connect(show_select)
	s.back_pressed.connect(show_title)


## 择道袍：四选二
func show_select() -> void:
	_clear()
	var s := RobeSelect.new()
	current = s
	add_child(s)
	s.start_pressed.connect(start_level)
	s.back_pressed.connect(show_difficulty)


func start_level() -> void:
	_clear()
	var s := Level.new()
	current = s
	add_child(s)
	s.finished.connect(show_result)
	s.restart_requested.connect(restart_level)


func show_result(_win: bool) -> void:
	_clear()
	get_tree().paused = false
	var s := ResultScreen.new()
	s.win = Game.result_win
	current = s
	add_child(s)
	s.again_pressed.connect(start_level)
	s.title_pressed.connect(show_title)
	s.swap_pressed.connect(show_select)   # 保留当前难度，直接回择袍界面


func restart_level() -> void:
	get_tree().paused = false
	start_level()

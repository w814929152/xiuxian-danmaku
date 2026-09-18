class_name Level
extends Node2D
## 关卡流程：三波妖潮 -> 血魔老祖
## 第 2 / 第 3 重妖潮以【护法妖将】压轴（Elite.gd，属性法罡逼玩家临阵换袍）
## 道具两个来源：斩妖按概率掉落（DROP_CHANCE）+ 每波结束刷新 WAVE_DROP 个
##   斩妖将另有保底一件（_on_elite_killed）
## 波次结束**不再回血** —— 元神只靠回春丹补

## 关卡结束（胜 / 负）—— 由 Main 连接，Level 不反向找 Main
signal finished(win: bool)
## 玩家请求重来本关（转发自 HUD）
signal restart_requested()

## 击杀小妖的掉落概率（实测：2000 次击杀掉落 373 次 = 18.65%，与配置一致）
const DROP_CHANCE := 0.18
## 每波妖潮结束后额外刷新的道具数（每局固定 3 个）
const WAVE_DROP := 1

var player: Player = null
var boss: Boss = null
var hud: HUD = null
var bg: Background = null
var score: int = 0
var wave_text: String = "入 境"
var paused: bool = false
var _running: bool = false


func _ready() -> void:
	bg = Background.new()
	add_child(bg)

	player = Player.new()
	player.world = self
	player.robes = []
	for c in Game.picked_robes:
		player.robes.append(int(c))
	add_child(player)
	player.player_died.connect(_on_player_died)

	hud = HUD.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	hud.bind(player)
	hud.pause_toggled.connect(_on_pause_toggled)
	hud.restart_requested.connect(_on_restart_requested)

	_start()


func _start() -> void:
	_running = true
	_run()


func wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout


# ---------------------------------------------------------------- 流程
func _run() -> void:
	hud.show_banner("第 一 重 · 妖潮来袭",
		"%s 难度 · WASD/方向键 移动 · J 或 鼠标左键 御剑 · 空格 更换道袍" % Game.diff_name(),
		2.6)
	await wait(2.0)
	if not _running:
		return

	await _wave(1, 5, 1.0)
	if not _running:
		return
	_drop_wave()
	hud.show_banner("第二重 · 四色齐至", "同色飞剑伤害 + 50%", 1.8)
	await wait(1.3)
	if not _running:
		return

	await _wave(2, 7, 1.15, true)
	if not _running:
		return
	_drop_wave()
	hud.show_banner("第三重 · 妖王先锋", "玄冰妖速度极快，注意走位", 1.8)
	await wait(1.2)
	if not _running:
		return

	await _wave(3, 8, 1.3, true)
	if not _running:
		return
	_drop_wave()
	hud.show_banner("血魔老祖 · 现世", "法罩开启时 —— 唯有同色飞剑可破，随时更换道袍", 2.8)
	await wait(1.8)
	if not _running:
		return
	await _boss_fight()


# ---------------------------------------------------------------- HUD 数据
## 分数与波次文字统一走这里推送给 HUD —— HUD 不反向读 Level
func _add_score(v: int) -> void:
	score += v
	if hud != null:
		hud.set_score(score)


func _set_wave(s: String) -> void:
	wave_text = s
	if hud != null:
		hud.set_wave(s)


# ---------------------------------------------------------------- 输入回调
func _on_pause_toggled(v: bool) -> void:
	paused = v
	get_tree().paused = v


func _on_restart_requested() -> void:
	get_tree().paused = false
	restart_requested.emit()


## [param elite] 本波是否以【护法妖将】压轴（第 2 / 第 3 重各一只）
func _wave(n: int, count: int, scale: float, elite := false) -> void:
	_set_wave("第 %d 重 · 妖潮" % n)
	for i in count:
		if not _running:
			return
		_spawn_enemy(scale)
		await wait(0.62)
	if elite:
		await wait(0.5)
		if not _running:
			return
		_spawn_elite(scale)
	# 等待清场。精英是硬性门槛 —— 小妖可以剩最后一只不等，妖将没斩就别想进下一重。
	# 上限放宽到 26 秒：斩一只妖将约 8~12 秒，14 秒的窗口会把它卡在半路。
	var limit := 26.0 if elite else 14.0
	var guard := 0.0
	while _running and guard < limit:
		await wait(0.3)
		guard += 0.3
		if _enemy_count() <= 1 and not _elite_alive():
			break


func _spawn_enemy(scale: float) -> void:
	var c: int = randi() % 4
	var pats := ["sine", "straight", "hover", "dive"]
	var pat: String = pats[randi() % pats.size()]
	var y := randf() * (Game.VIEW_H - 180.0) + 90.0
	var e := Enemy.new()
	e.world = self
	add_child(e)
	e.player_ref = player
	e.setup(c, pat, y, scale)
	e.killed.connect(_on_enemy_killed)


func _enemy_count() -> int:
	var n := 0
	for ch in get_children():
		if ch is Enemy:
			n += 1
	return n


## 场上是否还有活着的护法妖将（清场判定用）
func _elite_alive() -> bool:
	for ch in get_children():
		if ch is Elite and not (ch as Elite).dead:
			return true
	return false


## 压轴：护法妖将。法罡色由 Elite 自己从玩家道袍里抽 —— 保证一定破得了
func _spawn_elite(scale: float) -> void:
	var e := Elite.new()
	e.world = self
	add_child(e)
	e.player_ref = player
	e.player_robes = player.robes
	e.setup(scale, randf() * (Game.VIEW_H - 300.0) + 150.0)
	e.killed.connect(_on_elite_killed)
	hud.show_banner("护 法 妖 将",
		"身披【%s】法罡 —— 换上同色道袍方可速破" % Game.COLOR_CN[e.color], 2.2)


## 斩妖将：厚赏 + 必掉一件道具（斩它是有代价的，不能让人空手）
func _on_elite_killed(pos: Vector2, c: int, sc: int) -> void:
	_add_score(sc)
	Fx.pop(self, pos, "+%d" % sc, Game.COLOR_MAIN[c], 24, 1.1)
	Pickup.spawn(self, Pickup.random_kind(), pos)


func _on_enemy_killed(pos: Vector2, c: int, sc: int) -> void:
	_add_score(sc)
	Fx.pop(self, pos, "+%d" % sc, Game.COLOR_MAIN[c], 18)
	if randf() < DROP_CHANCE:
		Pickup.spawn(self, Pickup.random_kind(), pos)


## 每波妖潮结束：额外刷新 WAVE_DROP 个道具，散落在场景右段，逼玩家挪过去捡
func _drop_wave() -> void:
	for i in WAVE_DROP:
		var x := randf() * 540.0 + 460.0
		var y := randf() * (Game.VIEW_H - 240.0) + 120.0
		Pickup.spawn(self, Pickup.random_kind(), Vector2(x, y))


# ---------------------------------------------------------------- Boss
func _boss_fight() -> void:
	_set_wave("血魔老祖")
	bg.scroll_speed = 22.0
	boss = Boss.new()
	boss.world = self
	add_child(boss)
	boss.player_ref = player
	boss.player_robes = player.robes
	boss.phase_chg.connect(_on_boss_phase)
	boss.ward_chg.connect(_on_ward)
	boss.enrage_started.connect(_on_enrage)
	boss.boss_died.connect(_on_boss_died)
	hud.bind_boss(boss)
	var sub := "四色弹幕 + 属性法罩，破罩方能致胜" if Game.boss_ward() \
		else "四色弹幕 · 老祖不展法罩，全力输出即可"
	hud.show_banner("血 魔 老 祖", sub, 2.4)


func _on_enrage() -> void:
	hud.show_banner("狂 暴", "老祖周身泛起血光 · 四色螺旋弹幕", 1.8)


func _on_boss_phase(p: int) -> void:
	_add_score(600)
	hud.show_banner("第 %d 重法相" % p, "血魔变换法相，弹幕更急", 1.6)


func _on_ward(c: int) -> void:
	if c < 0 or player == null or not is_instance_valid(player):
		return
	if player.color != c:
		Fx.pop(self, player.position + Vector2(0.0, -52.0), "法罩 · %s" % Game.COLOR_CN[c],
			Game.COLOR_MAIN[c], 20, 1.1)


func _on_boss_died() -> void:
	_add_score(5000)
	_set_wave("功 成")
	await wait(1.3)
	_finish(true)


func _on_player_died() -> void:
	_running = false
	_set_wave("陨 落")
	_stop_field()
	await wait(1.5)
	_finish(false)


## 玩家已陨落：清弹、撤妖、让老祖收手。
## 不做这步的话，接下来这 1.5 秒里 Boss 仍会按套路开火，而 player_ref 指向的
## 玩家节点已经被 queue_free —— 把「已释放对象」赋给弹幕的 target 会直接报
## "Invalid assignment ... with value of type 'previously freed'"。
func _stop_field() -> void:
	for ch in get_children():
		if ch is Danmaku:
			(ch as Danmaku).dissolve()
		elif ch is Enemy:
			(ch as Enemy).queue_free()
		elif ch is Elite:
			(ch as Elite).queue_free()
		elif ch is Pickup:
			(ch as Pickup).queue_free()
	if boss != null and is_instance_valid(boss):
		boss.player_ref = null
		boss.stand_down()
	if bg != null:
		bg.scroll_speed = 6.0


func _finish(win: bool) -> void:
	_running = false
	Game.result_win = win
	Game.result_score = score
	Game.result_hp = player.hp if (player != null and is_instance_valid(player)) else 0
	finished.emit(win)


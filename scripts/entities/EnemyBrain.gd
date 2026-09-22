class_name EnemyBrain
extends RefCounted
## ---------------------------------------------------------------
## EnemyBrain —— 独有怪行为分发（纯静态）
##
## 职责：`Enemy` 里 kind != GRUNT 的单位，运动 / 开火转发到这里。
##   · 通用怪（GRUNT）路径**一行都不经过这里** —— Enemy 自己保留原有
##     match pattern / match color，保证既有波次配色与运动零回归。
##   · 本文件只处理 7 种独有怪；每个分支读 Enemy 的内部字段（约定：
##     Enemy 的内部契约，EnemyBrain 可读，其它类一律不许）。
##
## 三条契约（离场复用 Enemy 的既有态，别另造回收机制）：
##   1. 需要「进场后再打」的单位，用 e._entered 门控（Enemy._motion 里
##      向左穿过 VIEW_W-30 会置真）；hover 类不左移，由本文件自行置真。
##   2. 分裂 / 布雷 / 召唤一律 call_deferred —— 绝不在物理回调里 add_child。
##   3. 硬闸（MAX_CLONES / MAX_REINFORCE / MAX_MINES）超上限不生成、不排队。
## ---------------------------------------------------------------

## ② 变节者：核心在玩家两件战甲色之间轮换的间隔（秒）
const DEFECTOR_SWAP := 3.5
## ② 变节者：换色瞬间的破绽窗口（秒）—— 此间任意色 ×2
const DEFECTOR_WINDOW := 0.6
## ① 拆解者：死亡分裂出的小片数
const DISMANTLER_SHARDS := 2
## ④ 敷设者：雷的自毁时长（秒）
const LAYER_MINE_LIFE := 8.0
## ⑦ 相位者：折跃 + 无敌的节奏
const PHASER_CYCLE := 2.6
const PHASER_INVULN := 1.1


## 运动分发：由 Enemy._motion 在 kind != GRUNT 时调用
## 注意：e._t 由 Enemy._process 统一累加，这里不重复。
static func move(e: Enemy, delta: float) -> void:
	match e.kind:
		EnemyKind.K.DISMANTLER:
			_move_dismantler(e, delta)
		EnemyKind.K.DEFECTOR:
			_move_defector(e, delta)
		EnemyKind.K.PHALANX:
			_move_phalanx(e, delta)
		EnemyKind.K.LAYER:
			_move_layer(e, delta)
		EnemyKind.K.SIPHON:
			_move_siphon(e, delta)
		EnemyKind.K.MARTYR:
			_move_martyr(e, delta)
		EnemyKind.K.PHASER:
			_move_phaser(e, delta)


## 开火分发：由 Enemy._shoot 在 kind != GRUNT 时调用
static func fire(e: Enemy) -> void:
	match e.kind:
		EnemyKind.K.DISMANTLER:
			_fire_dismantler(e)
		EnemyKind.K.DEFECTOR:
			_fire_defector(e)
		EnemyKind.K.PHALANX:
			_fire_phalanx(e)
		EnemyKind.K.LAYER:
			_fire_layer(e)
		EnemyKind.K.SIPHON:
			_fire_siphon(e)
		EnemyKind.K.MARTYR:
			_fire_martyr(e)
		EnemyKind.K.PHASER:
			_fire_phaser(e)


# ============================================================ ① 拆解者 · 破片浮游机（L1 · 环）
## 缓慢左移 + 正弦起伏；死亡时分裂（在 Enemy._die 里触发）。
static func _move_dismantler(e: Enemy, delta: float) -> void:
	e.position.x -= e.speed * 0.7 * delta
	e.position.y = e._base_y + sin(e._t * 0.8 * TAU) * e._amp * 0.6
	if e.position.x < Game.VIEW_W - 30.0:
		e._entered = true


## 拆解者本体：六向抛破片（慢速散射，逼玩家走位清场）
static func _fire_dismantler(e: Enemy) -> void:
	if not e._entered:
		return
	for i in 6:
		var a := TAU * float(i) / 6.0
		e._shot(e.color, Vector2.RIGHT.rotated(a), 150.0, 8.0, 7)


## 小片：快速外飘，不二次分裂，no_block_clear。
static func spawn_shard(world: Node2D, pos: Vector2, color: int, dirv: Vector2,
		stage: int) -> void:
	if world == null:
		return
	var n := 0
	for ch in world.get_children():
		if ch is Enemy and (ch as Enemy).kind == EnemyKind.K.DISMANTLER \
				and (ch as Enemy)._shard and not (ch as Enemy).dead:
			n += 1
	if n >= EnemyKind.MAX_CLONES:
		return
	var s := Enemy.new()
	s.world = world
	s.kind = EnemyKind.K.DISMANTLER
	s.stage = stage
	s.no_block_clear = true
	s._phase = randf() * TAU
	world.add_child(s)
	s.setup(color, "straight", pos.y, 0.5)
	s._shard = true   # setup 会复位，故在其后置位
	s.position = pos
	s.speed = 210.0
	s._entered = true
	s._leaving = true   # 小片一路飞出画面即回收，不阻塞清场
	# 小片血量极低；同色光刃命中即连带秒杀（见 Enemy.hit 的 shard 分支）
	s.hp = 4
	s.max_hp = 4


# ============================================================ ② 变节者 · 棱晶换色机（L2 · 翼）
## 核心色在玩家两件战甲色之间每 3.5s 轮换；换色瞬间 0.6s 内任意色 ×2 破绽。
## 轮换色恒 ∈ 玩家已选两件战甲（可行性铁律，配色由 Level 保证，这里兜底取 S）。
static func _move_defector(e: Enemy, delta: float) -> void:
	e.position.x -= e.speed * 0.6 * delta
	e.position.y = e._base_y + sin(e._t * 1.1 * TAU) * e._amp * 0.5
	if e.position.x < Game.VIEW_W - 30.0:
		e._entered = true
	e._brain_timer -= delta
	if e._brain_timer <= 0.0:
		e._brain_timer = DEFECTOR_SWAP
		_swap_defector_color(e)


static func _swap_defector_color(e: Enemy) -> void:
	var s := Game.picked_armors
	if s.size() < 2:
		return
	var next := s[0] if e.color == s[1] else s[1]
	e.color = next
	# 破绽窗口：此间命中任意色 ×2 —— 用独立字段承载（不占 _flash，避免被 hit 白闪重置）
	e._ward_window = DEFECTOR_WINDOW
	e._t = 0.0   # 换色瞬间重置动画相位，翼面折射闪一次


## 变节者本体：朝玩家点射两发（换色破绽才是主要威胁，弹幕为次要压迫）
static func _fire_defector(e: Enemy) -> void:
	if not e._entered:
		return
	var a := e._aim()
	e._shot(e.color, a, 300.0, 8.0, 9)
	e._shot(e.color, a.rotated(-0.10), 280.0, 8.0, 9)


# ============================================================ ③ 列阵者 · 方阵炮舰（L3 · 炮列）
## 组内 3 艘同色同批（由 Level/Spawner 保证）；这里每艘按自己在墙中的序号
## 决定纵向偏移与开火相位，安全缝靠错开射击相位形成。
static func _move_phalanx(e: Enemy, delta: float) -> void:
	# 缓慢逼近到墙的 X 位（不飞出左界），纵向按 _base_y 固定
	var home_x := Game.VIEW_W - 190.0
	e.position.x = move_toward(e.position.x, home_x, e.speed * 0.5 * delta)
	if e.position.x <= home_x + 4.0:
		e._entered = true
	# 墙整体缓慢上下平移，制造规律安全缝
	e.position.y = e._base_y + sin(e._t * 0.5 * TAU) * 90.0


## 齐射：三向扇形慢弹，留缝（中间一列由组内中间艘负责，偏移让开 CORE 扇区）。
## 注意：本函数由 Enemy._shoot 调用，开火冷却已由 Enemy._firing 的 _fire 门控，
## 这里直接打，不再二次判 _fire（否则永远打不出）。
static func _fire_phalanx(e: Enemy) -> void:
	if not e._entered:
		return
	var a := e._aim().angle()
	# 3 连垂直弹幕墙：上 / 中 / 下，中间让开 ±15° CORE 扇区（偏移角而非正对）
	for i in 3:
		var off := (float(i) - 1.0) * 0.30
		e._shot(e.color, Vector2.RIGHT.rotated(a + off), 220.0, 9.0, 8)


# ============================================================ ④ 敷设者 · 引力雷舰（L4 · 触须）
## 横穿全屏，沿途布设静态引力雷（超 MAX_MINES 不生成、不排队），雷 8s 自毁。
static func _move_layer(e: Enemy, delta: float) -> void:
	# 引力雷：静态，靠 _life 倒计时自毁（Enemy._process 会递减 _life）
	if e._mine:
		if e._life <= 0.0:
			e._die()
		return
	e.position.x -= e.speed * 0.85 * delta
	if e.position.x < Game.VIEW_W - 30.0:
		e._entered = true
	# 布雷节拍（用 _brain_timer，不复用 _fire —— 那是 Enemy._firing 的开火冷却）
	e._brain_timer -= delta
	if e._brain_timer <= 0.0 and e.position.x < Game.VIEW_W - 120.0:
		e._brain_timer = 1.35
		_lay_mine(e)


static func _lay_mine(e: Enemy) -> void:
	if e.world == null:
		return
	var n := 0
	for ch in e.world.get_children():
		if ch is Enemy and (ch as Enemy)._mine and not (ch as Enemy).dead:
			n += 1
	if n >= EnemyKind.MAX_MINES:
		return   # 硬闸：超上限不生成、不排队
	var m := Enemy.new()
	m.world = e.world
	m.kind = EnemyKind.K.LAYER
	m.stage = e.stage
	m.no_block_clear = true
	m._phase = randf() * TAU
	e.world.add_child(m)
	m.setup(e.color, "straight", e.position.y + randf() * 60.0 - 30.0, 1.0)
	m._mine = true   # setup 会复位，故在其后置位
	m.position = e.position + Vector2(24.0, 0.0)
	m.speed = 0.0
	m._entered = true
	m._leaving = true
	m._life = LAYER_MINE_LIFE   # 8s 自毁
	m.hp = 12
	m.max_hp = 12
	m.score = EnemyKind.MINE_SCORE   # 雷不给分（否则玩家会为分去刷雷）


## 敷设者本体：轻弹幕（主要威胁是它布下的雷，不是它自己开火）
static func _fire_layer(e: Enemy) -> void:
	if not e._entered:
		return
	var a := e._aim().angle()
	# 两发慢弹，左右小散
	e._shot(e.color, Vector2.RIGHT.rotated(a + 0.20), 200.0, 9.0, 8)
	e._shot(e.color, Vector2.RIGHT.rotated(a - 0.20), 200.0, 9.0, 8)


# ============================================================ ⑤ 虹吸者 · 反相无人机（L4 · 触须）
## 反向共振：吸收某色弹幕并回血。被吸收色 ∈ 玩家已选两件战甲（Level 保证）。
## 缓慢逼近，周期性朝玩家吐一发「反相」弹（异色全额、同色被它吞掉回血）。
static func _move_siphon(e: Enemy, delta: float) -> void:
	e.position.x -= e.speed * 0.55 * delta
	e.position.y = e._base_y + sin(e._t * 0.7 * TAU) * e._amp * 0.7
	if e.position.x < Game.VIEW_W - 30.0:
		e._entered = true


static func _fire_siphon(e: Enemy) -> void:
	if not e._entered:
		return
	# 反相：朝玩家吐一发慢弹；玩家若同色吞下则虹吸者回血（见 Enemy.hit 的虹吸分支）
	# 开火冷却已由 Enemy._firing 的 _fire 门控，这里直接打
	var dir := e._aim()
	e._shot(e.color, dir, 180.0, 11.0, 9)


# ============================================================ ⑥ 殉爆者 · 冲撞自杀舰（L5 · 分身）
## 高速直冲玩家；死/撞都爆半径 150 冲击环（冲击环在 Enemy._die 里画）。
## 颜色 ∈ 四色，照常吃共振；冲撞伤害走「物理碰撞」通道——直接扣血，
## 不经 Player.take_hit 的同色吸收判定，因此换甲救不了（见 _contact_player）。
const MARTYR_CONTACT := 26.0
const MARTYR_DMG := 20
## 殉爆者自爆冲击环伤害（设计 §C.5 ⑥：半径 150，伤害 15，物理通道）
const MARTYR_SHOCK_DMG := 15
## 殉爆者自爆抛出的破片数（设计 §C.5 ⑥：8 片，继承本体色，正常四色弹可被同色甲免疫）
const MARTYR_SHARDS := 8

static func _move_martyr(e: Enemy, delta: float) -> void:
	var dir := e._aim()
	if e.player_ref != null and is_instance_valid(e.player_ref):
		# 直冲：主要沿 -X 推进，同时修正 y 朝玩家
		e.position.x -= e.speed * 1.9 * delta
		e.position.y = move_toward(e.position.y, e.player_ref.position.y, 150.0 * delta)
		# 物理碰撞：贴到玩家即爆（换甲不免疫）
		if e.position.distance_to(e.player_ref.position) < MARTYR_CONTACT + 12.0:
			_contact_player(e)
			return
	else:
		e.position.x -= e.speed * 1.9 * delta
	if e.position.x < Game.VIEW_W - 30.0:
		e._entered = true


## 撞中玩家：直接扣血（绕过同色免疫），随后自爆（冲击环由 _die 的 MARTYR 分支画）
static func _contact_player(e: Enemy) -> void:
	if e.player_ref != null and is_instance_valid(e.player_ref):
		var p: Player = e.player_ref
		if p.alive:
			p.hp -= MARTYR_DMG
			if p.hp <= 0:
				p.hp = 0
				p._die()
	if not e.dead:
		e._die()


## 殉爆（死亡）时触发：冲击环物理伤害 15（换甲挡不住）+ 8 片继承本体色的破片弹
## （正常四色弹，可被对应战甲免疫）。延后一帧执行，避免物理回调里 spawn。
static func martyr_explode(e: Enemy) -> void:
	if e.world == null or not is_instance_valid(e.world):
		return
	# ① 冲击环：半径 150 内的玩家吃 15 点「物理通道」伤害（不经 Player.take_hit 同色吸收）
	_physical_shock(e, MARTYR_SHOCK_DMG, 150.0)
	# ② 8 片破片：继承本体色 e.color（∈ S），作为正常敌弹入 world，可被同色甲免疫
	for i in MARTYR_SHARDS:
		var a := TAU * float(i) / float(MARTYR_SHARDS)
		var dir := Vector2.RIGHT.rotated(a)
		_martyr_shard(e.world, e.color, e.position, dir)


## 物理通道冲击：对半径内的玩家直接扣血（绕过同色免疫判定）
static func _physical_shock(e: Enemy, dmg: int, radius: float) -> void:
	if e.player_ref == null or not is_instance_valid(e.player_ref):
		return
	var p: Player = e.player_ref
	if not p.alive:
		return
	if e.position.distance_to(p.position) <= radius + 12.0:
		p.hp -= dmg
		if p.hp <= 0:
			p.hp = 0
			p._die()


## 殉爆者破片：一颗继承本体色的正常敌弹（走 Danmaku → Player.take_hit，可被同色甲免疫）
static func _martyr_shard(world: Node2D, c: int, pos: Vector2, dir: Vector2) -> void:
	if world == null:
		return
	Danmaku.spawn(world, c, pos + dir * 20.0, dir * 240.0, 10, 9)


static func _fire_martyr(e: Enemy) -> void:
	# 殉爆者存活期不开火 —— 威胁来自冲撞本体、自爆冲击环与殉爆破片（都在 _die 里触发）
	pass


# ============================================================ ⑦ 相位者 · 折跃刺客（L5 · 分身）
## 每 2.6s 无敌 1.1s + 折跃到玩家脸上。无敌期不受伤害（见 Enemy.hit 的相位分支）。
static func _move_phaser(e: Enemy, delta: float) -> void:
	e.position.x -= e.speed * 0.8 * delta
	e.position.y = e._base_y + sin(e._t * 1.4 * TAU) * e._amp * 0.8
	if e.position.x < Game.VIEW_W - 30.0:
		e._entered = true
	# 折跃节拍
	e._brain_timer -= delta
	if e._brain_timer <= 0.0:
		e._brain_timer = PHASER_CYCLE
		_phase_jump(e)


static func _phase_jump(e: Enemy) -> void:
	# 无敌窗口：用独立字段承载（不占 _flash，避免被 hit 白闪重置）
	e._phase_invuln = PHASER_INVULN
	# 折跃到玩家脸上（有玩家则贴脸，否则原地闪烁）
	if e.player_ref != null and is_instance_valid(e.player_ref):
		var p: Vector2 = e.player_ref.position
		e.position = Vector2(clampf(p.x - 130.0, 40.0, Game.VIEW_W - 40.0),
				clampf(p.y, 60.0, Game.VIEW_H - 60.0))
	Fx.ring(e.world, e.position, Game.COLOR_GLOW[e.color], 8.0, 46.0, 0.3, 4.0)


static func _fire_phaser(e: Enemy) -> void:
	if not e._entered:
		return
	# 折跃后朝玩家点射两发（开火冷却已由 Enemy._firing 的 _fire 门控，这里直接打）
	var a := e._aim()
	e._shot(e.color, a, 300.0, 8.0, 9)
	e._shot(e.color, a.rotated(0.12), 280.0, 8.0, 9)

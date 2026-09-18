class_name Pool
extends RefCounted
## ---------------------------------------------------------------
## Pool —— 极简节点对象池
##
## 只缓存「生命周期短、可被 setup() 完整重置」的节点：弹幕 / 飞剑 / 特效。
## 与 queue_free 的区别：release 只是把节点摘出场景树并留用，
## 避免 Boss 弹幕高峰时每秒数百次 Node + CollisionShape2D 的分配与析构。
##
## 约定：
##   1. acquire 之后，调用方必须调用该节点的 setup()/reset() 覆盖全部状态；
##   2. 池内节点一律无父节点，acquire 时只校验 is_instance_valid；
##   3. 池容量上限 MAX，超出直接 free，防止长时间游玩后无限增长。
## ---------------------------------------------------------------

const MAX := 512

static var _bins: Dictionary = {}


## 取一个可复用节点；池空则通过 factory 新建。返回 null 表示 parent 无效。
static func acquire(key: String, parent: Node, factory: Callable) -> Node:
	if parent == null or not is_instance_valid(parent):
		return null
	var bin: Array = _bins.get(key, [])
	var n: Node = null
	while not bin.is_empty():
		var cand: Node = bin.pop_back()
		if is_instance_valid(cand) and cand.get_parent() == null:
			n = cand
			break
	_bins[key] = bin
	if n == null:
		n = factory.call() as Node
	if n == null:
		return null
	if n.get_parent() != parent:
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		parent.add_child(n)
	return n


## 归还节点：摘出场景树保留待用（不 queue_free）。
static func release(key: String, n: Node) -> void:
	if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
		return
	var p := n.get_parent()
	if p != null:
		p.remove_child(n)
	var bin: Array = _bins.get(key, [])
	if bin.size() < MAX:
		bin.append(n)
		_bins[key] = bin
	else:
		n.free()


## 关卡彻底结束时调用，释放全部缓存节点。
static func clear() -> void:
	for key in _bins:
		var bin: Array = _bins[key]
		for n in bin:
			var nd: Node = n
			if is_instance_valid(nd) and nd.get_parent() == null:
				nd.free()
	_bins.clear()

extends Node
class_name KnowledgeEffectManager

## 知识效果管理器 - 管理答题正确/错误对游戏机制的即时影响
## 负责：答题buff/debuff、植物知识熟练度、僵尸知识关联

#region 信号
## 知识buff激活 [plant_type, multiplier, duration]
signal knowledge_buff_activated(plant_type: int, multiplier: float, duration: float)
## 知识buff结束 [plant_type]
signal knowledge_buff_expired(plant_type: int)
## 熟练度提升 [module_id, new_level, plant_type]
signal proficiency_level_up(module_id: int, new_level: int, plant_type: int)
## 僵尸知识惩罚 [zombie_type, knowledge_id]
signal zombie_knowledge_penalty(zombie_type: int, knowledge_id: String)
#endregion

#region 常量
## 答题正确buff：伤害倍率
const BUFF_DAMAGE_MULTIPLIER: float = 1.5
## 答题正确buff：持续时间（秒）
const BUFF_DURATION: float = 15.0
## 答题错误debuff：伤害倍率
const DEBUFF_DAMAGE_MULTIPLIER: float = 0.7
## 答题错误debuff：持续时间（秒）
const DEBUFF_DURATION: float = 10.0
## 熟练度每级所需经验
const EXP_PER_LEVEL: int = 3
## 最大熟练度等级
const MAX_PROFICIENCY_LEVEL: int = 5
## 每级熟练度提供的伤害加成
const DAMAGE_PER_PROFICIENCY_LEVEL: float = 0.1
#endregion

#region 数据结构
## 活跃buff表 {plant_type: {multiplier: float, timer: Timer, count: int}}
var _active_buffs: Dictionary = {}
## 模块熟练度 {module_id: {level: int, exp: int}}
var _module_proficiency: Dictionary = {}
## 僵尸-考点映射 {zombie_type: {module_id: int, knowledge_id: String, difficulty: int}}
var _zombie_knowledge_map: Dictionary = {}
## 僵尸知识惩罚是否激活
var is_penalty_active: bool = false
#endregion


func _ready() -> void:
	_init_zombie_knowledge_map()
	_connect_signals()


## 初始化僵尸-考点映射
func _init_zombie_knowledge_map() -> void:
	_zombie_knowledge_map = {
		CharacterRegistry.ZombieType.Z001Norm: {
			"module_id": 1, "knowledge_id": "math_limit", "difficulty": 1
		},
		CharacterRegistry.ZombieType.Z002Cone: {
			"module_id": 1, "knowledge_id": "math_continuity", "difficulty": 1
		},
		CharacterRegistry.ZombieType.Z003Bucket: {
			"module_id": 1, "knowledge_id": "math_limit", "difficulty": 2
		},
		CharacterRegistry.ZombieType.Z004Flag: {
			"module_id": 1, "knowledge_id": "math_continuity", "difficulty": 1
		},
		CharacterRegistry.ZombieType.Z005Newspaper: {
			"module_id": 2, "knowledge_id": "math_derivative", "difficulty": 2
		},
		CharacterRegistry.ZombieType.Z006ScreenDoor: {
			"module_id": 2, "knowledge_id": "math_chain_rule", "difficulty": 2
		},
		CharacterRegistry.ZombieType.Z007Football: {
			"module_id": 2, "knowledge_id": "math_implicit_func", "difficulty": 3
		},
		CharacterRegistry.ZombieType.Z008Dancing: {
			"module_id": 3, "knowledge_id": "math_integral", "difficulty": 2
		},
		CharacterRegistry.ZombieType.Z009BackupDancer: {
			"module_id": 3, "knowledge_id": "math_integral_substitution", "difficulty": 2
		},
		CharacterRegistry.ZombieType.Z010Dolphin: {
			"module_id": 3, "knowledge_id": "math_integral_by_parts", "difficulty": 3
		},
		CharacterRegistry.ZombieType.Z011Snorkel: {
			"module_id": 4, "knowledge_id": "math_ode", "difficulty": 2
		},
		CharacterRegistry.ZombieType.Z012Zomboni: {
			"module_id": 4, "knowledge_id": "math_ode_char_eq", "difficulty": 3
		},
		CharacterRegistry.ZombieType.Z013Pogo: {
			"module_id": 5, "knowledge_id": "math_partial_derivative", "difficulty": 3
		},
		CharacterRegistry.ZombieType.Z014Gargantuar: {
			"module_id": 5, "knowledge_id": "math_total_diff", "difficulty": 4
		},
		CharacterRegistry.ZombieType.Z015Imp: {
			"module_id": 5, "knowledge_id": "math_lagrange", "difficulty": 2
		},
		CharacterRegistry.ZombieType.Z016Bungee: {
			"module_id": 6, "knowledge_id": "math_double_integral", "difficulty": 3
		},
		CharacterRegistry.ZombieType.Z017Ladder: {
			"module_id": 6, "knowledge_id": "math_polar_coord", "difficulty": 3
		},
		CharacterRegistry.ZombieType.Z018Catapult: {
			"module_id": 6, "knowledge_id": "math_double_integral", "difficulty": 4
		},
	}
	print("[KnowledgeEffectManager] 僵尸-考点映射初始化完成，%d 种僵尸" % _zombie_knowledge_map.size())


## 连接信号
func _connect_signals() -> void:
	ExamManager.question_answered.connect(_on_question_answered)
	ExamManager.quiz_completed.connect(_on_quiz_completed)


## 答题回调：根据正确/错误施加效果
func _on_question_answered(question_id: String, is_correct: bool, _correct_answer: String) -> void:
	if is_correct:
		_apply_correct_answer_effect(question_id)
	else:
		_apply_wrong_answer_effect(question_id)


## 答题完成回调
func _on_quiz_completed(correct_count: int, total_count: int, module_id: int) -> void:
	## 根据正确率增加熟练度
	var ratio = float(correct_count) / max(total_count, 1)
	if ratio >= 0.8:
		_add_module_proficiency(module_id, 2)
	elif ratio >= 0.5:
		_add_module_proficiency(module_id, 1)
	else:
		_add_module_proficiency(module_id, 0)  # 不增加经验

	## 关闭惩罚状态
	is_penalty_active = false


## 答题正确：施加buff
func _apply_correct_answer_effect(question_id: String) -> void:
	## 查找与本题相关且在场上的植物
	var plant_type = _get_plant_type_for_question(question_id)
	if plant_type < 0:
		return

	_add_buff(plant_type, BUFF_DAMAGE_MULTIPLIER, BUFF_DURATION)

	## 增加模块熟练度（正确答题额外+1）
	var module_id = _get_module_id_for_question(question_id)
	if module_id > 0:
		_add_module_proficiency(module_id, 1)


## 答题错误：施加debuff
func _apply_wrong_answer_effect(question_id: String) -> void:
	## 激活僵尸惩罚：在debuff期间，僵尸获得增强
	is_penalty_active = true

	## 对场上相关植物施加debuff
	var plant_type = _get_plant_type_for_question(question_id)
	if plant_type >= 0:
		_add_buff(plant_type, DEBUFF_DAMAGE_MULTIPLIER, DEBUFF_DURATION)

	## 通知僵尸惩罚激活
	zombie_knowledge_penalty.emit(-1, "")


## 添加buff
func _add_buff(plant_type: int, multiplier: float, duration: float) -> void:
	if _active_buffs.has(plant_type):
		## 已有buff，更新为更高倍率或重置计时
		var existing = _active_buffs[plant_type]
		if multiplier > existing.multiplier:
			existing.multiplier = multiplier
		existing.count += 1
		existing.timer.start(duration)
	else:
		var timer = Timer.new()
		timer.one_shot = true
		timer.timeout.connect(_on_buff_timeout.bind(plant_type))
		add_child(timer)
		timer.start(duration)

		_active_buffs[plant_type] = {
			"multiplier": multiplier,
			"timer": timer,
			"count": 1
		}

	knowledge_buff_activated.emit(plant_type, multiplier, duration)


## buff超时
func _on_buff_timeout(plant_type: int) -> void:
	if not _active_buffs.has(plant_type):
		return

	var buff = _active_buffs[plant_type]
	buff.count -= 1

	if buff.count <= 0:
		buff.timer.queue_free()
		_active_buffs.erase(plant_type)
		knowledge_buff_expired.emit(plant_type)


## 获取知识伤害倍率（供子弹系统调用）
func get_damage_multiplier(plant_type: int) -> float:
	var multiplier: float = 1.0

	## 1. 活跃buff加成
	if _active_buffs.has(plant_type):
		multiplier *= _active_buffs[plant_type].multiplier

	## 2. 熟练度加成
	var module_id = _get_module_id_for_plant(plant_type)
	if module_id > 0 and _module_proficiency.has(module_id):
		var level = _module_proficiency[module_id].level
		multiplier += level * DAMAGE_PER_PROFICIENCY_LEVEL

	return multiplier


## 获取僵尸是否受到知识惩罚增强
func get_zombie_penalty_multiplier(zombie_type: int) -> float:
	if not is_penalty_active:
		return 1.0
	## 答题错误时僵尸增强
	return 1.2


## 获取僵尸对应考点ID
func get_zombie_knowledge_id(zombie_type: int) -> String:
	var data = _zombie_knowledge_map.get(zombie_type, {})
	return data.get("knowledge_id", "")


## 获取僵尸对应模块ID
func get_zombie_module_id(zombie_type: int) -> int:
	var data = _zombie_knowledge_map.get(zombie_type, {})
	return data.get("module_id", 0)


## 获取僵尸难度
func get_zombie_difficulty(zombie_type: int) -> int:
	var data = _zombie_knowledge_map.get(zombie_type, {})
	return data.get("difficulty", 1)


## 增加模块熟练度
func _add_module_proficiency(module_id: int, exp: int) -> void:
	if module_id <= 0 or module_id > 6:
		return

	if not _module_proficiency.has(module_id):
		_module_proficiency[module_id] = {"level": 1, "exp": 0}

	var prof = _module_proficiency[module_id]
	prof.exp += exp

	## 检查升级
	while prof.exp >= EXP_PER_LEVEL and prof.level < MAX_PROFICIENCY_LEVEL:
		prof.exp -= EXP_PER_LEVEL
		prof.level += 1
		## 查找该模块下在场上的植物触发升级信号
		var plant_type = _get_plant_type_for_module(module_id)
		if plant_type >= 0:
			proficiency_level_up.emit(module_id, prof.level, plant_type)


## 获取模块熟练度等级
func get_proficiency_level(module_id: int) -> int:
	if _module_proficiency.has(module_id):
		return _module_proficiency[module_id].level
	return 1


## 获取模块熟练度经验
func get_proficiency_exp(module_id: int) -> int:
	if _module_proficiency.has(module_id):
		return _module_proficiency[module_id].exp
	return 0


## 获取模块熟练度进度（0.0-1.0）
func get_proficiency_progress(module_id: int) -> float:
	var level = get_proficiency_level(module_id)
	var exp = get_proficiency_exp(module_id)
	if level >= MAX_PROFICIENCY_LEVEL:
		return 1.0
	return float(exp) / EXP_PER_LEVEL


## 获取所有模块的熟练度数据
func get_all_proficiency() -> Dictionary:
	return _module_proficiency.duplicate()


## 清除所有buffs
func clear_all_buffs() -> void:
	for plant_type in _active_buffs.keys():
		var buff = _active_buffs[plant_type]
		buff.timer.queue_free()
		knowledge_buff_expired.emit(plant_type)
	_active_buffs.clear()


## 重置所有数据
func reset_all_data() -> void:
	clear_all_buffs()
	_module_proficiency.clear()
	is_penalty_active = false


## 辅助：根据题目ID查找对应植物类型
func _get_plant_type_for_question(question_id: String) -> int:
	## 从PlantKnowledgeBinder获取映射
	var plant_map = PlantKnowledgeBinder.get_field_plants()
	if plant_map.is_empty():
		return -1
	## 返回场上的第一种植物(简化处理)
	return plant_map[0].get("plant_type", -1)


## 辅助：根据题目ID获取模块ID
func _get_module_id_for_question(question_id: String) -> int:
	var all_questions = ExamManager.get_all_questions()
	for q in all_questions:
		if q.get("id", "") == question_id:
			return q.get("module_id", 0)
	return 0


## 辅助：根据植物类型获取模块ID
func _get_module_id_for_plant(plant_type: int) -> int:
	return PlantKnowledgeBinder.get_module_id(plant_type)


## 辅助：根据模块ID查找场上的植物类型
func _get_plant_type_for_module(module_id: int) -> int:
	var plants = PlantKnowledgeBinder.get_field_plants()
	for p in plants:
		var pid = p.get("plant_type", -1)
		var mod = _get_module_id_for_plant(pid)
		if mod == module_id:
			return pid
	return -1


## 获取当前活跃buff信息（调试用）
func get_active_buffs_info() -> Array:
	var result: Array = []
	for plant_type in _active_buffs.keys():
		var buff = _active_buffs[plant_type]
		result.append({
			"plant_type": plant_type,
			"multiplier": buff.multiplier,
			"time_left": buff.timer.time_left,
			"count": buff.count
		})
	return result

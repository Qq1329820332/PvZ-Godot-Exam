extends Node
class_name PlantKnowledgeBinder

## 植物考点绑定管理器 - 管理植物与考纲知识的映射关系
## 记录场上已放置的植物，提供考点查询和关联出题功能

#region 信号
## 植物放置时触发 [plant_type, plant_id, module_id]
signal plant_placed(plant_type: int, plant_id: String, module_id: int)
## 植物被移除时触发 [plant_type, plant_id]
signal plant_removed(plant_type: int, plant_id: String)
## 场上植物考点变化（用于更新 UI）
signal field_knowledge_updated(module_ids: Array)
#endregion

#region 数据
var _plant_map: Dictionary = {}       # plant_id -> 完整植物数据
var _plant_type_to_id: Dictionary = {} # PlantType enum -> plant_id (JSON中的ID)
var _id_to_plant_type: Dictionary = {} # plant_id -> PlantType enum

## 场上当前已放置的植物列表 [{plant_type, plant_id, row, col}]
var field_plants: Array[Dictionary] = []
## 场上植物的考点集合（去重）
var field_knowledge_ids: Array[String] = []
## 场上的模块集合
var field_module_ids: Array[int] = []
#endregion

const PLANT_MAP_PATH: String = "res://data/plant_knowledge_map.json"


func _ready() -> void:
	_load_plant_map()
	_init_plant_type_mapping()
	_connect_plant_events()


## 加载植物映射数据
func _load_plant_map() -> void:
	var file = FileAccess.open(PLANT_MAP_PATH, FileAccess.READ)
	if file:
		var text = file.get_as_text()
		var data = JSON.parse_string(text)
		if data:
			var plants = data.get("plants", [])
			for p in plants:
				_plant_map[p.get("id", "")] = p
			print("[PlantKnowledgeBinder] 植物映射数据加载成功，%d 株植物" % plants.size())
		else:
			push_error("[PlantKnowledgeBinder] 植物映射数据解析失败")
	else:
		push_error("[PlantKnowledgeBinder] 无法加载植物映射: " + PLANT_MAP_PATH)


## 初始化 PlantType 枚举到 JSON ID 的映射
func _init_plant_type_mapping() -> void:
	# 映射规则：CharacterRegistry.PlantType 枚举名 → plant_knowledge_map.json 中的 id
	# 命名转换：P001PeaShooterSingle → plant_001_pea_shooter_single → 按模块匹配
	# 这里使用显式映射，确保准确对应
	_plant_type_to_id = {
		CharacterRegistry.PlantType.P001PeaShooterSingle: "plant_limit_pea",
		CharacterRegistry.PlantType.P004WallNut: "plant_continuity_tree",
		CharacterRegistry.PlantType.P006SnowPea: "plant_derivative_shooter",
		CharacterRegistry.PlantType.P007Chomper: "plant_chain_vine",
		CharacterRegistry.PlantType.P005PotatoMine: "plant_implicit_mushroom",
		CharacterRegistry.PlantType.P016DoomShroom: "plant_integral_mushroom",
		CharacterRegistry.PlantType.P003CherryBomb: "plant_substitution_flower",
		CharacterRegistry.PlantType.P008PeaShooterDouble: "plant_integral_lotus",
		CharacterRegistry.PlantType.P002SunFlower: "plant_ode_grass",
		CharacterRegistry.PlantType.P024TallNut: "plant_characteristic_tree",
		CharacterRegistry.PlantType.P019ThreePeater: "plant_partial_shooter",
		CharacterRegistry.PlantType.P023TorchWood: "plant_total_diff_fruit",
		CharacterRegistry.PlantType.P030StarFruit: "plant_lagrange_pine",
		CharacterRegistry.PlantType.P040MelonPult: "plant_double_flower",
		CharacterRegistry.PlantType.P045WinterMelon: "plant_polar_lotus",
	}
	# 建立反向映射
	for plant_type in _plant_type_to_id:
		var pid = _plant_type_to_id[plant_type]
		_id_to_plant_type[pid] = plant_type


## 连接植物放置/移除事件
func _connect_plant_events() -> void:
	# 通过 EventBus 监听植物放置事件
	EventBus.subscribe("plant_placed", _on_plant_placed_on_field)
	EventBus.subscribe("plant_removed", _on_plant_removed_from_field)


## 植物放置到场上的回调
func _on_plant_placed_on_field(plant_type: int, row: int, col: int) -> void:
	var plant_id = _plant_type_to_id.get(plant_type, "")
	if plant_id.is_empty():
		return

	# 记录到场上列表
	var entry = {
		"plant_type": plant_type,
		"plant_id": plant_id,
		"row": row,
		"col": col
	}
	field_plants.append(entry)
	_update_field_knowledge()

	var module_id = _get_module_id(plant_id)
	plant_placed.emit(plant_type, plant_id, module_id)


## 植物从场上移除的回调
func _on_plant_removed_from_field(plant_type: int, row: int, col: int) -> void:
	var plant_id = _plant_type_to_id.get(plant_type, "")
	if plant_id.is_empty():
		return

	# 从场上列表移除
	var idx = -1
	for i in range(field_plants.size()):
		var entry = field_plants[i]
		if entry.plant_type == plant_type and entry.row == row and entry.col == col:
			idx = i
			break
	if idx >= 0:
		field_plants.remove_at(idx)
		_update_field_knowledge()
		plant_removed.emit(plant_type, plant_id)


## 更新场上考点摘要
func _update_field_knowledge() -> void:
	var k_set: Dictionary = {}
	var m_set: Dictionary = {}
	for entry in field_plants:
		var data = _plant_map.get(entry.plant_id, {})
		var primary = data.get("primary_knowledge", "")
		if not primary.is_empty():
			k_set[primary] = true
		for secondary in data.get("secondary_knowledge", []):
			k_set[secondary] = true
		var mod = data.get("module", 0)
		if mod > 0:
			m_set[mod] = true

	field_knowledge_ids = k_set.keys()
	field_module_ids = m_set.keys().map(func(x): return int(x))
	field_knowledge_updated.emit(field_module_ids)


## 获取植物对应的考点 ID 列表
func get_knowledge_ids(plant_type: int) -> Array[String]:
	var plant_id = _plant_type_to_id.get(plant_type, "")
	if plant_id.is_empty():
		return []
	var data = _plant_map.get(plant_id, {})
	var result: Array[String] = []
	var primary = data.get("primary_knowledge", "")
	if not primary.is_empty():
		result.append(primary)
	for secondary in data.get("secondary_knowledge", []):
		result.append(secondary)
	return result


## 获取植物对应的模块 ID
func get_module_id(plant_type: int) -> int:
	var plant_id = _plant_type_to_id.get(plant_type, "")
	return _get_module_id(plant_id)


func _get_module_id(plant_id: String) -> int:
	var data = _plant_map.get(plant_id, {})
	return data.get("module", 0)


## 获取植物显示名称
func get_plant_display_name(plant_type: int) -> String:
	var plant_id = _plant_type_to_id.get(plant_type, "")
	var data = _plant_map.get(plant_id, {})
	return data.get("name", "")


## 获取植物技能描述
func get_plant_skill_description(plant_type: int) -> String:
	var plant_id = _plant_type_to_id.get(plant_type, "")
	var data = _plant_map.get(plant_id, {})
	return data.get("skill_description", "")


## 获取植物完整数据
func get_plant_data(plant_type: int) -> Dictionary:
	var plant_id = _plant_type_to_id.get(plant_type, "")
	return _plant_map.get(plant_id, {})


## 获取植物数据（通过 plant_id）
func get_plant_data_by_id(plant_id: String) -> Dictionary:
	return _plant_map.get(plant_id, {})


## 获取场上所有植物对应的考点 ID 列表（去重）
func get_field_knowledge_ids() -> Array[String]:
	return field_knowledge_ids.duplicate()


## 获取场上所有植物对应的模块 ID 列表（去重）
func get_field_module_ids() -> Array[int]:
	return field_module_ids.duplicate()


## 获取场上植物列表
func get_field_plants() -> Array:
	return field_plants.duplicate()


## 获取场上植物数量
func get_field_plant_count() -> int:
	return field_plants.size()


## 根据场上植物生成关联题目列表
func get_questions_for_field_plants(max_count: int = 3) -> Array:
	var result: Array = []
	var k_ids = get_field_knowledge_ids()
	if k_ids.is_empty():
		return result

	# 从 ExamManager 题库中筛选与场上考点匹配的题目
	var all_questions = ExamManager.get_all_questions()
	var pool: Array = []
	for q in all_questions:
		var q_kid = q.get("knowledge_id", "")
		if q_kid in k_ids:
			pool.append(q)

	# 随机打乱并取 max_count 道
	pool.shuffle()
	for i in range(min(max_count, pool.size())):
		result.append(pool[i])

	return result


## 根据指定植物类型获取关联题目
func get_questions_for_plant(plant_type: int, max_count: int = 2) -> Array:
	var k_ids = get_knowledge_ids(plant_type)
	if k_ids.is_empty():
		return []

	var result: Array = []
	var all_questions = ExamManager.get_all_questions()
	for q in all_questions:
		var q_kid = q.get("knowledge_id", "")
		if q_kid in k_ids:
			result.append(q)
		if result.size() >= max_count:
			break

	return result


## 清除场上植物记录
func clear_field_plants() -> void:
	field_plants.clear()
	field_knowledge_ids.clear()
	field_module_ids.clear()
	field_knowledge_updated.emit([])


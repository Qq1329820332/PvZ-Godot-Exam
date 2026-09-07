extends Node
class_name ExamManager

## 答题管理器 - 全局 autoload
## 负责加载考纲知识数据，管理题目抽取、计分、错题记录

#region 信号
## 答题完成时触发 [correct_count, total_count, module_id]
signal quiz_completed(correct_count: int, total_count: int, module_id: int)
## 单题回答后触发 [question_id, is_correct, correct_answer]
signal question_answered(question_id: String, is_correct: bool, correct_answer: String)
## 触发答题门（让 MainGameManager 显示答题面板）
signal trigger_quiz(module_id: int, difficulty: int)
#endregion

#region 数据
var _knowledge_data: Dictionary = {}
var _questions_data: Dictionary = {}
var _questions_list: Array = []
var _plant_map: Dictionary = {}

## 当前会话统计
var session_correct: int = 0
var session_total: int = 0
var session_module: int = 0
var session_wrong_ids: Array[String] = []

## 当前题目
var current_question: Dictionary = {}

## 是否正在答题中
var is_quiz_active: bool = false
#endregion

const KNOWLEDGE_PATH: String = "res://data/knowledge_data.json"
const QUESTIONS_PATH: String = "res://data/exam_questions.json"
const PLANT_MAP_PATH: String = "res://data/plant_knowledge_map.json"


func _ready() -> void:
	load_data()


## 加载所有 JSON 数据
func load_data() -> void:
	var knowledge_file = FileAccess.open(KNOWLEDGE_PATH, FileAccess.READ)
	if knowledge_file:
		var text = knowledge_file.get_as_text()
		_knowledge_data = JSON.parse_string(text)
		if _knowledge_data:
			print("[ExamManager] 考纲知识数据加载成功，%d 个模块" % _knowledge_data.get("modules", []).size())
		else:
			push_error("[ExamManager] 考纲知识数据解析失败")
	else:
		push_error("[ExamManager] 无法加载考纲知识数据: " + KNOWLEDGE_PATH)

	var questions_file = FileAccess.open(QUESTIONS_PATH, FileAccess.READ)
	if questions_file:
		var text = questions_file.get_as_text()
		_questions_data = JSON.parse_string(text)
		_questions_list = _questions_data.get("questions", [])
		if _questions_data:
			print("[ExamManager] 题库加载成功，%d 道题" % _questions_list.size())
	else:
		push_error("[ExamManager] 无法加载题库: " + QUESTIONS_PATH)

	var plant_file = FileAccess.open(PLANT_MAP_PATH, FileAccess.READ)
	if plant_file:
		var text = plant_file.get_as_text()
		_plant_map = JSON.parse_string(text)
		if _plant_map:
			print("[ExamManager] 植物映射数据加载成功，%d 株植物" % _plant_map.get("plants", []).size())
	else:
		push_error("[ExamManager] 无法加载植物映射: " + PLANT_MAP_PATH)


## 获取指定模块的题目列表
func get_questions_by_module(module_id: int) -> Array:
	return _questions_list.filter(func(q): return q.get("id", "").contains("M%d" % module_id))


## 获取随机题目（按模块和难度过滤）
func get_random_question(module_id: int = -1, difficulty: int = -1) -> Dictionary:
	var pool = _questions_list
	if module_id > 0:
		pool = get_questions_by_module(module_id)
	if difficulty > 0:
		pool = pool.filter(func(q): return q.get("difficulty", 1) == difficulty)
	if pool.is_empty():
		pool = _questions_list
	pool.shuffle()
	return pool[0] if pool.size() > 0 else {}


## 检查答案
func check_answer(question_id: String, answer: String) -> Dictionary:
	var question = {}
	for q in _questions_list:
		if q.get("id") == question_id:
			question = q
			break

	if question.is_empty():
		return {"correct": false, "correct_answer": "", "explanation": "题目未找到"}

	var is_correct = question.get("answer", "").to_upper() == answer.to_upper()
	var correct_ans = question.get("answer", "")
	var explanation = question.get("explanation", "暂无解析")
	var knowledge_id = question.get("knowledge_id", "")

	# 记录统计
	session_total += 1
	if is_correct:
		session_correct += 1
	else:
		session_wrong_ids.append(question_id)

	question_answered.emit(question_id, is_correct, correct_ans)

	return {
		"correct": is_correct,
		"correct_answer": correct_ans,
		"explanation": explanation,
		"knowledge_id": knowledge_id
	}


## 开始一轮答题
func start_quiz(module_id: int = 1, difficulty: int = -1, count: int = 1) -> void:
	session_correct = 0
	session_total = 0
	session_module = module_id
	session_wrong_ids.clear()
	is_quiz_active = true

	var question = get_random_question(module_id, difficulty)
	if question.is_empty():
		push_error("[ExamManager] 没有可用的题目，模块: %d" % module_id)
		is_quiz_active = false
		return

	current_question = question
	trigger_quiz.emit(module_id, difficulty)


## 获取下一题
func next_question(module_id: int = -1, difficulty: int = -1) -> Dictionary:
	if module_id <= 0:
		module_id = session_module
	var question = get_random_question(module_id, difficulty)
	if question.is_empty():
		finish_quiz()
		return {}
	current_question = question
	return current_question


## 结束本轮答题
func finish_quiz() -> void:
	is_quiz_active = false
	quiz_completed.emit(session_correct, session_total, session_module)
	print("[ExamManager] 答题结束: %d/%d 正确" % [session_correct, session_total])


## 获取模块信息
func get_module_info(module_id: int) -> Dictionary:
	var modules = _knowledge_data.get("modules", [])
	for m in modules:
		if m.get("id") == module_id:
			return m
	return {}


## 获取考点信息
func get_knowledge_info(knowledge_id: String) -> Dictionary:
	var modules = _knowledge_data.get("modules", [])
	for m in modules:
		for kp in m.get("knowledge_points", []):
			if kp.get("id") == knowledge_id:
				return kp
	return {}


## 获取植物信息
func get_plant_info(plant_id: String) -> Dictionary:
	for p in _plant_map.get("plants", []):
		if p.get("id") == plant_id:
			return p
	return {}


## 获取错题列表
func get_wrong_questions() -> Array:
	var result: Array = []
	for qid in session_wrong_ids:
		for q in _questions_list:
			if q.get("id") == qid:
				result.append(q)
				break
	return result
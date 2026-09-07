extends Control
class_name ExamPanel

## 答题面板 - 波清后弹出，展示题目、选项、解析

signal answer_submitted(is_correct: bool)
signal panel_closed()

## 节点引用
@onready var label_question: Label = %LabelQuestion
@onready var label_module: Label = %LabelModule
@onready var label_score: Label = %LabelScore
@onready var label_explanation: Label = %LabelExplanation
@onready var label_knowledge: Label = %LabelKnowledge
@onready var btn_a: BaseButton = %BtnA
@onready var btn_b: BaseButton = %BtnB
@onready var btn_c: BaseButton = %BtnC
@onready var btn_d: BaseButton = %BtnD
@onready var btn_continue: BaseButton = %BtnContinue
@onready var panel_feedback: Panel = %PanelFeedback
@onready var panel_question: Panel = %PanelQuestion
@onready var timer_auto_close: Timer = %TimerAutoClose

var _current_question: Dictionary = {}
var _answered: bool = false
var _module_id: int = 1
var _difficulty: int = -1
var _question_count: int = 0
var _max_questions: int = 1


func _ready() -> void:
	hide()
	panel_feedback.hide()
	btn_continue.hide()
	_connect_buttons()


func _connect_buttons() -> void:
	btn_a.pressed.connect(_on_option_pressed.bind(&quot;A&quot;))
	btn_b.pressed.connect(_on_option_pressed.bind(&quot;B&quot;))
	btn_c.pressed.connect(_on_option_pressed.bind(&quot;C&quot;))
	btn_d.pressed.connect(_on_option_pressed.bind(&quot;D&quot;))
	btn_continue.pressed.connect(_on_continue_pressed)


## 显示答题面板
func show_quiz(module_id: int = 1, difficulty: int = -1, max_questions: int = 1) -> void:
	_module_id = module_id
	_difficulty = difficulty
	_max_questions = max_questions
	_question_count = 0
	_show_next_question()


## 显示下一题
func _show_next_question() -> void:
	if _question_count >= _max_questions:
		ExamManager.finish_quiz()
		_close_panel()
		return

	_answered = false
	_question_count += 1

	var question = ExamManager.get_random_question(_module_id, _difficulty) if _question_count == 1 else ExamManager.next_question(_module_id, _difficulty)
	if question.is_empty():
		_close_panel()
		return

	_current_question = question
	_update_ui()
	appear()


## 更新UI显示
func _update_ui() -> void:
	# 题目
	label_question.text = _current_question.get(&quot;question&quot;, &quot;加载题目失败&quot;)

	# 选项
	var options = _current_question.get(&quot;options&quot;, [])
	btn_a.get_node(&quot;Label&quot;).text = options[0] if options.size() &gt; 0 else &quot;A. &quot;
	btn_b.get_node(&quot;Label&quot;).text = options[1] if options.size() &gt; 1 else &quot;B. &quot;
	btn_c.get_node(&quot;Label&quot;).text = options[2] if options.size() &gt; 2 else &quot;C. &quot;
	btn_d.get_node(&quot;Label&quot;).text = options[3] if options.size() &gt; 3 else &quot;D. &quot;

	# 模块和分值
	var module_info = ExamManager.get_module_info(_module_id)
	label_module.text = &quot;第%d章: %s&quot; % [_module_id, module_info.get(&quot;name&quot;, &quot;&quot;)]
	label_score.text = &quot;得分: %d/%d&quot; % [ExamManager.session_correct, ExamManager.session_total]

	# 隐藏反馈
	panel_feedback.hide()
	btn_continue.hide()

	# 启用所有选项按钮
	for btn in [btn_a, btn_b, btn_c, btn_d]:
		btn.disabled = false


## 选项点击
func _on_option_pressed(option: String) -> void:
	if _answered:
		return
	_answered = true

	# 禁用所有选项
	for btn in [btn_a, btn_b, btn_c, btn_d]:
		btn.disabled = true

	# 检查答案
	var result = ExamManager.check_answer(_current_question.get(&quot;id&quot;, &quot;&quot;), option)
	_update_score()

	# 显示反馈
	label_explanation.text = result.get(&quot;explanation&quot;, &quot;暂无解析&quot;)

	# 显示考点知识
	var knowledge = ExamManager.get_knowledge_info(result.get(&quot;knowledge_id&quot;, &quot;&quot;))
	if not knowledge.is_empty():
		label_knowledge.text = &quot;考点: %s\n%s&quot; % [knowledge.get(&quot;name&quot;, &quot;&quot;), knowledge.get(&quot;formula&quot;, &quot;&quot;)]
	else:
		label_knowledge.text = &quot;&quot;

	# 高亮正确选项
	_highlight_correct(result.get(&quot;correct_answer&quot;, &quot;A&quot;))

	panel_feedback.show()
	btn_continue.show()
	answer_submitted.emit(result.get(&quot;correct&quot;, false))


## 高亮正确选项
func _highlight_correct(correct_answer: String) -> void:
	var btn_map = {&quot;A&quot;: btn_a, &quot;B&quot;: btn_b, &quot;C&quot;: btn_c, &quot;D&quot;: btn_d}
	for key in btn_map:
		var btn = btn_map[key]
		if key == correct_answer:
			btn.modulate = Color(0.3, 1.0, 0.3)  # 绿色
		else:
			btn.modulate = Color(0.5, 0.5, 0.5)  # 灰色


## 更新分数显示
func _update_score() -> void:
	label_score.text = &quot;得分: %d/%d&quot; % [ExamManager.session_correct, ExamManager.session_total]


## 继续按钮
func _on_continue_pressed() -> void:
	# 重置按钮颜色
	for btn in [btn_a, btn_b, btn_c, btn_d]:
		btn.modulate = Color.WHITE

	# 到下一题或关闭
	if _question_count &lt; _max_questions:
		_show_next_question()
	else:
		ExamManager.finish_quiz()
		_close_panel()


## 淡入
func appear() -> void:
	show()
	modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(self, &quot;modulate&quot;, Color.WHITE, 0.3)


## 淡出关闭
func _close_panel() -> void:
	var tween = create_tween()
	tween.tween_property(self, &quot;modulate&quot;, Color(1, 1, 1, 0), 0.2)
	await tween.finished
	hide()
	panel_closed.emit()
extends Node2D
class_name QuizGate

## 答题门 - 波清后出现在战场上的视觉元素
## 表示答题即将开始，提供视觉反馈

signal gate_entered()

## 答题门参数
@export var module_id: int = 1
@export var difficulty: int = -1
@export var question_count: int = 1

## 节点引用
@onready var sprite: Sprite2D = %SpriteGate
@onready var label: Label = %LabelGate
@onready var area: Area2D = %AreaGate
@onready var animation: AnimationPlayer = %AnimationPlayer


func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	ExamManager.trigger_quiz.connect(_on_global_quiz_triggered)


## 初始化答题门
func init_gate(mod_id: int = 1, diff: int = -1, count: int = 1) -> void:
	module_id = mod_id
	difficulty = diff
	question_count = count
	label.text = "第%d章\n答题" % module_id


## 当玩家/植物进入触发区域
func _on_body_entered(body: Node) -> void:
	gate_entered.emit()
	if not ExamManager.is_quiz_active:
		ExamManager.start_quiz(module_id, difficulty, question_count)
		queue_free()


## 全局答题触发时播放动画
func _on_global_quiz_triggered(mod_id: int, _diff: int) -> void:
	if mod_id == module_id and animation:
		animation.play("gate_appear")

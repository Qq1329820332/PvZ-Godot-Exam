extends Control
class_name KnowledgeTip

## 知识提示 - 植物放置时浮出的知识点提示

## 显示参数
@export var display_duration: float = 4.0
@export var fade_duration: float = 0.5

## 节点引用
@onready var label_name: Label = %LabelName
@onready var label_knowledge: Label = %LabelKnowledge
@onready var label_module: Label = %LabelModule


## 显示知识提示
func show_tip(plant_name: String, knowledge_name: String, module_name: String) -> void:
	label_name.text = plant_name
	label_knowledge.text = knowledge_name
	label_module.text = module_name
	appear()


## 显示从植物类型获取的知识提示
func show_tip_from_plant(plant_type: int) -> void:
	var plant_data = PlantKnowledgeBinder.get_plant_data(plant_type)
	if plant_data.is_empty():
		queue_free()
		return

	var plant_name = plant_data.get("name", "未知植物")
	var primary_kid = plant_data.get("primary_knowledge", "")
	var module_id = plant_data.get("module", 0)

	var knowledge_info = ExamManager.get_knowledge_info(primary_kid)
	var knowledge_name = knowledge_info.get("name", "")

	var module_info = ExamManager.get_module_info(module_id)
	var module_name = module_info.get("name", "")

	show_tip(plant_name, knowledge_name, "第%d章: %s" % [module_id, module_name])


## 淡入显示
func appear() -> void:
	show()
	modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, fade_duration)
	tween.tween_interval(display_duration)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), fade_duration)
	await tween.finished
	queue_free()

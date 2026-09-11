class_name LevelCompleteCard
extends PanelContainer
## The "level complete" card: title, level name, one star icon per possible
## star (earned ones gold, missed ones grey), the reward if any. Shown by the
## GameHUD when a LevelController completes, hidden when the hub loads.

const EARNED := Color(1.0, 0.85, 0.25)
const MISSED := Color(0.35, 0.35, 0.4)

@onready var level_label: Label = $Margin/Rows/LevelName
@onready var star_row: HBoxContainer = $Margin/Rows/Stars
@onready var reward_label: Label = $Margin/Rows/Reward
@onready var title_label: Label = $Margin/Rows/Title
@onready var footer_label: Label = $Margin/Rows/Footer

var shown_stars := 0
var shown_total := 0


func _ready() -> void:
	visible = false
	title_label.text = tr(&"CARD_LEVEL_COMPLETE")
	footer_label.text = tr(&"CARD_RETURNING")


func show_result(definition: LevelDefinition, stars: int, total: int, first_time: bool) -> void:
	shown_stars = stars
	shown_total = total
	level_label.text = tr(definition.display_name) if definition else ""
	for child in star_row.get_children():
		child.queue_free()
	for i in maxi(total, stars):
		var icon := StarIcon.new()
		icon.star_size = 44.0
		icon.fill_color = EARNED if i < stars else MISSED
		star_row.add_child(icon)
	var rewards := PackedStringArray()
	if definition and first_time:
		for id in definition.reward_abilities:
			rewards.append(AbilityComponent.display_name(StringName(id)))
	reward_label.visible = not rewards.is_empty()
	reward_label.text = tr(&"CARD_REWARD") % ", ".join(rewards) if not rewards.is_empty() else ""
	visible = true
	# Pop in.
	pivot_offset = size * 0.5
	scale = Vector2(0.6, 0.6)
	modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.2)


func dismiss() -> void:
	visible = false

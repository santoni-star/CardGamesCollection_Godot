extends Panel
## Visual representation of a single Card. Works without external art assets.

@onready var rank_top: Label = $RankLabelTop
@onready var suit_center: Label = $SuitLabelCenter
@onready var rank_bottom: Label = $RankLabelBottom
@onready var back_pattern: Control = $BackPattern

var card: Card
var face_up: bool = true

func setup(p_card: Card, p_face_up: bool = true) -> void:
	card = p_card
	face_up = p_face_up
	_refresh()

func flip(p_face_up: bool) -> void:
	face_up = p_face_up
	_refresh()

## Animated version: shrinks, swaps the face at the midpoint, grows back.
func animate_flip_to(p_card: Card, p_face_up: bool) -> void:
	CardFX.flip(self, func(): setup(p_card, p_face_up))

## Fade + pop this card into place. Call right after adding it to the tree.
func animate_in(delay: float = 0.0) -> void:
	CardFX.deal_in(self, delay)

## Sweep this card off toward `direction` (local offset) and free it.
func animate_collect(direction: Vector2) -> void:
	CardFX.collect_and_free(self, direction)

func _refresh() -> void:
	if card == null or not face_up:
		rank_top.text = ""
		suit_center.text = ""
		rank_bottom.text = ""
		back_pattern.visible = true
		self_modulate = Color(1, 1, 1)
		return

	back_pattern.visible = false
	self_modulate = Color(1, 1, 1)
	var label := card.rank_label()
	var symbol := card.suit_symbol()
	var color := card.suit_color()

	rank_top.text = label
	rank_top.add_theme_color_override("font_color", color)

	suit_center.text = symbol
	suit_center.add_theme_color_override("font_color", color)

	rank_bottom.text = label
	rank_bottom.add_theme_color_override("font_color", color)

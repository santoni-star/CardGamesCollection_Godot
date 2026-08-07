extends Button
## A clickable card used in the player's hand row.
## Used both for playing a card (Playing phase) and selecting cards to discard (Discarding phase).

@onready var rank_top: Label = $RankLabelTop
@onready var suit_center: Label = $SuitLabelCenter
@onready var rank_bottom: Label = $RankLabelBottom

var card: Card
var selected: bool = false:
	set(v):
		selected = v
		modulate = Color(0.55, 0.85, 1.0) if selected else Color(1, 1, 1)

func setup(p_card: Card) -> void:
	card = p_card
	var label := card.rank_label()
	var symbol := card.suit_symbol()
	var color := card.suit_color()
	rank_top.text = label
	rank_top.add_theme_color_override("font_color", color)
	suit_center.text = symbol
	suit_center.add_theme_color_override("font_color", color)
	rank_bottom.text = label
	rank_bottom.add_theme_color_override("font_color", color)

## Fade + pop this card into place. Call right after adding it to the tree.
func animate_in(delay: float = 0.0) -> void:
	CardFX.deal_in(self, delay)

## Brief shake to signal an illegal move (e.g. "must follow suit").
func animate_reject() -> void:
	CardFX.shake(self)

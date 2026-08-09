extends Control
## Косинка (Klondike Solitaire) — повноцінна версія.
## Правила: 7 стовпців (спадні, чергування кольорів), сток → скид по 1,
## 4 фундаменти A→K за мастю. Всі анімації через CardFX.
##
## Взаємодія:
##   - Клік по стоку  — перегорнути карту в скид (або перевернути скид назад).
##   - Клік по карті  — спершу спроба покласти на фундамент (авто);
##                      інакше карта/група вибирається для переміщення.
##   - Подвійний клік — авто-переміщення на фундамент.
##   - Клік по стовпцю/фундаменту — покласти вибране туди.
##   - Клік по вибраній карті — скасувати вибір.

const Deck = preload("res://scripts/card/Deck.gd")
const CardFX = preload("res://scripts/core/CardFX.gd")
const Card = preload("res://scripts/card/Card.gd")
const CardViewScene := preload("res://scenes/components/CardView.tscn")

const CARD_SIZE := Vector2(88, 124)
const STOCK_POS := Vector2(40, 100)
const WASTE_POS := Vector2(165, 100)
const FOUND_Y := 100.0
const FOUND_X := [820.0, 930.0, 1040.0, 1150.0]
const TAB_Y := 300.0
const TAB_X := [40.0, 145.0, 250.0, 355.0, 460.0, 565.0, 670.0]
const TAB_DOWN_STEP := 18.0
const TAB_UP_STEP := 30.0

@onready var back_button: Button = $TopBar/BackButton
@onready var new_game_button: Button = $TopBar/NewGameButton
@onready var moves_label: Label = $TopBar/MovesLabel
@onready var time_label: Label = $TopBar/TimeLabel
@onready var status_label: Label = $StatusLabel
@onready var board: Control = $Board

var stock: Array[Card] = []
var waste: Array[Card] = []
var foundations: Array = [[], [], [], []]
var tableau: Array = [[], [], [], [], [], [], []]

var stock_slot: Panel
var stock_view: Control
var waste_views: Array[Control] = []
var foundation_slots: Array[Panel] = []
var foundation_views: Array = [[], [], [], []]
var tableau_slots: Array[Panel] = []
var tableau_views: Array = [[], [], [], [], [], [], []]

var selected_col: int = -1
var selected_idx: int = -1
var moves: int = 0
var elapsed: float = 0.0
var game_over: bool = false

func _ready() -> void:
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	new_game_button.pressed.connect(_on_new_game)
	_build_slots()
	new_game()

func _process(delta: float) -> void:
	if not game_over:
		elapsed += delta
		time_label.text = _format_time(elapsed)

# ---------------------------------------------------------------------------
# SETUP
# ---------------------------------------------------------------------------

func _build_slots() -> void:
	stock_slot = _make_slot(STOCK_POS)
	stock_slot.gui_input.connect(_on_stock_slot_input)
	board.add_child(stock_slot)

	for i in 4:
		var s := _make_slot(Vector2(FOUND_X[i], FOUND_Y))
		foundation_slots.append(s)
		s.gui_input.connect(_on_foundation_slot_input.bind(i))
		board.add_child(s)

	for i in 7:
		var s := _make_slot(Vector2(TAB_X[i], TAB_Y))
		tableau_slots.append(s)
		s.gui_input.connect(_on_tableau_slot_input.bind(i))
		board.add_child(s)

func _make_slot(pos: Vector2) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = CARD_SIZE
	p.position = pos
	p.size = CARD_SIZE
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 1, 1, 0.15)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_right = 8
	sb.corner_radius_bottom_left = 8
	p.add_theme_stylebox_override("panel", sb)
	return p

func _on_new_game() -> void:
	new_game()

func new_game() -> void:
	stock.clear()
	waste.clear()
	for f in 4:
		foundations[f].clear()
	for t in 7:
		tableau[t].clear()
	_clear_views()

	var deck := Deck.new()
	deck.build_standard()
	deck.shuffle()

	for col in 7:
		for _i in col + 1:
			tableau[col].append(deck.draw_card())

	while not deck.is_empty():
		stock.append(deck.draw_card())

	_ensure_reveal_state()
	selected_col = -1
	selected_idx = -1
	moves = 0
	elapsed = 0.0
	game_over = false
	moves_label.text = "Ходи: 0"
	time_label.text = "00:00"
	status_label.text = ""
	_render_all(true)

func _clear_views() -> void:
	if stock_view != null:
		stock_view.queue_free()
		stock_view = null
	for v in waste_views:
		v.queue_free()
	waste_views.clear()
	for f in 4:
		for v in foundation_views[f]:
			v.queue_free()
		foundation_views[f].clear()
	for t in 7:
		for v in tableau_views[t]:
			v.queue_free()
		tableau_views[t].clear()

# ---------------------------------------------------------------------------
# RENDERING
# ---------------------------------------------------------------------------

func _render_all(animate_deal: bool = false) -> void:
	_clear_views()

	# Stock: face-down stack with a card view; empty => show slot only.
	if not stock.is_empty():
		stock_view = _make_card_view(null, false)
		stock_view.position = STOCK_POS
		stock_view.gui_input.connect(_on_stock_view_input)

	# Waste: last up to 3 cards fanned right; only the top card is clickable.
	var n := waste.size()
	for i in n:
		var cv: Control = _make_card_view(waste[i], true)
		cv.position = WASTE_POS + Vector2(min((n - 1 - i) * 18, 36), 0)
		waste_views.append(cv)
		if i == n - 1:
			cv.gui_input.connect(_on_waste_view_input)

	# Foundations.
	for f in 4:
		var count: int = foundations[f].size()
		if count > 0:
			var cv: Control = _make_card_view(foundations[f][count - 1], true)
			cv.position = Vector2(FOUND_X[f], FOUND_Y)
			foundation_views[f].append(cv)
			cv.gui_input.connect(_on_foundation_card_input.bind(f))

	# Tableau: stacked cards, face-down compressed, face-up spread.
	for col in 7:
		var cards: Array = tableau[col]
		var count: int = cards.size()
		if count == 0:
			continue
		var y := TAB_Y
		for i in count:
			var face_up: bool = i == count - 1 or _is_face_up(col, i)
			var cv: Control = _make_card_view(cards[i], face_up)
			cv.position = Vector2(TAB_X[col], y)
			tableau_views[col].append(cv)
			if face_up:
				cv.gui_input.connect(_on_tableau_card_input.bind(col, i))
				y += TAB_UP_STEP
			else:
				y += TAB_DOWN_STEP

	_refresh_selection_highlight()
	_check_win()

func _is_face_up(col: int, idx: int) -> bool:
	# A card is face-up if it was ever revealed: top card always, or the
	# column was dealt as face-up. We track by: idx >= count-1 is top.
	# Revealed cards are those at index >= first_face_up[col].
	# Simple model: every card below the top that is part of a run is face-up;
	# we store face-up state implicitly: face-up iff it was moved/revealed.
	# For dealt columns: only the last card starts face-up; when the top card
	# is moved away, the next one is flipped by _flip_top.
	# We persist revealed state via `tableau_revealed`.
	return _tableau_face_up[col].has(idx)

var _tableau_face_up: Array = []

func _ensure_reveal_state() -> void:
	_tableau_face_up = []
	for col in 7:
		var set := {}
		if not tableau[col].is_empty():
			set[tableau[col].size() - 1] = true
		_tableau_face_up.append(set)

func _make_card_view(card: Card, face_up: bool) -> Control:
	var cv = CardViewScene.instantiate()
	board.add_child(cv)  # must be in tree before setup(): CardView uses @onready
	cv.setup(card, face_up)
	return cv

# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------

func _on_stock_slot_input(event: InputEvent) -> void:
	print(\"Stock slot clicked\")
	if _is_left_click(event):
		_draw_from_stock()

func _on_stock_view_input(event: InputEvent) -> void:
	if _is_left_click(event):
		_draw_from_stock()

func _draw_from_stock() -> void:
	if game_over:
		return
	if stock.is_empty():
		if waste.is_empty():
			return
		# Recycle: waste becomes the stock again; top card (last drawn) draws first.
		stock = waste.duplicate()
		waste.clear()
		moves += 1
		_update_hud()
		_render_all()
		return
	var card: Card = stock.pop_back()
	waste.append(card)
	moves += 1
	_update_hud()
	_render_all()

func _on_waste_view_input(event: InputEvent) -> void:
	if game_over or waste.is_empty():
		return
	if _is_left_click(event):
		var card: Card = waste[waste.size() - 1]
		if not _try_auto_to_foundation(card, "waste", -1, waste.size() - 1):
			# Selecting from waste: treat as a single-card selection.
			_select_run(-1, -1)  # clear previous
			selected_col = -2  # marker: waste
			selected_idx = waste.size() - 1
			_refresh_selection_highlight()

func _on_foundation_card_input(event: InputEvent, f: int) -> void:
	if _is_left_click(event):
		_try_place_selected_on_foundation(f)

func _on_foundation_slot_input(event: InputEvent, f: int) -> void:
	if _is_left_click(event):
		_try_place_selected_on_foundation(f)

func _on_tableau_card_input(event: InputEvent, col: int, idx: int) -> void:
	if game_over:
		return
	if not _is_left_click(event):
		return
	# Clicking a card inside the selected run cancels the selection (single click).
	if selected_col == col and idx >= selected_idx and not event.double_click:
		_selection_clear()
		_refresh_selection_highlight()
		return
	if selected_col != -1:
		# Try to drop a selected run onto this column.
		if _try_place_selected_on_tableau(col):
			return
		# If the clicked card itself can't accept, (re)select a run from it.
	if _is_face_up(col, idx):
		var card: Card = tableau[col][idx]
		if idx == tableau[col].size() - 1:
			if event.double_click:
				if _try_auto_to_foundation(card, "tableau", col, idx):
					return
			if _try_auto_to_foundation(card, "tableau", col, idx):
				return
		_select_run(col, idx)
		_refresh_selection_highlight()

func _on_tableau_slot_input(event: InputEvent, col: int) -> void:
	if _is_left_click(event) and selected_col != -1:
		_try_place_selected_on_tableau(col)

# ---------------------------------------------------------------------------
# SELECTION
# ---------------------------------------------------------------------------

func _select_run(col: int, idx: int) -> void:
	selected_col = col
	selected_idx = idx

func _selected_cards() -> Array:
	if selected_col == -2:  # waste
		if waste.is_empty():
			return []
		return [waste[waste.size() - 1]]
	if selected_col < 0:
		return []
	return tableau[selected_col].slice(selected_idx)

func _refresh_selection_highlight() -> void:
	for col in 7:
		for i in tableau_views[col].size():
			var cv: Control = tableau_views[col][i]
			var is_sel: bool = selected_col == col and i >= selected_idx
			cv.modulate = Color(1, 1, 0.75) if is_sel else Color(1, 1, 1)
	if selected_col == -2 and not waste_views.is_empty():
		waste_views[waste_views.size() - 1].modulate = Color(1, 1, 0.75)

# ---------------------------------------------------------------------------
# RULES
# ---------------------------------------------------------------------------

func _can_place_foundation(f: int, card: Card) -> bool:
	if foundations[f].is_empty():
		return card.rank == 1
	var top: Card = foundations[f][foundations[f].size() - 1]
	return top.suit == card.suit and card.rank == top.rank + 1

func _can_place_tableau(col: int, card: Card) -> bool:
	if tableau[col].is_empty():
		return card.rank == 13
	var top: Card = tableau[col][tableau[col].size() - 1]
	if not _is_face_up(col, tableau[col].size() - 1):
		return false
	return card.rank == top.rank - 1 and _opposite_color(card, top)

func _opposite_color(a: Card, b: Card) -> bool:
	return _is_red(a) != _is_red(b)

func _is_red(c: Card) -> bool:
	return c.suit == Card.Suit.HEARTS or c.suit == Card.Suit.DIAMONDS

func _try_auto_to_foundation(card: Card, src_zone: String, col: int, idx: int) -> bool:
	# Only the top card of a tableau column can go to a foundation.
	if src_zone == "tableau" and idx != tableau[col].size() - 1:
		return false
	for f in 4:
		if _can_place_foundation(f, card):
			_move_to_foundation(src_zone, col, idx, f)
			return true
	return false

func _move_to_foundation(src_zone: String, col: int, idx: int, f: int) -> void:
	var card: Card
	if src_zone == "waste":
		card = waste.pop_back()
	else:
		card = tableau[col][idx]
		tableau[col].remove_at(idx)
		_auto_flip(col)
	foundations[f].append(card)
	moves += 1
	_update_hud()
	_render_all()
	_check_win()

func _try_place_selected_on_tableau(col: int) -> bool:
	var cards: Array = _selected_cards()
	if cards.is_empty():
		return false
	var target_col := col
	if selected_col == -2:
		if not _can_place_tableau(target_col, cards[0]):
			return false
		var card: Card = waste.pop_back()
		tableau[target_col].append(card)
		_tableau_face_up[target_col][tableau[target_col].size() - 1] = true
	else:
		var src := selected_col
		var from_idx := selected_idx
		if src == target_col:
			_selection_clear()
			return false
		if not _can_place_tableau(target_col, cards[0]):
			return false
		var run: Array = tableau[src].slice(from_idx)
		tableau[src].resize(from_idx)
		tableau[target_col].append_array(run)
		# All moved cards stay face-up in the target column.
		for k in run.size():
			_tableau_face_up[target_col][tableau[target_col].size() - run.size() + k] = true
		_auto_flip(src)
	moves += 1
	_selection_clear()
	_update_hud()
	_render_all()
	return true

func _try_place_selected_on_foundation(f: int) -> void:
	var cards: Array = _selected_cards()
	if cards.is_empty() or cards.size() > 1:
		return
	if not _can_place_foundation(f, cards[0]):
		return
	if selected_col == -2:
		waste.pop_back()
	else:
		tableau[selected_col].remove_at(selected_idx)
		_auto_flip(selected_col)
	foundations[f].append(cards[0])
	moves += 1
	_selection_clear()
	_update_hud()
	_render_all()
	_check_win()

func _auto_flip(col: int) -> void:
	# After removing a card, the new top of a non-empty column becomes face-up.
	if not tableau[col].is_empty():
		_tableau_face_up[col][tableau[col].size() - 1] = true

func _selection_clear() -> void:
	selected_col = -1
	selected_idx = -1

# ---------------------------------------------------------------------------
# HUD / WIN
# ---------------------------------------------------------------------------

func _update_hud() -> void:
	moves_label.text = "Ходи: %d" % moves

func _format_time(t: float) -> String:
	var total: int = int(t)
	return "%02d:%02d" % [total / 60, total % 60]

func _check_win() -> void:
	if game_over:
		return
	for f in 4:
		if foundations[f].size() != 13:
			return
	game_over = true
	status_label.text = "Перемога! %s" % _format_time(elapsed)
	CardFX.pulse(status_label)

func _is_left_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed

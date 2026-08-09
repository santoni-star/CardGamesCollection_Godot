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

var moves: int = 0
var elapsed: float = 0.0
var game_over: bool = false

# Drag & drop state.
var _drag_active: bool = false
var _drag_src: String = ""          # "waste" | "tableau"
var _drag_col: int = -1
var _drag_idx: int = -1
var _drag_offset: Vector2 = Vector2.ZERO   # cursor pos inside the grabbed card
var _drag_moved: bool = false
var _ghost_views: Array[Control] = []
const DRAG_THRESHOLD := 8.0

func _ready() -> void:
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	new_game_button.pressed.connect(_on_new_game)
	# Bulletproof pass-through: every Control except Buttons becomes
	# MOUSE_FILTER_IGNORE, so nothing can swallow board clicks. Buttons keep
	# their default STOP and eat their own clicks in the GUI phase; all other
	# clicks/motion reach _unhandled_input below (viewport coordinates).
	_make_pass_through(self)
	_build_slots()
	new_game()

func _make_pass_through(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			continue  # buttons keep STOP: they consume their own clicks
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_make_pass_through(child)

## Board-level input. Buttons on the TopBar consume their clicks in the GUI
## phase; all other clicks/motion land here as unhandled input.
func _unhandled_input(event: InputEvent) -> void:
	_on_board_input(event)

func _process(delta: float) -> void:
	if not game_over:
		elapsed += delta
		time_label.text = _format_time(elapsed)

# ---------------------------------------------------------------------------
# SETUP
# ---------------------------------------------------------------------------

func _build_slots() -> void:
	stock_slot = _make_slot(STOCK_POS)
	board.add_child(stock_slot)

	for i in 4:
		var s := _make_slot(Vector2(FOUND_X[i], FOUND_Y))
		foundation_slots.append(s)
		board.add_child(s)

	for i in 7:
		var s := _make_slot(Vector2(TAB_X[i], TAB_Y))
		tableau_slots.append(s)
		board.add_child(s)

func _make_slot(pos: Vector2) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = CARD_SIZE
	p.position = pos
	p.size = CARD_SIZE
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_clear_ghosts()

	# Stock: face-down stack with a card view; empty => show slot only.
	if not stock.is_empty():
		stock_view = _make_card_view(null, false)
		stock_view.position = STOCK_POS

	# Waste: last up to 3 cards fanned right; only the top card is draggable.
	var n := waste.size()
	for i in n:
		var cv: Control = _make_card_view(waste[i], true)
		cv.position = WASTE_POS + Vector2(min((n - 1 - i) * 18, 36), 0)
		waste_views.append(cv)

	# Foundations.
	for f in 4:
		var count: int = foundations[f].size()
		if count > 0:
			var cv: Control = _make_card_view(foundations[f][count - 1], true)
			cv.position = Vector2(FOUND_X[f], FOUND_Y)
			foundation_views[f].append(cv)

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
				y += TAB_UP_STEP
			else:
				y += TAB_DOWN_STEP

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
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(cv)  # must be in tree before setup(): CardView uses @onready
	cv.setup(card, face_up)
	return cv

# ---------------------------------------------------------------------------
# INPUT (drag & drop, hit-testing on the board)
# ---------------------------------------------------------------------------

func _on_board_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_press(event.position)
		else:
			_on_left_release(event.position)
	elif event is InputEventMouseMotion and _drag_active:
		# Only count as a real drag once the cursor leaves the grab area.
		if (event.position - (_drag_anchor() + _drag_offset)).length() > DRAG_THRESHOLD:
			_drag_moved = true
			_update_drag(event.position)

func _on_left_press(pos: Vector2) -> void:
	if game_over:
		return
	# Stock: draw a card (either on the stock slot or its card view).
	if _rect_at(STOCK_POS).has_point(pos):
		_draw_from_stock()
		return
	# Waste top card: start a drag.
	if not waste.is_empty() and _rect_at(WASTE_POS + Vector2(min((waste.size() - 1) * 18, 36), 0)).has_point(pos):
		_start_drag("waste", -1, -1, pos)
		return
	# Tableau face-up card: start a drag of the run from that card.
	for col in 7:
		var views: Array = tableau_views[col]
		for i in range(views.size() - 1, -1, -1):
			if not _is_face_up(col, i):
				continue
			if _card_rect(col, i).has_point(pos):
				_start_drag("tableau", col, i, pos)
				return
	# Foundation top card: single click does nothing; use drag to place.
	return

func _draw_from_stock() -> void:
	if game_over:
		return
	if stock.is_empty():
		if waste.is_empty():
			return
		# Recycle: waste becomes the stock again; top card draws first.
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

func _on_left_release(pos: Vector2) -> void:
	if not _drag_active:
		return
	# A plain click (no drag) on a top card auto-sends it to a foundation.
	if not _drag_moved:
		_try_click_to_foundation()
		_cancel_drag()
		return
	# Decide the drop target from the release position.
	for f in 4:
		if _rect_at(Vector2(FOUND_X[f], FOUND_Y)).has_point(pos):
			_finish_drag_to_foundation(f)
			return
	for col in 7:
		if _column_rect(col).has_point(pos):
			_finish_drag_to_tableau(col)
			return
	_cancel_drag()

func _try_click_to_foundation() -> void:
	var cards: Array = _selected_cards()
	if cards.size() != 1:
		return
	for f in 4:
		if _can_place_foundation(f, cards[0]):
			_execute_move_to_foundation(f)
			return

func _start_drag(src: String, col: int, idx: int, pos: Vector2) -> void:
	_drag_active = true
	_drag_src = src
	_drag_col = col
	_drag_idx = idx
	_drag_moved = false
	var anchor: Vector2
	if src == "waste":
		anchor = _rect_at(WASTE_POS + Vector2(min((waste.size() - 1) * 18, 36), 0)).position
	else:
		anchor = _card_rect(col, idx).position
	_drag_offset = pos - anchor
	_build_ghosts()

func _build_ghosts() -> void:
	_clear_ghosts()
	var cards: Array = _selected_cards()
	for i in cards.size():
		var cv: Control = _make_card_view(cards[i], true)
		cv.z_index = 100
		cv.position = _drag_anchor() + Vector2(0, i * TAB_UP_STEP)
		_ghost_views.append(cv)

func _update_drag(pos: Vector2) -> void:
	var base: Vector2 = pos - _drag_offset
	for i in _ghost_views.size():
		_ghost_views[i].position = base + Vector2(0, i * TAB_UP_STEP)

func _finish_drag_to_foundation(f: int) -> void:
	var cards: Array = _selected_cards()
	_clear_ghosts()
	_drag_active = false
	if cards.size() != 1:
		return
	if not _can_place_foundation(f, cards[0]):
		return
	_execute_move_to_foundation(f)

func _finish_drag_to_tableau(col: int) -> void:
	var cards: Array = _selected_cards()
	_clear_ghosts()
	_drag_active = false
	if cards.is_empty():
		return
	# Don't drop a run onto its own column.
	if _drag_src == "tableau" and _drag_col == col:
		return
	if not _can_place_tableau(col, cards[0]):
		return
	_execute_move_to_tableau(col)

func _cancel_drag() -> void:
	_clear_ghosts()
	_drag_active = false
	_drag_moved = false

func _execute_move_to_foundation(f: int) -> void:
	var src := _drag_src
	var col := _drag_col
	var idx := _drag_idx
	var card: Card
	if src == "waste":
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

func _execute_move_to_tableau(col: int) -> void:
	var src := _drag_src
	var from_idx := _drag_idx
	if src == "waste":
		var card: Card = waste.pop_back()
		tableau[col].append(card)
		_tableau_face_up[col][tableau[col].size() - 1] = true
	else:
		var src_col := _drag_col
		var run: Array = tableau[src_col].slice(from_idx)
		tableau[src_col].resize(from_idx)
		tableau[col].append_array(run)
		for k in run.size():
			_tableau_face_up[col][tableau[col].size() - run.size() + k] = true
		_auto_flip(src_col)
	moves += 1
	_update_hud()
	_render_all()

func _selected_cards() -> Array:
	if _drag_src == "waste":
		if waste.is_empty():
			return []
		return [waste[waste.size() - 1]]
	if _drag_src == "tableau" and _drag_col >= 0:
		return tableau[_drag_col].slice(_drag_idx)
	return []

func _drag_anchor() -> Vector2:
	if _drag_src == "waste":
		return _rect_at(WASTE_POS + Vector2(min((waste.size() - 1) * 18, 36), 0)).position
	return _card_rect(_drag_col, _drag_idx).position

func _clear_ghosts() -> void:
	for g in _ghost_views:
		if is_instance_valid(g):
			g.queue_free()
	_ghost_views.clear()

func _rect_at(pos: Vector2) -> Rect2:
	return Rect2(pos, CARD_SIZE)

func _card_rect(col: int, idx: int) -> Rect2:
	var y := TAB_Y
	for i in idx:
		y += TAB_UP_STEP if _is_face_up(col, i) else TAB_DOWN_STEP
	return Rect2(Vector2(TAB_X[col], y), CARD_SIZE)

func _column_rect(col: int) -> Rect2:
	# Whole column footprint: from the top slot down past the last card,
	# plus generous drop padding so releases slightly below the stack land.
	var cards: Array = tableau[col]
	var height: float = CARD_SIZE.y + 40.0
	if not cards.is_empty():
		var y := TAB_Y
		for i in cards.size():
			y += TAB_UP_STEP if _is_face_up(col, i) else TAB_DOWN_STEP
		height = maxf(height, y - TAB_Y + CARD_SIZE.y * 0.5 + 40.0)
	return Rect2(Vector2(TAB_X[col], TAB_Y), Vector2(CARD_SIZE.x, height))

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

func _auto_flip(col: int) -> void:
	# After removing a card, the new top of a non-empty column becomes face-up.
	if not tableau[col].is_empty():
		_tableau_face_up[col][tableau[col].size() - 1] = true

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

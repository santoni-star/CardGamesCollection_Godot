extends Control
## Kosynka (Klondike) — rewritten from scratch.
## Interaction model: every card is a Button (same proven approach as Hearts).
## Drag & drop: press card (button_down) -> drag with mouse (_unhandled_input
## motion) -> release (button_up). A plain click on a top card auto-sends it
## to a foundation; clicking the stock draws a card.

const Card = preload("res://scripts/card/Card.gd")

# --- Layout (viewport 1280x720) ------------------------------------------
const CARD_SIZE := Vector2(88, 124)
const STOCK_POS := Vector2(40, 100)
const WASTE_POS := Vector2(165, 100)
const WASTE_FAN := 18.0
const FOUND_X: Array[float] = [820.0, 930.0, 1040.0, 1150.0]
const FOUND_Y := 100.0
const TAB_X: Array[float] = [40.0, 145.0, 250.0, 355.0, 460.0, 565.0, 670.0]
const TAB_Y := 300.0
const TAB_UP_STEP := 34.0    # vertical gap between face-up cards
const TAB_DOWN_STEP := 24.0  # vertical gap between face-down cards
const DRAG_THRESHOLD := 8.0

# --- Node references -------------------------------------------------------
@onready var back_button: Button = $TopBar/BackButton
@onready var new_game_button: Button = $TopBar/NewGameButton
@onready var moves_label: Label = $TopBar/MovesLabel
@onready var time_label: Label = $TopBar/TimeLabel
@onready var status_label: Label = $StatusLabel
@onready var board: Control = $Board

# --- Game state ------------------------------------------------------------
var stock: Array = []              # Array[Card], top = last
var waste: Array = []              # Array[Card], top = last
var foundations: Array = [[], [], [], []]  # Array[Array[Card]]
var tableau: Array = []            # 7 columns of Array[Card], top = last
var _face_up: Array = []           # 7 Dictionaries: col -> {idx: true}
var moves: int = 0
var elapsed: float = 0.0
var game_over: bool = false

# --- Drag & drop state -----------------------------------------------------
var _press_src: Dictionary = {}    # {"type": "waste"|"tableau", "col": int, "idx": int}
var _press_pos: Vector2 = Vector2.ZERO
var _drag_active: bool = false
var _ghosts: Array = []            # Array[Control] - flying card copies

# --- Styleboxes -------------------------------------------------------------
var _sb_card: StyleBoxFlat
var _sb_card_hover: StyleBoxFlat
var _sb_card_pressed: StyleBoxFlat
var _sb_back: StyleBoxFlat
var _sb_slot: StyleBoxFlat

func _ready() -> void:
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	new_game_button.pressed.connect(_on_new_game)
	_build_styleboxes()
	new_game()

func _process(delta: float) -> void:
	if not game_over:
		elapsed += delta
		time_label.text = _format_time(elapsed)

func _format_time(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	return "%02d:%02d" % [m, s]

# ---------------------------------------------------------------------------
# GAME SETUP
# ---------------------------------------------------------------------------

func _build_styleboxes() -> void:
	_sb_card = StyleBoxFlat.new()
	_sb_card.bg_color = Color(1, 1, 1, 1)
	_sb_card.set_border_width_all(2)
	_sb_card.border_color = Color(0.15, 0.15, 0.18, 1)
	_sb_card.set_corner_radius_all(8)
	_sb_card.shadow_color = Color(0, 0, 0, 0.25)
	_sb_card.shadow_size = 3

	_sb_card_hover = StyleBoxFlat.new()
	_sb_card_hover.bg_color = Color(1, 1, 0.92, 1)
	_sb_card_hover.set_border_width_all(2)
	_sb_card_hover.border_color = Color(0.15, 0.15, 0.18, 1)
	_sb_card_hover.set_corner_radius_all(8)
	_sb_card_hover.shadow_color = Color(0, 0, 0, 0.35)
	_sb_card_hover.shadow_size = 4

	_sb_card_pressed = StyleBoxFlat.new()
	_sb_card_pressed.bg_color = Color(0.9, 0.93, 1, 1)
	_sb_card_pressed.set_border_width_all(2)
	_sb_card_pressed.border_color = Color(0.15, 0.15, 0.18, 1)
	_sb_card_pressed.set_corner_radius_all(8)

	_sb_back = StyleBoxFlat.new()
	_sb_back.bg_color = Color(0.09, 0.25, 0.5, 1)
	_sb_back.set_border_width_all(3)
	_sb_back.border_color = Color(0.03, 0.12, 0.3, 1)
	_sb_back.set_corner_radius_all(8)

	_sb_slot = StyleBoxFlat.new()
	_sb_slot.bg_color = Color(1, 1, 1, 0.05)
	_sb_slot.set_border_width_all(2)
	_sb_slot.border_color = Color(1, 1, 1, 0.15)
	_sb_slot.set_corner_radius_all(8)

func _on_new_game() -> void:
	new_game()

func new_game() -> void:
	var deck: Array = []
	for suit in 4:
		for rank in 13:
			deck.append(Card.new(suit, rank + 1))
	deck.shuffle()

	stock.clear()
	waste.clear()
	for f in 4:
		foundations[f].clear()
	tableau.clear()
	_face_up.clear()
	var idx := 0
	for col in 7:
		var col_cards: Array = []
		var fu := {}
		for i in col + 1:
			col_cards.append(deck[idx])
			idx += 1
		fu[col_cards.size() - 1] = true
		tableau.append(col_cards)
		_face_up.append(fu)
	for i in range(idx, deck.size()):
		stock.append(deck[i])

	moves = 0
	elapsed = 0.0
	game_over = false
	moves_label.text = "Ходи: 0"
	time_label.text = "00:00"
	status_label.text = ""
	_render_all()

func _check_win() -> void:
	for f in 4:
		if foundations[f].size() != 13:
			return
	game_over = true
	status_label.text = "Вітаємо! Ви виграли!"

# ---------------------------------------------------------------------------
# RULES
# ---------------------------------------------------------------------------

func _is_face_up(col: int, idx: int) -> bool:
	return bool(_face_up[col].get(idx, false))

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
	var diff_ok: bool = card.rank == top.rank - 1
	var color_ok: bool = (card.suit % 2) != (top.suit % 2)
	return diff_ok and color_ok

## Cards picked up by the current drag (single waste card or a tableau run).
func _dragged_cards() -> Array:
	var cards: Array = []
	if _press_src.get("type", "") == "waste":
		if not waste.is_empty():
			cards.append(waste[waste.size() - 1])
	elif _press_src.get("type", "") == "tableau":
		var col: int = _press_src.get("col", -1)
		var idx: int = _press_src.get("idx", -1)
		if col >= 0 and idx >= 0 and idx < tableau[col].size():
			for i in range(idx, tableau[col].size()):
				cards.append(tableau[col][i])
	return cards

# ---------------------------------------------------------------------------
# RENDERING
# ---------------------------------------------------------------------------

func _clear_board() -> void:
	for c in board.get_children():
		c.queue_free()

func _render_all() -> void:
	_clear_board()
	_ghosts.clear()

	# Stock slot + pile. The stock pile is interactive: click draws a card.
	var stock_slot := _make_slot_btn()
	stock_slot.position = STOCK_POS
	board.add_child(stock_slot)
	if not stock.is_empty():
		var back := _make_card_btn(null, false)
		back.position = STOCK_POS
		back.mouse_filter = Control.MOUSE_FILTER_STOP
		back.button_down.connect(_on_stock_pressed)
		board.add_child(back)

	# Waste: fanned face-up cards; only the top one is interactive.
	for i in waste.size():
		var cv := _make_card_btn(waste[i], true)
		cv.position = WASTE_POS + Vector2(min(i * WASTE_FAN, 40.0), 0)
		if i == waste.size() - 1:
			cv.button_down.connect(_on_card_down.bind({"type": "waste"}))
			cv.button_up.connect(_on_card_up)
		else:
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(cv)

	# Foundations: slot + cards (cards are not interactive here).
	for f in 4:
		var slot := _make_slot_btn()
		slot.position = Vector2(FOUND_X[f], FOUND_Y)
		board.add_child(slot)
		if not foundations[f].is_empty():
			var cv := _make_card_btn(foundations[f][foundations[f].size() - 1], true)
			cv.position = Vector2(FOUND_X[f], FOUND_Y)
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			board.add_child(cv)

	# Tableau: face-down cards below face-up runs.
	for col in 7:
		var slot := _make_slot_btn()
		slot.position = Vector2(TAB_X[col], TAB_Y)
		board.add_child(slot)
		var y := TAB_Y
		for i in tableau[col].size():
			var face_up: bool = _is_face_up(col, i)
			var cv := _make_card_btn(tableau[col][i], face_up)
			cv.position = Vector2(TAB_X[col], y)
			if face_up:
				cv.button_down.connect(_on_card_down.bind({"type": "tableau", "col": col, "idx": i}))
				cv.button_up.connect(_on_card_up)
			board.add_child(cv)
			y += TAB_UP_STEP if face_up else TAB_DOWN_STEP

func _make_slot_btn() -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	b.size = CARD_SIZE
	b.add_theme_stylebox_override("normal", _sb_slot)
	b.add_theme_stylebox_override("hover", _sb_slot)
	b.add_theme_stylebox_override("pressed", _sb_slot)
	b.add_theme_stylebox_override("focus", _sb_slot)
	b.disabled = true
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func _make_card_btn(card: Card, face_up: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	b.size = CARD_SIZE
	if not face_up:
		b.add_theme_stylebox_override("normal", _sb_back)
		b.add_theme_stylebox_override("hover", _sb_back)
		b.add_theme_stylebox_override("pressed", _sb_back)
		b.add_theme_stylebox_override("focus", _sb_back)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE  # face-down cards: no input
		return b

	b.add_theme_stylebox_override("normal", _sb_card)
	b.add_theme_stylebox_override("hover", _sb_card_hover)
	b.add_theme_stylebox_override("pressed", _sb_card_pressed)
	b.add_theme_stylebox_override("focus", _sb_card)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var tl := Label.new()
	tl.text = card.rank_label() + "\n" + card.suit_symbol()
	tl.add_theme_font_size_override("font_size", 13)
	tl.add_theme_color_override("font_color", card.suit_color())
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.position = Vector2(6, 2)
	b.add_child(tl)

	var center := Label.new()
	center.text = card.suit_symbol()
	center.add_theme_font_size_override("font_size", 32)
	center.add_theme_color_override("font_color", card.suit_color())
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.grow_horizontal = 2
	center.grow_vertical = 2
	b.add_child(center)
	return b

# ---------------------------------------------------------------------------
# INPUT — drag & drop via Button signals + _unhandled_input motion
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Mouse motion while a card is pressed: once past the threshold, start the
	# drag and follow the cursor with ghost copies.
	if event is InputEventMouseMotion and _press_src.size() > 0:
		if not _drag_active and event.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_start_drag(event.position)
		elif _drag_active:
			_move_ghosts(event.position)

func _on_stock_pressed() -> void:
	_draw_from_stock()

func _on_card_down(src: Dictionary) -> void:
	if game_over:
		return
	if src.get("type", "") == "tableau":
		var col: int = src.get("col", -1)
		var idx: int = src.get("idx", -1)
		if col < 0 or idx < 0 or idx >= tableau[col].size() or not _is_face_up(col, idx):
			return
	_press_src = src
	_press_pos = get_viewport().get_mouse_position()
	_drag_active = false

func _on_card_up() -> void:
	if _press_src.size() == 0:
		return
	var release_pos: Vector2 = get_viewport().get_mouse_position()
	var src: Dictionary = _press_src
	_press_src = {}

	if not _drag_active:
		# Plain click: auto-send a top card (waste or tableau top) to a foundation.
		_try_click_to_foundation(src)
		return

	_clear_ghosts()
	_drag_active = false
	var cards: Array = _dragged_cards_from(src)
	if cards.is_empty():
		return

	# Drop hit-test: foundations first, then columns.
	for f in 4:
		var r := Rect2(Vector2(FOUND_X[f], FOUND_Y), CARD_SIZE)
		if r.has_point(release_pos):
			_finish_drop_to_foundation(f, cards)
			return
	for col in 7:
		if _column_rect(col).has_point(release_pos):
			_finish_drop_to_tableau(col, cards, src)
			return

func _dragged_cards_from(src: Dictionary) -> Array:
	var cards: Array = []
	if src.get("type", "") == "waste":
		if not waste.is_empty():
			cards.append(waste[waste.size() - 1])
	elif src.get("type", "") == "tableau":
		var col: int = src.get("col", -1)
		var idx: int = src.get("idx", -1)
		if col >= 0 and idx >= 0 and idx < tableau[col].size():
			for i in range(idx, tableau[col].size()):
				cards.append(tableau[col][i])
	return cards

func _start_drag(pos: Vector2) -> void:
	_drag_active = true
	_clear_ghosts()
	var cards: Array = _dragged_cards_from(_press_src)
	if cards.is_empty():
		return
	# Anchor: top of the pile under the cursor.
	var anchor_y: float
	if _press_src.get("type", "") == "waste":
		anchor_y = WASTE_POS.y
	else:
		anchor_y = _card_rect(_press_src.get("col", 0), _press_src.get("idx", 0)).position.y
	var dy: float = pos.y - anchor_y
	for i in cards.size():
		var cv := _make_card_btn(cards[i], true)
		var y: float = pos.y + i * TAB_UP_STEP - dy
		cv.position = Vector2(pos.x - CARD_SIZE.x * 0.5, y)
		cv.z_index = 100 + i
		board.add_child(cv)
		_ghosts.append(cv)

func _move_ghosts(pos: Vector2) -> void:
	if _ghosts.is_empty():
		return
	var src_col: int = _press_src.get("col", -1)
	var src_idx: int = _press_src.get("idx", -1)
	var anchor_y: float
	if _press_src.get("type", "") == "waste":
		anchor_y = WASTE_POS.y
	else:
		anchor_y = _card_rect(src_col, src_idx).position.y
	var dy: float = pos.y - anchor_y
	for i in _ghosts.size():
		_ghosts[i].position = Vector2(pos.x - CARD_SIZE.x * 0.5, pos.y + i * TAB_UP_STEP - dy)

func _clear_ghosts() -> void:
	for g in _ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_ghosts.clear()

func _try_click_to_foundation(src: Dictionary) -> void:
	var cards: Array = _dragged_cards_from(src)
	if cards.size() != 1:
		return
	var card: Card = cards[0]
	for f in 4:
		if _can_place_foundation(f, card):
			_execute_to_foundation(f, card, src)
			return

func _finish_drop_to_foundation(f: int, cards: Array) -> void:
	if cards.size() != 1:
		return
	var card: Card = cards[0]
	if not _can_place_foundation(f, card):
		return
	_execute_to_foundation(f, card, _press_src)

func _execute_to_foundation(f: int, card: Card, src: Dictionary) -> void:
	if src.get("type", "") == "waste":
		waste.erase(card)
	elif src.get("type", "") == "tableau":
		var col: int = src.get("col", -1)
		var idx: int = src.get("idx", -1)
		if col >= 0 and idx >= 0 and idx < tableau[col].size():
			_remove_run_from(col, idx)
	foundations[f].append(card)
	_after_move()

func _finish_drop_to_tableau(col: int, cards: Array, src: Dictionary) -> void:
	var card: Card = cards[0]
	if src.get("type", "") == "tableau" and src.get("col", -1) == col:
		return  # dropped on its own column
	if not _can_place_tableau(col, card):
		return
	if src.get("type", "") == "waste":
		waste.erase(card)
	elif src.get("type", "") == "tableau":
		var scol: int = src.get("col", -1)
		var sidx: int = src.get("idx", -1)
		if scol >= 0 and sidx >= 0 and sidx < tableau[scol].size():
			_remove_run_from(scol, sidx)
	for c in cards:
		tableau[col].append(c)
	_face_up[col][tableau[col].size() - 1] = true
	_after_move()

## Removes the run starting at (col, idx); flips the new top card.
func _remove_run_from(col: int, idx: int) -> void:
	for i in range(tableau[col].size() - 1, idx - 1, -1):
		tableau[col].pop_back()
		_face_up[col].erase(i)
	if not tableau[col].is_empty():
		_face_up[col][tableau[col].size() - 1] = true

func _after_move() -> void:
	moves += 1
	moves_label.text = "Ходи: %d" % moves
	_press_src = {}
	_drag_active = false
	_render_all()
	_check_win()

func _card_rect(col: int, idx: int) -> Rect2:
	var y := TAB_Y
	for i in idx:
		y += TAB_UP_STEP if _is_face_up(col, i) else TAB_DOWN_STEP
	return Rect2(Vector2(TAB_X[col], y), CARD_SIZE)

func _column_rect(col: int) -> Rect2:
	var cards: Array = tableau[col]
	var height: float = CARD_SIZE.y + 40.0
	if not cards.is_empty():
		var y := TAB_Y
		for i in cards.size():
			y += TAB_UP_STEP if _is_face_up(col, i) else TAB_DOWN_STEP
		height = maxf(height, y - TAB_Y + CARD_SIZE.y * 0.5 + 40.0)
	return Rect2(Vector2(TAB_X[col], TAB_Y), Vector2(CARD_SIZE.x, height))

# ---------------------------------------------------------------------------
# STOCK
# ---------------------------------------------------------------------------

func _draw_from_stock() -> void:
	if game_over:
		return
	if stock.is_empty():
		if waste.is_empty():
			return
		# Recycle: waste becomes stock again (top card draws first).
		var recycled: Array = []
		for i in range(waste.size() - 1, -1, -1):
			recycled.append(waste[i])
		stock = recycled
		waste.clear()
		_render_all()
		return
	waste.append(stock.pop_back())
	moves += 1
	moves_label.text = "Ходи: %d" % moves
	_render_all()

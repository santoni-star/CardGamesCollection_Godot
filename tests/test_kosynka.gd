extends SceneTree
## Headless smoke test for Kosynka (Klondike) game logic + drag & drop input.
## Run: godot --headless --path /home/v/card-games-hearts-2026-08-09 --script tests/test_kosynka.gd

const Card = preload("res://scripts/card/Card.gd")

var failures: int = 0

func _init() -> void:
	var scene: Node = load("res://scenes/games/Kosynka/Kosynka.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var k = scene

	# --- deal correctness ---
	check(k.stock.size() == 24, "stock has 24 cards, got %d" % k.stock.size())
	check(k.waste.is_empty(), "waste empty at start")
	var total: int = k.stock.size() + k.waste.size()
	for f in 4:
		total += k.foundations[f].size()
	for t in 7:
		total += k.tableau[t].size()
	check(total == 52, "total cards 52, got %d" % total)
	for i in 7:
		check(k.tableau[i].size() == i + 1, "tableau[%d] has %d cards, expected %d" % [i, k.tableau[i].size(), i + 1])
	for i in 7:
		check(k._is_face_up(i, k.tableau[i].size() - 1), "top of col %d is face-up" % i)
	check(k._is_face_up(0, 0) == false or k.tableau[0].size() == 1, "col0 single card logic ok")

	# --- stock draw via board input (real click path) ---
	var before: int = k.waste.size()
	_press(k, Vector2(84, 162))
	check(k.waste.size() == before + 1, "stock click draws a card (%d -> %d)" % [before, k.waste.size()])
	check(k.stock.size() == 23, "after draw stock 23, got %d" % k.stock.size())
	var drawn: Card = k.waste[k.waste.size() - 1]
	check(drawn != null, "drawn card exists")

	# --- drag waste card onto a foundation (only if top card is an ace) ---
	var top: Card = k.waste[k.waste.size() - 1]
	if top.rank == 1:
		var f_target: int = -1
		for f in 4:
			if k._can_place_foundation(f, top):
				f_target = f
				break
		if f_target >= 0:
			var wrect: Rect2 = Rect2(k.WASTE_POS + Vector2(min((k.waste.size() - 1) * 18, 36), 0), k.CARD_SIZE)
			var press_pos: Vector2 = wrect.position + Vector2(44, 62)
			var drop_pos: Vector2 = Vector2(k.FOUND_X[f_target] + 44, 162)
			_drag(k, press_pos, drop_pos)
			check(k.foundations[f_target].size() == 1, "dragged waste ace onto foundation %d" % f_target)
			check(k.waste.is_empty() or k.waste[k.waste.size() - 1] != top, "waste card removed after drag")

	# --- foundation rule via click-to-foundation (top tableau card that is an ace) ---
	var ace_col: int = -1
	for col in 7:
		var i: int = k.tableau[col].size() - 1
		if k._is_face_up(col, i) and k.tableau[col][i].rank == 1:
			ace_col = col
			break
	if ace_col >= 0:
		var f_target: int = -1
		for f in 4:
			if k._can_place_foundation(f, k.tableau[ace_col][k.tableau[ace_col].size() - 1]):
				f_target = f
				break
		if f_target >= 0:
			var r: Rect2 = k._card_rect(ace_col, k.tableau[ace_col].size() - 1)
			_click(k, r.position + Vector2(44, 62))
			check(k.foundations[f_target].size() == 1, "plain click auto-sends ace to foundation %d" % f_target)

	# --- tableau stacking + run drag (controlled state) ---
	k.waste.clear()
	for f in 4:
		k.foundations[f].clear()
	for t in 7:
		k.tableau[t].clear()
	k._tableau_face_up = [{}, {}, {}, {}, {}, {}, {}]
	k.tableau[0].append(Card.new(Card.Suit.SPADES, 12))   # Q♠
	k.tableau[1].append(Card.new(Card.Suit.HEARTS, 13))   # K♥
	k._tableau_face_up[0] = {0: true}
	k._tableau_face_up[1] = {0: true}
	k._render_all()
	var r0: Rect2 = k._card_rect(0, 0)
	var drop: Vector2 = Vector2(k.TAB_X[1] + 44, 400)
	_drag(k, r0.position + Vector2(44, 62), drop)
	check(k.tableau[0].is_empty(), "run moved off source column")
	check(k.tableau[1].size() == 2, "run landed on target column (size %d)" % k.tableau[1].size())

	# --- same-column drop rejected ---
	var before_size: int = k.tableau[1].size()
	var r1: Rect2 = k._card_rect(1, 1)
	_drag(k, r1.position + Vector2(44, 62), Vector2(k.TAB_X[1] + 44, 400))
	check(k.tableau[1].size() == before_size, "same-column drop rejected")

	# --- recycle waste when stock empty ---
	while not k.stock.is_empty():
		k._draw_from_stock()
	k._draw_from_stock()  # recycle
	check(k.waste.is_empty(), "waste recycled into stock")
	check(k.stock.size() > 0, "stock refilled after recycle")

	# --- win detection on fake complete foundations ---
	var any_card: Card = null
	for col in 7:
		if not k.tableau[col].is_empty():
			any_card = k.tableau[col][0]
			break
	if any_card == null:
		any_card = k.waste[0]
	for f in 4:
		k.foundations[f].clear()
		for r in 13:
			k.foundations[f].append(Card.new(Card.Suit.HEARTS, r + 1))
	k._check_win()
	check(k.game_over == true, "game_over set when all foundations full")

	print("=== Kosynka tests: %d failures ===" % failures)
	quit(1 if failures > 0 else 0)

func _press(k, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	k._on_board_input(ev)

func _click(k, pos: Vector2) -> void:
	_press(k, pos)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = pos
	k._on_board_input(rel)

func _drag(k, from: Vector2, to: Vector2) -> void:
	_press(k, from)
	var mot := InputEventMouseMotion.new()
	mot.position = to
	k._on_board_input(mot)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = to
	k._on_board_input(rel)

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: " + msg)
	else:
		failures += 1
		print("  FAIL: " + msg)

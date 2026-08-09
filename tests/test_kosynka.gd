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

	# --- stock draw via button press path ---
	var before: int = k.waste.size()
	k._on_stock_pressed()
	check(k.waste.size() == before + 1, "stock click draws a card (%d -> %d)" % [before, k.waste.size()])
	check(k.stock.size() == 23, "after draw stock 23, got %d" % k.stock.size())

	# --- plain click on a top tableau ace auto-sends to foundation ---
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
			var src := {"type": "tableau", "col": ace_col, "idx": k.tableau[ace_col].size() - 1}
			k._on_card_down(src)
			k._on_card_up()
			check(k.foundations[f_target].size() == 1, "plain click auto-sends ace to foundation %d" % f_target)

	# --- controlled drag: waste ace onto a foundation ---
	k.waste.clear()
	for f in 4:
		k.foundations[f].clear()
	k.waste.append(Card.new(Card.Suit.SPADES, 1))
	k._render_all()
	k._on_card_down({"type": "waste"})
	k._start_drag(Vector2(200, 150))
	k._move_ghosts(Vector2(k.FOUND_X[0] + 44, 162))
	var cards: Array = k._dragged_cards_from({"type": "waste"})
	check(cards.size() == 1, "waste drag picks 1 card")
	k._finish_drop_to_foundation(0, cards)
	check(k.foundations[0].size() == 1, "drag waste ace onto foundation 0")
	check(k.waste.is_empty(), "waste emptied after drag")

	# --- controlled drag: tableau run onto another column ---
	k.tableau[0].clear()
	k._face_up[0] = {}
	k.tableau[1].clear()
	k._face_up[1] = {}
	k.tableau[0].append(Card.new(Card.Suit.SPADES, 12))  # Q♠
	k.tableau[1].append(Card.new(Card.Suit.HEARTS, 13))  # K♥
	k._face_up[0] = {0: true}
	k._face_up[1] = {0: true}
	k._render_all()
	var src2 := {"type": "tableau", "col": 0, "idx": 0}
	k._on_card_down(src2)
	k._start_drag(Vector2(k.TAB_X[0] + 44, 400))
	k._move_ghosts(Vector2(k.TAB_X[1] + 44, 400))
	var cards2: Array = k._dragged_cards_from(src2)
	check(cards2.size() == 1, "tableau drag picks the run")
	k._finish_drop_to_tableau(1, cards2, src2)
	check(k.tableau[0].is_empty(), "run moved off source column")
	check(k.tableau[1].size() == 2, "run landed on target column (size %d)" % k.tableau[1].size())

	# --- same-column drop rejected ---
	var before_size: int = k.tableau[1].size()
	var src3 := {"type": "tableau", "col": 1, "idx": 1}
	var cards3: Array = k._dragged_cards_from(src3)
	k._finish_drop_to_tableau(1, cards3, src3)
	check(k.tableau[1].size() == before_size, "same-column drop rejected")

	# --- foundation rule: no stacking wrong suit ---
	var heart2 := Card.new(Card.Suit.HEARTS, 2)
	check(k._can_place_foundation(0, heart2) == false, "heart 2 cannot go on spade foundation")

	# --- recycle waste when stock empty ---
	while not k.stock.is_empty():
		k._draw_from_stock()
	k._draw_from_stock()  # recycle
	check(k.waste.is_empty(), "waste recycled into stock")
	check(k.stock.size() > 0, "stock refilled after recycle")

	# --- win detection on fake complete foundations ---
	for f in 4:
		k.foundations[f].clear()
		for r in 13:
			k.foundations[f].append(Card.new(Card.Suit.HEARTS, r + 1))
	k._check_win()
	check(k.game_over == true, "game_over set when all foundations full")

	print("=== Kosynka tests: %d failures ===" % failures)
	quit(1 if failures > 0 else 0)

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: " + msg)
	else:
		failures += 1
		print("  FAIL: " + msg)

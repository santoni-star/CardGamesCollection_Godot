extends SceneTree
## Headless smoke test for Kosynka (Klondike) game logic.
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

	# --- stock draw ---
	k._draw_from_stock()
	check(k.stock.size() == 23, "after draw stock 23, got %d" % k.stock.size())
	check(k.waste.size() == 1, "after draw waste 1, got %d" % k.waste.size())
	var drawn: Card = k.waste[0]
	check(drawn != null, "drawn card exists")

	# --- foundation rule: ace on empty ---
	# deterministic: force an ace onto a column top, then auto-foundation
	var ace: Card = Card.new(Card.Suit.SPADES, 1)
	var col0: Array = k.tableau[0]
	col0.append(ace)
	k._tableau_face_up[0][col0.size() - 1] = true
	check(k._try_auto_to_foundation(ace, "tableau", 0, col0.size() - 1), "ace from tableau top goes to foundation")
	check(k.foundations[0].size() == 1 or k.foundations[1].size() == 1 or k.foundations[2].size() == 1 or k.foundations[3].size() == 1,
		"foundation holds the ace")

	# --- waste → foundation auto ---
	var waste_card: Card = k.waste[0]
	if waste_card.rank == 1:
		check(k._try_auto_to_foundation(waste_card, "waste", -1, 0), "waste ace auto-foundation")

	# --- tableau stacking rule ---
	var src_col: int = -1
	var src_idx: int = -1
	var src_card: Card = null
	for col in 7:
		var i: int = k.tableau[col].size() - 1
		if k._is_face_up(col, i):
			src_col = col
			src_idx = i
			src_card = k.tableau[col][i]
			break
	if src_card != null:
		var legal: int = 0
		var target: int = -1
		for col in 7:
			if col == src_col:
				continue
			if k._can_place_tableau(col, src_card):
				legal += 1
				target = col
		if legal > 0:
			k._select_run(src_col, src_idx)
			k._try_place_selected_on_tableau(target)
			check(k.tableau[target].size() >= 2, "run moved to col %d (size %d)" % [target, k.tableau[target].size()])
		check(k.selected_col == -1, "selection cleared after move")

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

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: " + msg)
	else:
		failures += 1
		print("  FAIL: " + msg)

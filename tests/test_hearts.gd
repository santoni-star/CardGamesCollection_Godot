extends Node
## Headless smoke test for Hearts game flow.
## Needs a scene (autoloads like GameData are not loaded in --script mode).
## Run: godot --headless --path . res://tests/TestHearts.tscn

var failures: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)

func _ready() -> void:
	var scene = load("res://scenes/games/Hearts/Hearts.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var h = scene

	# --- deal ---
	check(h.hands[0].size() == 13 and h.hands[1].size() == 13
		and h.hands[2].size() == 13 and h.hands[3].size() == 13, "deal: 13 cards each")
	check(h.phase == h.Phase.PASSING, "starts in passing phase")

	# --- passing: human selects 3 and confirms ---
	if h.phase == h.Phase.PASSING:
		var hc_list: Array = h.player_hand_row.get_children()
		check(hc_list.size() == 13, "hand row rendered 13 cards")
		for i in 3:
			h._toggle_pass_selection(hc_list[i])
		check(h.selected_pass.size() == 3, "3 cards selected to pass")
		h._on_confirm_pass()

	var guard: int = 0
	while h.phase == h.Phase.PASSING and guard < 20:
		guard += 1
		await get_tree().create_timer(0.5).timeout
	check(h.phase == h.Phase.PLAYING, "reached playing phase (guard=%d)" % guard)

	# --- play full round ---
	guard = 0
	while h.phase == h.Phase.PLAYING and guard < 260:
		guard += 1
		if h.current_turn == 0:
			var legal: Array = h._legal_cards(0)
			if legal.is_empty():
				break
			h._try_play_human_card(legal[0], null)
		await get_tree().create_timer(0.5).timeout
	check(h.phase == h.Phase.ROUND_OVER, "round finished (guard=%d)" % guard)
	print("DIAG: hands=", h.hands[0].size(), h.hands[1].size(), h.hands[2].size(), h.hands[3].size(),
		" tricks=", h.trick_number, " points=", h.round_points, " rounds=", h.round_number)

	# --- scoring sanity: points sum to 26 unless someone shot the moon ---
	var total_pts: int = 0
	for p in 4:
		total_pts += h.round_points[p]
	var moon: bool = false
	for p in 4:
		if h.round_points[p] == 26:
			moon = true
	check(moon or total_pts == 26, "trick points sum to 26 (%d, moon=%s)" % [total_pts, str(moon)])
	check(h.trick_number == 13, "13 tricks played (%d)" % h.trick_number)

	print("=== Hearts tests: %d failures ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)

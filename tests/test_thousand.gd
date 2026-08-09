extends SceneTree
## Headless smoke test for Thousand (1000) game flow.
## Run: godot --headless --path . --script tests/test_thousand.gd

const Card = preload("res://scripts/card/Card.gd")

var failures: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	var scene = load("res://scenes/games/Thousand/Thousand.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var t = scene

	# --- deterministic rules ---
	check(t.hands[0].size() == 7 and t.hands[1].size() == 7 and t.hands[2].size() == 7,
		"deal: 7 cards each")
	check(t.widow.size() == 3, "widow has 3 cards")

	# marriage values
	check(t._marriage_value(Card.Suit.HEARTS) == 100, "marriage hearts=100")
	check(t._marriage_value(Card.Suit.DIAMONDS) == 80, "marriage diamonds=80")
	check(t._marriage_value(Card.Suit.CLUBS) == 60, "marriage clubs=60")
	check(t._marriage_value(Card.Suit.SPADES) == 40, "marriage spades=40")

	# card score: trump beats everything, then led suit
	t.trump_suit = Card.Suit.HEARTS
	var nine_hearts: Card = Card.new(Card.Suit.HEARTS, 9)
	var ace_spades: Card = Card.new(Card.Suit.SPADES, 14)  # A = 14 internally
	var ten_hearts: Card = Card.new(Card.Suit.HEARTS, 10)
	check(t._card_score(nine_hearts, Card.Suit.SPADES) > t._card_score(ace_spades, Card.Suit.SPADES),
		"trump 9 beats non-trump A")
	check(t._card_score(ten_hearts, Card.Suit.HEARTS) > t._card_score(nine_hearts, Card.Suit.HEARTS),
		"10 beats 9 in led suit")
	check(t._card_score(Card.new(Card.Suit.CLUBS, 9), Card.Suit.SPADES) == -1,
		"off-suit non-trump scores -1")
	t.trump_suit = -1

	# legal cards: lead = anything; after lead = must follow suit
	t.trick_leader = 0
	t.trick_cards = [null, null, null]
	var any_legal: Array = t._legal_cards(0)
	check(any_legal.size() == 7, "leader may play any card")

	# --- full bidding loop with timers ---
	var guard: int = 0
	while t.phase == t.Phase.BIDDING and guard < 40:
		guard += 1
		if t.current_bid_turn == 0 and not t.passed[0]:
			if randf() < 0.5 and t.highest_bid < 200:
				t._human_bid(25)
			else:
				t._on_human_pass()
		await create_timer(0.8).timeout
	check(t.phase != t.Phase.BIDDING, "bidding finished (guard=%d)" % guard)
	check(t.highest_bidder >= 0, "there is a highest bidder")

	# --- discard phase ---
	if t.phase == t.Phase.DISCARDING:
		if t.highest_bidder == 0:
			# human must discard: select first 3 cards
			var hc_list: Array = t.player_hand_row.get_children()
			for i in 3:
				t._toggle_discard_selection(hc_list[i])
			check(t.selected_discards.size() == 3, "3 cards selected for discard")
			check(t.confirm_discard_button.disabled == false, "confirm enabled at 3")
			t._on_confirm_discard()
		else:
			# AI discards on its own timer
			guard = 0
			while t.phase == t.Phase.DISCARDING and guard < 20:
				guard += 1
				await create_timer(1.0).timeout
	check(t.phase == t.Phase.PLAYING, "reached playing phase")

	# --- play full round with timers ---
	guard = 0
	while t.phase == t.Phase.PLAYING and guard < 200:
		guard += 1
		if t.current_turn == 0:
			var legal: Array = t._legal_cards(0)
			if legal.is_empty():
				break
			t._try_play_human_card(legal[0], null)
		await create_timer(0.6).timeout
	check(t.phase == t.Phase.ROUND_OVER, "round finished (guard=%d)" % guard)

	# --- scoring: bidder gets ALL points when making the bid ---
	var bidder: int = t.highest_bidder
	var bid: int = t.highest_bid
	var expected: int = t.tricks_won_points[bidder] + t.marriage_points[bidder]
	if expected >= bid:
		check(t.total_score[bidder] == expected, "bidder scored full points (%d)" % expected)
	else:
		check(t.total_score[bidder] == -bid, "bidder penalized by bid (%d)" % bid)
	var others_ok: bool = true
	for p in 3:
		if p != bidder:
			var pts: int = t.tricks_won_points[p] + t.marriage_points[p]
			if t.total_score[p] != pts:
				others_ok = false
	check(others_ok, "other players scored their trick points")

	print("=== Thousand tests: %d failures ===" % failures)
	quit(1 if failures > 0 else 0)

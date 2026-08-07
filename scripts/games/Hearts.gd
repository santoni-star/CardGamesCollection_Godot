extends Control
## Hearts module. All animation goes through CardFX (scripts/core/CardFX.gd) —
## this file only contains Hearts' rules. Player 0 = You, 1 = West, 2 = North, 3 = East.
## Standard 52-card deck, 13 cards each, no trump — the trick's led suit always decides.
##
## Known simplifications vs. tournament rules:
## - First-trick restriction only forbids hearts/Q♠ when a player is VOID in the
##   led suit (clubs) and has a safe alternative — matches how it plays out in
##   practice since the leader is always forced to open with 2♣.
## - No "hearts must be led once broken" edge cases around all-hearts hands.

enum Phase { PASSING, PLAYING, ROUND_OVER, GAME_OVER }

const CardViewScene := preload("res://scenes/components/CardView.tscn")
const HandCardScene := preload("res://scenes/components/HandCard.tscn")

@onready var back_button: Button = $TopBar/BackButton
@onready var score_label: Label = $TopBar/ScoreLabel
@onready var status_label: Label = $TopBar/StatusLabel
@onready var message_label: Label = $MessageLabel

@onready var slot_holder := {0: null, 1: null, 2: null, 3: null}

@onready var west_hand: VBoxContainer = $WestHand
@onready var north_hand: HBoxContainer = $NorthHand
@onready var east_hand: VBoxContainer = $EastHand

@onready var pass_panel: VBoxContainer = $PassPanel
@onready var pass_instruction_label: Label = $PassPanel/InstructionLabel
@onready var confirm_pass_button: Button = $PassPanel/ConfirmPassButton

@onready var continue_button: Button = $ContinueButton
@onready var player_hand_row: HBoxContainer = $PlayerHandRow

const PLAYER_NAMES := ["You", "West", "North", "East"]
# Pass direction per round (round_number % 4): left, right, across, hold.
const PASS_OFFSETS := [1, 3, 2, 0]
const PASS_NAMES := ["left", "right", "across", "hold your cards"]

var hands: Array = [[], [], [], []]
var total_score: Array = [0, 0, 0, 0]
var round_number: int = 0

var phase: int = Phase.PASSING
var selected_pass: Array = []

var hearts_broken: bool = false
var trick_number: int = 1
var trick_cards: Array = [null, null, null, null]
var trick_card_views: Dictionary = {0: null, 1: null, 2: null, 3: null}
var trick_leader: int = 0
var current_turn: int = 0
var round_points: Array = [0, 0, 0, 0]

func _ready() -> void:
	slot_holder[0] = $TrickArea/SlotYou
	slot_holder[1] = $TrickArea/SlotWest
	slot_holder[2] = $TrickArea/SlotNorth
	slot_holder[3] = $TrickArea/SlotEast

	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	confirm_pass_button.pressed.connect(_on_confirm_pass)
	continue_button.pressed.connect(_on_continue_pressed)

	start_new_round()

# ---------------------------------------------------------------------------
# ROUND SETUP
# ---------------------------------------------------------------------------

func start_new_round() -> void:
	message_label.text = ""
	continue_button.visible = false
	pass_panel.visible = false
	_clear_trick_area()

	var deck := Deck.new()
	deck.build_standard()
	deck.shuffle()

	hands = [[], [], [], []]
	for p in 4:
		for i in 13:
			hands[p].append(deck.draw_card())
	for p in 4:
		hands[p].sort_custom(func(a, b): return _card_sort_key(a) < _card_sort_key(b))

	hearts_broken = false
	trick_number = 1
	trick_cards = [null, null, null, null]
	round_points = [0, 0, 0, 0]

	_render_status()

	var offset: int = PASS_OFFSETS[round_number % 4]
	if offset == 0:
		phase = Phase.PLAYING
		message_label.text = "This round: hold your cards."
		_render_hands(true)
		_begin_first_trick()
	else:
		phase = Phase.PASSING
		selected_pass.clear()
		pass_instruction_label.text = "Pass 3 cards %s" % PASS_NAMES[round_number % 4]
		confirm_pass_button.disabled = true
		pass_panel.visible = true
		status_label.text = "Choose 3 cards to pass"
		_render_hands(true)

func _on_confirm_pass() -> void:
	var offset: int = PASS_OFFSETS[round_number % 4]
	var outgoing := {}
	outgoing[0] = selected_pass.duplicate()
	for p in [1, 2, 3]:
		outgoing[p] = _ai_choose_pass(p)

	for p in 4:
		for c in outgoing[p]:
			hands[p].erase(c)
	for p in 4:
		var target: int = (p + offset) % 4
		hands[target].append_array(outgoing[p])
	for p in 4:
		hands[p].sort_custom(func(a, b): return _card_sort_key(a) < _card_sort_key(b))

	pass_panel.visible = false
	phase = Phase.PLAYING
	message_label.text = "Cards passed %s." % PASS_NAMES[round_number % 4]
	_render_hands(true)
	_begin_first_trick()

func _ai_choose_pass(p: int) -> Array:
	var hand: Array = hands[p].duplicate()
	hand.sort_custom(func(a, b): return _card_danger(b) < _card_danger(a))
	return [hand[0], hand[1], hand[2]]

func _begin_first_trick() -> void:
	trick_leader = _find_two_of_clubs_holder()
	current_turn = trick_leader
	_advance_play()

func _find_two_of_clubs_holder() -> int:
	for p in 4:
		for c in hands[p]:
			if c.suit == Card.Suit.CLUBS and c.rank == 2:
				return p
	return 0

# ---------------------------------------------------------------------------
# PLAYING TRICKS
# ---------------------------------------------------------------------------

func _advance_play() -> void:
	if current_turn == 0:
		status_label.text = "Your turn"
		_update_hand_interactivity()
	else:
		status_label.text = "%s is playing..." % PLAYER_NAMES[current_turn]
		await get_tree().create_timer(0.6).timeout
		var card = _ai_choose_card(current_turn)
		_play_card(current_turn, card)

func _try_play_human_card(card: Card, hand_card_node: Control) -> void:
	if phase != Phase.PLAYING or current_turn != 0:
		return
	var legal: Array = _legal_cards(0)
	if not legal.has(card):
		message_label.text = "You must follow suit!"
		hand_card_node.animate_reject()
		return
	_play_card(0, card)

func _play_card(player: int, card: Card) -> void:
	hands[player].erase(card)
	if card.suit == Card.Suit.HEARTS:
		hearts_broken = true

	trick_cards[player] = card
	_place_trick_card_visual(player, card)
	if player == 0:
		_render_hands(false)

	var all_played := true
	for c in trick_cards:
		if c == null:
			all_played = false
			break

	if all_played:
		await get_tree().create_timer(0.9).timeout
		_resolve_trick()
	else:
		current_turn = (player + 1) % 4
		_advance_play()

func _resolve_trick() -> void:
	var led_suit: int = trick_cards[trick_leader].suit
	var best_player := trick_leader
	var best_score := _card_score(trick_cards[trick_leader], led_suit)
	for p in 4:
		if p == trick_leader:
			continue
		var s := _card_score(trick_cards[p], led_suit)
		if s > best_score:
			best_score = s
			best_player = p

	var points := 0
	for c in trick_cards:
		if c.suit == Card.Suit.HEARTS:
			points += 1
		elif c.suit == Card.Suit.SPADES and c.rank == 12:
			points += 13
	round_points[best_player] += points

	if points > 0:
		message_label.text = "%s takes the trick (+%d points)" % [PLAYER_NAMES[best_player], points]
	else:
		message_label.text = "%s takes the trick" % PLAYER_NAMES[best_player]

	var winner_holder: Control = slot_holder[best_player]
	for p in 4:
		var cv = trick_card_views[p]
		if cv != null:
			var direction: Vector2 = (winner_holder.global_position - cv.global_position) * 0.7
			cv.animate_collect(direction)
	trick_card_views = {0: null, 1: null, 2: null, 3: null}

	trick_leader = best_player
	current_turn = best_player
	trick_cards = [null, null, null, null]
	trick_number += 1

	if hands[0].is_empty():
		await get_tree().create_timer(CardFX.COLLECT_DURATION + 0.1).timeout
		_end_round()
	else:
		await get_tree().create_timer(CardFX.COLLECT_DURATION + 0.15).timeout
		_advance_play()

func _card_score(card: Card, led_suit: int) -> int:
	if card.suit == led_suit:
		return card.standard_order_value()
	return -1

func _legal_cards(player: int) -> Array:
	var hand: Array = hands[player]
	var is_lead: bool = trick_cards[trick_leader] == null

	if trick_number == 1 and is_lead:
		for c in hand:
			if c.suit == Card.Suit.CLUBS and c.rank == 2:
				return [c]

	if is_lead:
		if not hearts_broken:
			var safe := []
			for c in hand:
				if c.suit != Card.Suit.HEARTS:
					safe.append(c)
			if safe.size() > 0:
				return safe
		return hand.duplicate()

	var led_suit: int = trick_cards[trick_leader].suit
	var matching := []
	for c in hand:
		if c.suit == led_suit:
			matching.append(c)
	if matching.size() > 0:
		return matching

	if trick_number == 1:
		var safe := []
		for c in hand:
			var is_point_card: bool = c.suit == Card.Suit.HEARTS or (c.suit == Card.Suit.SPADES and c.rank == 12)
			if not is_point_card:
				safe.append(c)
		if safe.size() > 0:
			return safe

	return hand.duplicate()

func _ai_choose_card(player: int) -> Card:
	var legal: Array = _legal_cards(player)
	var is_lead: bool = trick_cards[trick_leader] == null

	if is_lead:
		legal.sort_custom(func(a, b): return _card_danger(a) < _card_danger(b))
		return legal[0]

	var led_suit: int = trick_cards[trick_leader].suit
	var following: Array = []
	for c in legal:
		if c.suit == led_suit:
			following.append(c)

	if following.size() > 0:
		var current_best := -1
		for c in trick_cards:
			if c != null and c.suit == led_suit:
				if c.standard_order_value() > current_best:
					current_best = c.standard_order_value()
		var non_winning := []
		for c in following:
			if c.standard_order_value() < current_best:
				non_winning.append(c)
		if non_winning.size() > 0:
			non_winning.sort_custom(func(a, b): return b.standard_order_value() < a.standard_order_value())
			return non_winning[0]
		following.sort_custom(func(a, b): return a.standard_order_value() < b.standard_order_value())
		return following[0]
	else:
		legal.sort_custom(func(a, b): return _card_danger(b) < _card_danger(a))
		return legal[0]

# ---------------------------------------------------------------------------
# ROUND END / SCORING
# ---------------------------------------------------------------------------

func _end_round() -> void:
	phase = Phase.ROUND_OVER

	var moon_shooter := -1
	for p in 4:
		if round_points[p] == 26:
			moon_shooter = p

	var result_lines := []
	if moon_shooter != -1:
		for p in 4:
			total_score[p] += 0 if p == moon_shooter else 26
		result_lines.append("%s shot the moon! Everyone else +26." % PLAYER_NAMES[moon_shooter])
	else:
		for p in 4:
			total_score[p] += round_points[p]
			result_lines.append("%s: +%d" % [PLAYER_NAMES[p], round_points[p]])

	message_label.text = "\n".join(result_lines)
	CardFX.pulse(score_label)
	_render_status()

	var game_over := false
	for p in 4:
		if total_score[p] >= 100:
			game_over = true

	if game_over:
		phase = Phase.GAME_OVER
		var best_p := 0
		for p in 4:
			if total_score[p] < total_score[best_p]:
				best_p = p
		status_label.text = "%s wins with the lowest score (%d)!" % [PLAYER_NAMES[best_p], total_score[best_p]]
		continue_button.text = "New Match"
	else:
		status_label.text = "Round over"
		continue_button.text = "Next Round"
	continue_button.visible = true

func _on_continue_pressed() -> void:
	if phase == Phase.GAME_OVER:
		total_score = [0, 0, 0, 0]
		round_number = 0
	else:
		round_number += 1
	continue_button.visible = false
	start_new_round()

# ---------------------------------------------------------------------------
# RENDERING
# ---------------------------------------------------------------------------

func _render_status() -> void:
	score_label.text = "You: %d  West: %d  North: %d  East: %d" % total_score
	_render_ai_hands()

func _render_hands(animate: bool) -> void:
	for c in player_hand_row.get_children():
		c.queue_free()

	var legal_now: Array = []
	if phase == Phase.PLAYING and current_turn == 0:
		legal_now = _legal_cards(0)

	var i := 0
	for card in hands[0]:
		var hc = HandCardScene.instantiate()
		player_hand_row.add_child(hc)
		hc.setup(card)
		var can_play: bool = phase == Phase.PLAYING and current_turn == 0 and legal_now.has(card)
		var can_select: bool = phase == Phase.PASSING
		hc.disabled = not (can_play or can_select)
		hc.pressed.connect(_on_hand_card_pressed.bind(hc))
		if animate:
			hc.animate_in(i * 0.03)
		i += 1

	_render_ai_hands()

func _render_ai_hands() -> void:
	# Render West hand (face-down cards, vertical on left)
	for c in west_hand.get_children():
		c.queue_free()
	for i in range(hands[1].size()):
		var cv = CardViewScene.instantiate()
		west_hand.add_child(cv)
		cv.setup(null, false)  # face-down
		cv.animate_in(i * 0.03)
	
	# Render North hand (face-down cards, horizontal on top)
	for c in north_hand.get_children():
		c.queue_free()
	for i in range(hands[2].size()):
		var cv = CardViewScene.instantiate()
		north_hand.add_child(cv)
		cv.setup(null, false)  # face-down
		cv.animate_in(i * 0.03)
	
	# Render East hand (face-down cards, vertical on right)
	for c in east_hand.get_children():
		c.queue_free()
	for i in range(hands[3].size()):
		var cv = CardViewScene.instantiate()
		east_hand.add_child(cv)
		cv.setup(null, false)  # face-down
		cv.animate_in(i * 0.03)

func _update_hand_interactivity() -> void:
	var legal_now: Array = []
	if phase == Phase.PLAYING and current_turn == 0:
		legal_now = _legal_cards(0)
	for hc in player_hand_row.get_children():
		var can_play: bool = phase == Phase.PLAYING and current_turn == 0 and legal_now.has(hc.card)
		hc.disabled = not can_play

func _on_hand_card_pressed(hc) -> void:
	match phase:
		Phase.PASSING:
			_toggle_pass_selection(hc)
		Phase.PLAYING:
			if current_turn == 0:
				_try_play_human_card(hc.card, hc)

func _toggle_pass_selection(hc) -> void:
	if hc.selected:
		hc.selected = false
		selected_pass.erase(hc.card)
	elif selected_pass.size() < 3:
		hc.selected = true
		selected_pass.append(hc.card)
	confirm_pass_button.disabled = selected_pass.size() != 3

func _place_trick_card_visual(player: int, card: Card) -> void:
	var holder: Control = slot_holder[player]
	var cv = CardViewScene.instantiate()
	holder.add_child(cv)
	cv.setup(card, true)
	cv.animate_in()
	trick_card_views[player] = cv

func _clear_trick_area() -> void:
	for p in 4:
		var holder: Control = slot_holder[p]
		if holder == null:
			continue
		for c in holder.get_children():
			c.queue_free()
	trick_card_views = {0: null, 1: null, 2: null, 3: null}

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

func _card_sort_key(c: Card) -> int:
	return c.suit * 20 + c.standard_order_value()

## Higher = more dangerous to hold (Q♠ worst, then hearts, then high spades).
func _card_danger(c: Card) -> int:
	if c.suit == Card.Suit.SPADES and c.rank == 12:
		return 1000
	if c.suit == Card.Suit.HEARTS:
		return 200 + c.standard_order_value()
	if c.suit == Card.Suit.SPADES and c.standard_order_value() >= 12:
		return 100 + c.standard_order_value()
	return c.standard_order_value()

extends Control
const Deck = preload("res://scripts/card/Deck.gd")
const CardFX = preload("res://scripts/core/CardFX.gd")
const Card = preload("res://scripts/card/Card.gd")
## Thousand (1000) module. All animation goes through CardFX
## (scripts/core/CardFX.gd) — this file only contains Thousand's rules.
## Player 0 = You, 1 = AI West, 2 = AI East. 24-card deck, 7 cards each, 3-card widow.
##
## Known simplifications vs. full tournament rules:
## - No "barrel" (bochka) penalty zone near 880-1000.
## - Marriages are always auto-announced when leading with a K/Q you hold the pair of.
## - No forced overtrump when void in led suit (you may discard any card).
## - Bid increments fixed at +5 / +25 (real games use free increments).

enum Phase { BIDDING, DISCARDING, PLAYING, ROUND_OVER, GAME_OVER }

const CardViewScene := preload("res://scenes/components/CardView.tscn")
const HandCardScene := preload("res://scenes/components/HandCard.tscn")

@onready var back_button: Button = $TopBar/BackButton
@onready var score_label: Label = $TopBar/ScoreLabel
@onready var status_label: Label = $TopBar/StatusLabel
@onready var ai_west_label: Label = $AIWestLabel
@onready var ai_east_label: Label = $AIEastLabel
@onready var ai_west_hand: HBoxContainer = $AIWestHand
@onready var ai_east_hand: HBoxContainer = $AIEastHand
@onready var message_label: Label = $MessageLabel

@onready var slot_holder := {
	0: null, 1: null, 2: null,
}

@onready var bidding_panel: VBoxContainer = $BiddingPanel
@onready var current_bid_label: Label = $BiddingPanel/CurrentBidLabel
@onready var bid_small_button: Button = $BiddingPanel/HBoxContainer/BidSmallButton
@onready var bid_big_button: Button = $BiddingPanel/HBoxContainer/BidBigButton
@onready var pass_button: Button = $BiddingPanel/HBoxContainer/PassButton

@onready var discard_panel: VBoxContainer = $DiscardPanel
@onready var confirm_discard_button: Button = $DiscardPanel/ConfirmDiscardButton

@onready var continue_button: Button = $ContinueButton
@onready var player_hand_row: HBoxContainer = $PlayerHandRow

const PLAYER_NAMES := ["Ви", "ІІ Захід", "ІІ Схід"]

var hands: Array = [[], [], []]
var widow: Array = []
var total_score: Array = [0, 0, 0]
var round_number: int = 0

var phase: int = Phase.BIDDING
var passed: Array = [false, false, false]
var highest_bid: int = 0
var highest_bidder: int = -1
var current_bid_turn: int = 0

var trump_suit: int = -1
var trick_cards: Array = [null, null, null]
var trick_card_views: Dictionary = {0: null, 1: null, 2: null}
var trick_leader: int = 0
var current_turn: int = 0
var tricks_won_points: Array = [0, 0, 0]
var marriage_points: Array = [0, 0, 0]

var selected_discards: Array = []

func _ready() -> void:
	slot_holder[0] = $TrickArea/HBox/SlotYou/CardHolder
	slot_holder[1] = $TrickArea/HBox/SlotAIWest/CardHolder
	slot_holder[2] = $TrickArea/HBox/SlotAIEast/CardHolder

	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	bid_small_button.pressed.connect(func(): _human_bid(5))
	bid_big_button.pressed.connect(func(): _human_bid(25))
	pass_button.pressed.connect(_on_human_pass)
	confirm_discard_button.pressed.connect(_on_confirm_discard)
	continue_button.pressed.connect(_on_continue_pressed)

	start_new_round()

# ---------------------------------------------------------------------------
# ROUND SETUP
# ---------------------------------------------------------------------------

func start_new_round() -> void:
	phase = Phase.BIDDING
	message_label.text = ""
	continue_button.visible = false
	discard_panel.visible = false
	bidding_panel.visible = false
	_clear_trick_area()

	var deck := Deck.new()
	deck.build_thousand_deck()
	deck.shuffle()

	hands = [[], [], []]
	for p in 3:
		for i in 7:
			hands[p].append(deck.draw_card())
	widow = [deck.draw_card(), deck.draw_card(), deck.draw_card()]

	for p in 3:
		hands[p].sort_custom(func(a, b): return _card_sort_key(a) < _card_sort_key(b))

	tricks_won_points = [0, 0, 0]
	marriage_points = [0, 0, 0]
	trump_suit = -1
	trick_cards = [null, null, null]

	passed = [false, false, false]
	highest_bid = 0
	highest_bidder = -1
	current_bid_turn = round_number % 3

	_render_hands(true)
	_render_status()
	_advance_bidding()

# ---------------------------------------------------------------------------
# BIDDING
# ---------------------------------------------------------------------------

func _advance_bidding() -> void:
	while true:
		var active_count := 0
		for p in 3:
			if not passed[p]:
				active_count += 1
		if active_count <= 1:
			break

		while passed[current_bid_turn]:
			current_bid_turn = (current_bid_turn + 1) % 3

		if current_bid_turn == highest_bidder:
			current_bid_turn = (current_bid_turn + 1) % 3
			continue

		if current_bid_turn == 0:
			_show_bidding_panel_for_human()
			return
		else:
			status_label.text = "%s розмірковує..." % PLAYER_NAMES[current_bid_turn]
			await get_tree().create_timer(0.7).timeout
			_ai_make_bid_decision(current_bid_turn)
			current_bid_turn = (current_bid_turn + 1) % 3

	_finish_bidding()

func _show_bidding_panel_for_human() -> void:
	bidding_panel.visible = true
	var txt := "Поточна ставка: %d" % highest_bid
	if highest_bidder != -1:
		txt += " (%s)" % PLAYER_NAMES[highest_bidder]
	current_bid_label.text = txt
	status_label.text = "Ваша черга торгуватись"

func _human_bid(increment: int) -> void:
	var new_bid: int
	if highest_bidder == -1:
		new_bid = 100
	else:
		new_bid = highest_bid + increment
	highest_bid = new_bid
	highest_bidder = 0
	message_label.text = "Ви ставите %d" % new_bid
	bidding_panel.visible = false
	current_bid_turn = (current_bid_turn + 1) % 3
	_advance_bidding()

func _on_human_pass() -> void:
	passed[0] = true
	message_label.text = "Ви пасуєте"
	bidding_panel.visible = false
	current_bid_turn = (current_bid_turn + 1) % 3
	_advance_bidding()

func _ai_make_bid_decision(p: int) -> void:
	var strength := _hand_strength(hands[p])
	var ceiling := 60 + strength * 3
	if highest_bid < ceiling and highest_bid < 400:
		var new_bid: int = 100 if highest_bidder == -1 else highest_bid + 5
		if randf() < 0.3:
			new_bid += 5
		highest_bid = new_bid
		highest_bidder = p
		message_label.text = "%s ставить %d" % [PLAYER_NAMES[p], new_bid]
	else:
		passed[p] = true
		message_label.text = "%s пасує" % PLAYER_NAMES[p]
	_render_status()

func _hand_strength(hand: Array) -> int:
	var total := 0
	for c in hand:
		total += c.thousand_points()
	var suits_with_pair := {}
	for c in hand:
		if c.rank == 12 or c.rank == 13:
			if not suits_with_pair.has(c.suit):
				suits_with_pair[c.suit] = 0
			suits_with_pair[c.suit] += 1
	for suit in suits_with_pair:
		if suits_with_pair[suit] >= 2:
			total += 20
	return total

func _finish_bidding() -> void:
	bidding_panel.visible = false
	if highest_bidder == -1:
		message_label.text = "Everyone passed. Redealing..."
		await get_tree().create_timer(1.2).timeout
		start_new_round()
		return
	status_label.text = "%s won the bid at %d" % [PLAYER_NAMES[highest_bidder], highest_bid]
	_start_discard_phase()

# ---------------------------------------------------------------------------
# DISCARDING (bid winner takes the widow, then discards back to 7)
# ---------------------------------------------------------------------------

func _start_discard_phase() -> void:
	phase = Phase.DISCARDING
	hands[highest_bidder].append_array(widow)
	widow = []
	hands[highest_bidder].sort_custom(func(a, b): return _card_sort_key(a) < _card_sort_key(b))
	_render_hands(highest_bidder == 0)

	if highest_bidder == 0:
		discard_panel.visible = true
		selected_discards.clear()
		confirm_discard_button.disabled = true
		status_label.text = "Виберіть 3 карти для скидання"
	else:
		status_label.text = "%s скидає..." % PLAYER_NAMES[highest_bidder]
		await get_tree().create_timer(0.9).timeout
		_ai_discard(highest_bidder)
		_start_playing_phase()

func _ai_discard(p: int) -> void:
	hands[p].sort_custom(func(a, b): return a.thousand_points() < b.thousand_points())
	for i in 3:
		hands[p].pop_front()
	hands[p].sort_custom(func(a, b): return _card_sort_key(a) < _card_sort_key(b))
	_render_hands(false)

func _on_confirm_discard() -> void:
	for c in selected_discards:
		hands[0].erase(c)
	selected_discards.clear()
	discard_panel.visible = false
	_start_playing_phase()

# ---------------------------------------------------------------------------
# PLAYING TRICKS
# ---------------------------------------------------------------------------

func _start_playing_phase() -> void:
	phase = Phase.PLAYING
	trick_leader = highest_bidder
	current_turn = trick_leader
	trick_cards = [null, null, null]
	_clear_trick_area()
	message_label.text = "Торги завершено. %s ходить першим." % PLAYER_NAMES[trick_leader]
	_render_hands(true)
	status_label.text = "Гра — контракт %d" % highest_bid
	_advance_play()

func _advance_play() -> void:
	# All cards played — the round is over. This must be checked BEFORE any
	# AI move, otherwise the leader of the "8th trick" would crash on an
	# empty hand (legal[0] on empty array).
	if hands[0].is_empty() and hands[1].is_empty() and hands[2].is_empty():
		_end_round()
		return
	if current_turn == 0:
		status_label.text = "Ваш хід"
		_update_hand_interactivity()
	else:
		status_label.text = "%s ходить..." % PLAYER_NAMES[current_turn]
		await get_tree().create_timer(0.7).timeout
		var card: Card = _ai_choose_card(current_turn)
		if card == null:
			_end_round()
			return
		_play_card(current_turn, card)

func _try_play_human_card(card: Card, hand_card_node: Control) -> void:
	if phase != Phase.PLAYING or current_turn != 0:
		return
	# Guard: player already played this trick (fast double-click during resolve pause).
	if trick_cards[0] != null:
		return
	var legal: Array = _legal_cards(0)
	if not legal.has(card):
		message_label.text = "Потрібно ходити в масть!"
		hand_card_node.animate_reject()
		return
	_play_card(0, card)

func _play_card(player: int, card: Card) -> void:
	var is_lead := true
	for c in trick_cards:
		if c != null:
			is_lead = false
			break

	hands[player].erase(card)

	if is_lead and (card.rank == 12 or card.rank == 13):
		var pair_rank: int = 12 if card.rank == 13 else 13
		var has_pair := false
		for c2 in hands[player]:
			if c2.suit == card.suit and c2.rank == pair_rank:
				has_pair = true
				break
		if has_pair:
			var mv := _marriage_value(card.suit)
			marriage_points[player] += mv
			if trump_suit == -1:
				trump_suit = card.suit
			message_label.text = "%s оголошує шлюб у %s! (+%d)" % [PLAYER_NAMES[player], _suit_name(card.suit), mv]
			CardFX.pulse(message_label)

	trick_cards[player] = card
	_place_trick_card_visual(player, card)
	if player == 0:
		_render_hands(false)
	else:
		ai_west_label.text = "ІІ Захід — %d карт" % hands[1].size()
		ai_east_label.text = "ІІ Схід — %d карт" % hands[2].size()

	var all_played := true
	for c in trick_cards:
		if c == null:
			all_played = false
			break

	if all_played:
		await get_tree().create_timer(0.9).timeout
		_resolve_trick()
	else:
		current_turn = (player + 1) % 3
		_advance_play()

func _resolve_trick() -> void:
	# Idempotency guard: a stray double-call (fast player clicks during the
	# 0.9s resolve pause) must not crash on an already-cleared trick.
	if trick_cards[0] == null or trick_cards[1] == null or trick_cards[2] == null:
		return
	var led_suit: int = trick_cards[trick_leader].suit
	var best_player := trick_leader
	var best_score := _card_score(trick_cards[trick_leader], led_suit)
	for p in 3:
		if p == trick_leader:
			continue
		var s := _card_score(trick_cards[p], led_suit)
		if s > best_score:
			best_score = s
			best_player = p

	var trick_points := 0
	for c in trick_cards:
		trick_points += c.thousand_points()
	tricks_won_points[best_player] += trick_points
	message_label.text = "%s виграє взятку (+%d очок)" % [PLAYER_NAMES[best_player], trick_points]

	# Sweep the played cards toward the winner's slot, then free them.
	var winner_holder: Control = slot_holder[best_player]
	for p in 3:
		var cv = trick_card_views[p]
		if cv != null:
			var direction: Vector2 = (winner_holder.global_position - cv.global_position) * 0.7
			cv.animate_collect(direction)
	trick_card_views = {0: null, 1: null, 2: null}

	trick_leader = best_player
	current_turn = best_player
	trick_cards = [null, null, null]

	if hands[0].is_empty():
		await get_tree().create_timer(CardFX.COLLECT_DURATION + 0.1).timeout
		_end_round()
	else:
		await get_tree().create_timer(CardFX.COLLECT_DURATION + 0.15).timeout
		_advance_play()

func _card_score(card: Card, led_suit: int) -> int:
	if trump_suit != -1 and card.suit == trump_suit:
		return 1000 + card.thousand_order_value()
	elif card.suit == led_suit:
		return card.thousand_order_value()
	else:
		return -1

func _legal_cards(player: int) -> Array:
	if trick_cards[trick_leader] == null:
		return hands[player].duplicate()
	var led_suit: int = trick_cards[trick_leader].suit
	var matching := []
	for c in hands[player]:
		if c.suit == led_suit:
			matching.append(c)
	if matching.size() > 0:
		return matching
	return hands[player].duplicate()

func _ai_choose_card(player: int) -> Card:
	var legal: Array = _legal_cards(player)
	if legal.is_empty():
		return null
	var is_lead: bool = trick_cards[trick_leader] == null

	if is_lead:
		for c in legal:
			if c.rank == 12 or c.rank == 13:
				var pair_rank: int = 12 if c.rank == 13 else 13
				for c2 in hands[player]:
					if c2.suit == c.suit and c2.rank == pair_rank and c2 != c:
						return c
		legal.sort_custom(func(a, b): return a.thousand_order_value() < b.thousand_order_value())
		for c in legal:
			if trump_suit == -1 or c.suit != trump_suit:
				return c
		return legal[0]
	else:
		var led_suit: int = trick_cards[trick_leader].suit
		var current_best := -1
		for c in trick_cards:
			if c != null:
				var s := _card_score(c, led_suit)
				if s > current_best:
					current_best = s
		var winning_candidates := []
		for c in legal:
			if _card_score(c, led_suit) > current_best:
				winning_candidates.append(c)
		if winning_candidates.size() > 0:
			winning_candidates.sort_custom(func(a, b): return a.thousand_order_value() < b.thousand_order_value())
			return winning_candidates[0]
		else:
			legal.sort_custom(func(a, b): return a.thousand_points() < b.thousand_points())
			return legal[0]

# ---------------------------------------------------------------------------
# ROUND END / SCORING
# ---------------------------------------------------------------------------

func _end_round() -> void:
	phase = Phase.ROUND_OVER
	var bidder_total: int = tricks_won_points[highest_bidder] + marriage_points[highest_bidder]
	var result_lines := []

	if bidder_total >= highest_bid:
		total_score[highest_bidder] += bidder_total
		result_lines.append("%s виконав контракт (%d/%d)! +%d" % [PLAYER_NAMES[highest_bidder], bidder_total, highest_bid, bidder_total])
	else:
		total_score[highest_bidder] -= highest_bid
		result_lines.append("%s провалив контракт (%d/%d)! -%d" % [PLAYER_NAMES[highest_bidder], bidder_total, highest_bid, highest_bid])

	for p in 3:
		if p != highest_bidder:
			var pts: int = tricks_won_points[p] + marriage_points[p]
			total_score[p] += pts
			result_lines.append("%s набрав %d очок" % [PLAYER_NAMES[p], pts])

	message_label.text = "\n".join(result_lines)
	CardFX.pulse(score_label)
	_render_status()

	var winner := -1
	for p in 3:
		if total_score[p] >= 1000:
			winner = p

	if winner != -1:
		phase = Phase.GAME_OVER
		status_label.text = "%s виграє матч з %d очками!" % [PLAYER_NAMES[winner], total_score[winner]]
		continue_button.text = "Новий матч"
	else:
		status_label.text = "Раунд завершено"
		continue_button.text = "Наступний раунд"
	continue_button.visible = true

func _on_continue_pressed() -> void:
	if phase == Phase.GAME_OVER:
		total_score = [0, 0, 0]
		round_number = 0
	else:
		round_number += 1
	continue_button.visible = false
	start_new_round()

# ---------------------------------------------------------------------------
# RENDERING
# ---------------------------------------------------------------------------

func _render_status() -> void:
	score_label.text = "Ви: %d   ІІ Захід: %d   ІІ Схід: %d" % [total_score[0], total_score[1], total_score[2]]
	_render_ai_hands()

## Full rebuild of the player's hand row. Call only when the hand's card LIST
## actually changes (deal, discard, a card played) — pass animate=true for a
## staggered deal-in. For pure interactivity refresh use _update_hand_interactivity().
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
		var can_select: bool = phase == Phase.DISCARDING and highest_bidder == 0
		hc.disabled = not (can_play or can_select)
		hc.pressed.connect(_on_hand_card_pressed.bind(hc))
		if animate:
			hc.animate_in(i * 0.05)
		i += 1

	_render_ai_hands()

func _render_ai_hands() -> void:
	# Render AI West hand (face-down cards)
	for c in ai_west_hand.get_children():
		c.queue_free()
	for i in range(hands[1].size()):
		var cv = CardViewScene.instantiate()
		ai_west_hand.add_child(cv)
		cv.setup(null, false)  # face-down
		cv.animate_in(i * 0.03)
	
	# Render AI East hand (face-down cards)
	for c in ai_east_hand.get_children():
		c.queue_free()
	for i in range(hands[2].size()):
		var cv = CardViewScene.instantiate()
		ai_east_hand.add_child(cv)
		cv.setup(null, false)  # face-down
		cv.animate_in(i * 0.03)

	ai_west_label.text = "ІІ Захід — %d карт" % hands[1].size()
	ai_east_label.text = "ІІ Схід — %d карт" % hands[2].size()

## Lightweight refresh: only toggles which cards are clickable, no rebuild/animation.
func _update_hand_interactivity() -> void:
	var legal_now: Array = []
	if phase == Phase.PLAYING and current_turn == 0:
		legal_now = _legal_cards(0)
	for hc in player_hand_row.get_children():
		var can_play: bool = phase == Phase.PLAYING and current_turn == 0 and legal_now.has(hc.card)
		var can_select: bool = phase == Phase.DISCARDING and highest_bidder == 0
		hc.disabled = not (can_play or can_select)

func _on_hand_card_pressed(hc) -> void:
	match phase:
		Phase.DISCARDING:
			if highest_bidder == 0:
				_toggle_discard_selection(hc)
		Phase.PLAYING:
			if current_turn == 0:
				_try_play_human_card(hc.card, hc)

func _toggle_discard_selection(hc) -> void:
	if hc.selected:
		hc.selected = false
		selected_discards.erase(hc.card)
	elif selected_discards.size() < 3:
		hc.selected = true
		selected_discards.append(hc.card)
	confirm_discard_button.disabled = selected_discards.size() != 3

func _place_trick_card_visual(player: int, card: Card) -> void:
	var holder: Control = slot_holder[player]
	var cv = CardViewScene.instantiate()
	holder.add_child(cv)
	cv.setup(card, true)
	cv.animate_in()
	trick_card_views[player] = cv

func _clear_trick_area() -> void:
	for p in 3:
		var holder: Control = slot_holder[p]
		if holder == null:
			continue
		for c in holder.get_children():
			c.queue_free()
	trick_card_views = {0: null, 1: null, 2: null}

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

func _card_sort_key(c: Card) -> int:
	return c.suit * 10 + c.thousand_order_value()

func _marriage_value(suit: int) -> int:
	match suit:
		Card.Suit.HEARTS: return 100
		Card.Suit.DIAMONDS: return 80
		Card.Suit.CLUBS: return 60
		Card.Suit.SPADES: return 40
	return 0

func _suit_name(suit: int) -> String:
	match suit:
		Card.Suit.HEARTS: return "червах"
		Card.Suit.DIAMONDS: return "бубнах"
		Card.Suit.CLUBS: return "хрестах"
		Card.Suit.SPADES: return "піках"
	return "?"

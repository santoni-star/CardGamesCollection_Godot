extends Control
## Blackjack module. All animation goes through CardFX (scripts/core/CardFX.gd) —
## this file only contains Blackjack's rules; the visual feel is shared with
## every other game in the collection.

const CardViewScene := preload("res://scenes/components/CardView.tscn")

@onready var chips_label: Label = $TopBar/ChipsLabel
@onready var message_label: Label = $TopBar/MessageLabel
@onready var dealer_label: Label = $DealerSection/DealerLabel
@onready var dealer_cards: HBoxContainer = $DealerSection/DealerCards
@onready var player_label: Label = $PlayerSection/PlayerLabel
@onready var player_cards: HBoxContainer = $PlayerSection/PlayerCards
@onready var bet_spinbox: SpinBox = $BottomBar/BetRow/BetSpinBox
@onready var deal_button: Button = $BottomBar/BetRow/DealButton
@onready var hit_button: Button = $BottomBar/ActionRow/HitButton
@onready var stand_button: Button = $BottomBar/ActionRow/StandButton
@onready var double_button: Button = $BottomBar/ActionRow/DoubleButton
@onready var back_button: Button = $TopBar/BackButton

var deck: Deck
var dealer_hand: Array[Card] = []
var player_hand: Array[Card] = []
var dealer_card_views: Array = []
var player_card_views: Array = []
var current_bet: int = 0
var round_active: bool = false

func _ready() -> void:
	update_chips_label()
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	deal_button.pressed.connect(_on_deal_pressed)
	hit_button.pressed.connect(_on_hit_pressed)
	stand_button.pressed.connect(_on_stand_pressed)
	double_button.pressed.connect(_on_double_pressed)
	bet_spinbox.max_value = max(10, GameData.chips)
	_set_action_buttons(false)

func update_chips_label() -> void:
	chips_label.text = "Chips: %d" % GameData.chips

func _set_action_buttons(enabled: bool) -> void:
	hit_button.disabled = not enabled
	stand_button.disabled = not enabled
	double_button.disabled = not enabled or GameData.chips < current_bet or player_hand.size() != 2

func _clear_table() -> void:
	for v in dealer_card_views:
		v.queue_free()
	for v in player_card_views:
		v.queue_free()
	dealer_card_views.clear()
	player_card_views.clear()
	dealer_hand.clear()
	player_hand.clear()

func _add_dealer_card(card: Card, face_up: bool, delay: float = 0.0) -> void:
	var cv = CardViewScene.instantiate()
	dealer_cards.add_child(cv)
	cv.setup(card, face_up)
	dealer_card_views.append(cv)
	cv.animate_in(delay)

func _add_player_card(card: Card, delay: float = 0.0) -> void:
	var cv = CardViewScene.instantiate()
	player_cards.add_child(cv)
	cv.setup(card, true)
	player_card_views.append(cv)
	cv.animate_in(delay)

func _on_deal_pressed() -> void:
	current_bet = int(bet_spinbox.value)
	if current_bet > GameData.chips:
		message_label.text = "Not enough chips!"
		CardFX.shake(message_label)
		return

	message_label.text = ""
	_clear_table()
	deck = Deck.new()
	deck.build_standard()
	deck.shuffle()
	round_active = true

	player_hand = [deck.draw_card(), deck.draw_card()]
	dealer_hand = [deck.draw_card(), deck.draw_card()]

	# Deal one card at a time, staggered, dealer's second card face-down.
	_add_player_card(player_hand[0], 0.0)
	_add_dealer_card(dealer_hand[0], true, 0.12)
	_add_player_card(player_hand[1], 0.24)
	_add_dealer_card(dealer_hand[1], false, 0.36)

	_update_labels(false)
	deal_button.disabled = true
	bet_spinbox.editable = false
	_set_action_buttons(true)

	if _hand_value(player_hand) == 21:
		await get_tree().create_timer(0.7).timeout
		_finish_round()

func _update_labels(reveal_dealer: bool) -> void:
	player_label.text = "You: %d" % _hand_value(player_hand)
	if reveal_dealer:
		dealer_label.text = "Dealer: %d" % _hand_value(dealer_hand)
	else:
		dealer_label.text = "Dealer: %d + ?" % dealer_hand[0].blackjack_value()

func _hand_value(hand: Array[Card]) -> int:
	var total := 0
	var aces := 0
	for card in hand:
		total += card.blackjack_value()
		if card.rank == 1:
			aces += 1
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total

func _on_hit_pressed() -> void:
	if not round_active:
		return
	var card = deck.draw_card()
	player_hand.append(card)
	_add_player_card(card)
	_update_labels(false)
	_set_action_buttons(true)
	if _hand_value(player_hand) >= 21:
		await get_tree().create_timer(0.5).timeout
		_finish_round()

func _on_double_pressed() -> void:
	if not round_active or GameData.chips < current_bet * 2:
		return
	current_bet *= 2
	var card = deck.draw_card()
	player_hand.append(card)
	_add_player_card(card)
	_update_labels(false)
	await get_tree().create_timer(0.5).timeout
	_finish_round()

func _on_stand_pressed() -> void:
	_finish_round()

func _finish_round() -> void:
	round_active = false
	_set_action_buttons(false)

	var player_total := _hand_value(player_hand)

	# Reveal the dealer's hole card with a flip animation.
	if dealer_card_views.size() > 1:
		dealer_card_views[1].animate_flip_to(dealer_hand[1], true)
		await get_tree().create_timer(CardFX.FLIP_DURATION * 2 + 0.05).timeout
	_update_labels(true)

	if player_total <= 21:
		while _hand_value(dealer_hand) < 17:
			var card = deck.draw_card()
			dealer_hand.append(card)
			_add_dealer_card(card, true)
			await get_tree().create_timer(0.45).timeout
			_update_labels(true)

	var dealer_total := _hand_value(dealer_hand)
	var result_text := ""

	if player_total > 21:
		GameData.chips -= current_bet
		result_text = "Bust! You lose %d chips." % current_bet
	elif player_total == 21 and player_hand.size() == 2:
		var win := int(current_bet * 1.5)
		GameData.chips += win
		result_text = "Blackjack! You win %d chips!" % win
	elif dealer_total > 21:
		GameData.chips += current_bet
		result_text = "Dealer busts! You win %d chips!" % current_bet
	elif player_total > dealer_total:
		GameData.chips += current_bet
		result_text = "You win %d chips!" % current_bet
	elif player_total < dealer_total:
		GameData.chips -= current_bet
		result_text = "You lose %d chips." % current_bet
	else:
		result_text = "Push. Bet returned."

	message_label.text = result_text
	CardFX.pulse(message_label)
	update_chips_label()
	GameData.reset_chips_if_broke()
	if GameData.chips <= 0:
		message_label.text += " Out of chips — reset to 500."
		update_chips_label()
	GameData.save_game()

	deal_button.disabled = false
	bet_spinbox.editable = true
	bet_spinbox.max_value = max(10, GameData.chips)

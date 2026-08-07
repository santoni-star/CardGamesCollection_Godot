class_name Card
extends RefCounted
## A single playing card. Shared by Blackjack, Hearts, Thousand.

enum Suit { HEARTS, DIAMONDS, CLUBS, SPADES }

var suit: Suit
var rank: int # 1=Ace, 2-10, 11=Jack, 12=Queen, 13=King

func _init(p_suit: Suit, p_rank: int) -> void:
	suit = p_suit
	rank = p_rank

func suit_symbol() -> String:
	match suit:
		Suit.HEARTS: return "♥"
		Suit.DIAMONDS: return "♦"
		Suit.CLUBS: return "♣"
		Suit.SPADES: return "♠"
	return "?"

func suit_color() -> Color:
	if suit == Suit.HEARTS or suit == Suit.DIAMONDS:
		return Color(0.85, 0.1, 0.1)
	return Color(0.1, 0.1, 0.1)

func rank_label() -> String:
	match rank:
		1: return "A"
		11: return "J"
		12: return "Q"
		13: return "K"
		_: return str(rank)

## Blackjack value: Ace counts as 11 here; soft/hard adjustment happens in hand_value().
func blackjack_value() -> int:
	if rank == 1:
		return 11
	elif rank >= 10:
		return 10
	return rank

## Standard trick-taking order (Ace high): 2 < 3 ... < 10 < J < Q < K < A.
## Used by games like Hearts. Distinct from thousand_order_value().
func standard_order_value() -> int:
	if rank == 1:
		return 14
	return rank

## Order strength for the Thousand (1000) card game: 9 < J < Q < K < 10 < A
func thousand_order_value() -> int:
	match rank:
		9: return 0
		11: return 1
		12: return 2
		13: return 3
		10: return 4
		1: return 5
	return -1

## Points value for Thousand scoring.
func thousand_points() -> int:
	match rank:
		1: return 11
		10: return 10
		13: return 4
		12: return 3
		11: return 2
		9: return 0
	return 0

func to_short_string() -> String:
	return rank_label() + suit_symbol()

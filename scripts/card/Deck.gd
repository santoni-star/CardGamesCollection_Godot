class_name Deck
extends RefCounted
## A shuffleable stack of Cards.

var cards: Array[Card] = []

## Standard 52-card deck by default. Pass a subset of ranks for shortened decks.
func build_standard(include_ranks: Array = [1,2,3,4,5,6,7,8,9,10,11,12,13]) -> void:
	cards.clear()
	for suit in [Card.Suit.HEARTS, Card.Suit.DIAMONDS, Card.Suit.CLUBS, Card.Suit.SPADES]:
		for rank in include_ranks:
			cards.append(Card.new(suit, rank))

## 24-card deck used by the Thousand (1000) card game: 9,10,J,Q,K,A per suit.
func build_thousand_deck() -> void:
	build_standard([9, 10, 11, 12, 13, 1])

func shuffle() -> void:
	cards.shuffle()

func draw_card() -> Card:
	if cards.is_empty():
		return null
	return cards.pop_back()

func is_empty() -> bool:
	return cards.is_empty()

func size() -> int:
	return cards.size()

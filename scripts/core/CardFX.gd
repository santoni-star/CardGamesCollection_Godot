class_name CardFX
extends RefCounted
## Shared animation layer ("engine" core) used by every card game module
## (Blackjack, Thousand, Hearts, and any future game). A new game module
## never writes its own tween code — it just calls these helpers, so the
## visual feel stays identical everywhere and only the RULES differ per game.

const DEAL_DURATION := 0.28
const MOVE_DURATION := 0.32
const FLIP_DURATION := 0.14
const COLLECT_DURATION := 0.35

## Fade + pop a freshly-added card into place. Use when dealing / drawing / passing.
static func deal_in(node: Control, delay: float = 0.0) -> void:
	node.modulate.a = 0.0
	node.scale = Vector2(0.7, 0.7)
	node.pivot_offset = node.custom_minimum_size / 2.0
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "modulate:a", 1.0, DEAL_DURATION).set_delay(delay)
	tween.tween_property(node, "scale", Vector2(1, 1), DEAL_DURATION) \
		.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Slide a card to a target LOCAL position (within its current parent).
static func move_to(node: Control, target_pos: Vector2, duration: float = MOVE_DURATION) -> Tween:
	var tween := node.create_tween()
	tween.tween_property(node, "position", target_pos, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tween

## Flip a card in place: shrink on X, swap the face via callback, grow back.
static func flip(node: Control, on_midpoint: Callable) -> void:
	node.pivot_offset = node.custom_minimum_size / 2.0
	var tween := node.create_tween()
	tween.tween_property(node, "scale:x", 0.0, FLIP_DURATION).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(on_midpoint)
	tween.tween_property(node, "scale:x", 1.0, FLIP_DURATION).set_trans(Tween.TRANS_SINE)

## Quick emphasis bounce — winning hand, announced marriage, big score, etc.
static func pulse(node: Control) -> void:
	node.pivot_offset = node.size / 2.0
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector2(1.12, 1.12), 0.12).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "scale", Vector2(1, 1), 0.12).set_trans(Tween.TRANS_SINE)

## Sweep a played card away (toward the trick winner) then free it. Used to
## visually "collect" a finished trick instead of it just vanishing.
static func collect_and_free(node: Control, direction: Vector2, duration: float = COLLECT_DURATION) -> void:
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "position", node.position + direction, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(node, "modulate:a", 0.0, duration)
	tween.finished.connect(node.queue_free)

## Gentle shake — used for illegal-move feedback ("must follow suit" etc).
static func shake(node: Control) -> void:
	var start_x := node.position.x
	var tween := node.create_tween()
	tween.tween_property(node, "position:x", start_x - 6, 0.05)
	tween.tween_property(node, "position:x", start_x + 6, 0.05)
	tween.tween_property(node, "position:x", start_x - 4, 0.05)
	tween.tween_property(node, "position:x", start_x, 0.05)

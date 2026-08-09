extends Control

@onready var chips_label: Label = $CenterContainer/VBoxContainer/ChipsLabel
@onready var kosynka_button: Button = $CenterContainer/VBoxContainer/KosynkaButton
@onready var blackjack_button: Button = $CenterContainer/VBoxContainer/BlackjackButton
@onready var hearts_button: Button = $CenterContainer/VBoxContainer/HeartsButton
@onready var thousand_button: Button = $CenterContainer/VBoxContainer/ThousandButton
@onready var settings_button: Button = $CenterContainer/VBoxContainer/SettingsButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

func _ready() -> void:
	chips_label.text = "Фішки: %d" % GameData.chips
	kosynka_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/games/Kosynka/Kosynka.tscn"))
	blackjack_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/games/Blackjack/Blackjack.tscn"))
	hearts_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/games/Hearts/Hearts.tscn"))
	thousand_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/games/Thousand/Thousand.tscn"))
	settings_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Settings.tscn"))
	quit_button.pressed.connect(func(): get_tree().quit())

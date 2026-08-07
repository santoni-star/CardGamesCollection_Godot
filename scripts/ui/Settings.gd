extends Control

@onready var sound_slider: HSlider = $CenterContainer/VBoxContainer/SoundSlider
@onready var music_slider: HSlider = $CenterContainer/VBoxContainer/MusicSlider
@onready var name_edit: LineEdit = $CenterContainer/VBoxContainer/NameEdit
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

func _ready() -> void:
	sound_slider.value = GameData.sound_volume
	music_slider.value = GameData.music_volume
	name_edit.text = GameData.player_name

	sound_slider.value_changed.connect(func(v): GameData.sound_volume = v; GameData.save_game())
	music_slider.value_changed.connect(func(v): GameData.music_volume = v; GameData.save_game())
	name_edit.text_changed.connect(func(t): GameData.player_name = t)
	name_edit.focus_exited.connect(func(): GameData.save_game())
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))

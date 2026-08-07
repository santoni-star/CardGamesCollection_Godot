extends Node
## Global autoload: player state, settings, save/load.
## Access anywhere in the project as `GameData`.

var chips: int = 1000
var sound_volume: float = 0.8
var music_volume: float = 0.6
var player_name: String = "Player"

const SAVE_PATH := "user://savegame.dat"

func _ready() -> void:
	load_game()

func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data := {
			"chips": chips,
			"sound_volume": sound_volume,
			"music_volume": music_volume,
			"player_name": player_name,
		}
		file.store_string(JSON.stringify(data))
		file.close()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var text := file.get_as_text()
		file.close()
		var json := JSON.new()
		if json.parse(text) == OK:
			var data: Dictionary = json.get_data()
			chips = data.get("chips", 1000)
			sound_volume = data.get("sound_volume", 0.8)
			music_volume = data.get("music_volume", 0.6)
			player_name = data.get("player_name", "Player")

func reset_chips_if_broke() -> void:
	if chips <= 0:
		chips = 500
		save_game()

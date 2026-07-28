extends Node
# Autoload: Session
#
# Guarda o que foi escolhido no menu para a cena de jogo ler a seguir.
# As cenas em Godot não recebem argumentos, daí este intermediário.

var player_faction: String = ""
var ai_faction: String = ""

func set_match(player_slug: String, ai_slug: String) -> void:
	player_faction = player_slug
	ai_faction = ai_slug

func has_match() -> bool:
	return player_faction != "" and ai_faction != ""

func clear() -> void:
	player_faction = ""
	ai_faction = ""

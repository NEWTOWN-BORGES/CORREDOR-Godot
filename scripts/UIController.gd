extends Control

var engine: GameEngine
var cartas: Dictionary = {}
var player_faction: String = "reinos"
var ai_faction: String = "coro"

@onready var tatico_container = $VBoxContainer/TacticoHand/CardContainer
@onready var hand_container = $VBoxContainer/Hand/HandContainer
@onready var hud_label = $VBoxContainer/HUD
@onready var pass_button = $VBoxContainer/ButtonPass

func _ready():
	engine = GameEngine.new()
	_load_cards()
	_start_game()
	_render_game()
	pass_button.pressed.connect(_on_pass)

func _load_cards():
	var json_str = FileAccess.get_file_as_string("res://resources/cartas.json")
	cartas = JSON.parse_string(json_str)
	print("Carregadas: %d cartas" % [
		cartas.get("unidades", []).size() +
		cartas.get("apoios", []).size() +
		cartas.get("taticos", []).size()
	])

func _start_game():
	var player_deck = _build_faction_deck(player_faction)
	var ai_deck = _build_faction_deck(ai_faction)
	engine.init_game(player_deck, ai_deck)

func _build_faction_deck(faction_slug: String) -> Array:
	var all_cards = cartas.get("unidades", []) + cartas.get("apoios", []) + cartas.get("taticos", [])
	var faction_cards = []
	for card in all_cards:
		if card.get("faccao_slug") == faction_slug:
			faction_cards.append(card)
	return faction_cards.slice(0, 20)

func _render_game():
	# Limpar
	for child in tatico_container.get_children():
		child.queue_free()
	for child in hand_container.get_children():
		child.queue_free()

	var p = engine.players["player"]

	# Render Tatico Hand
	for i in range(p.get("tacticoHand", []).size()):
		var card = p["tacticoHand"][i]
		var btn = Button.new()
		btn.text = card.get("nome", "?")
		btn.custom_minimum_size = Vector2(100, 100)
		btn.pressed.connect(func(): _play_tatico(i))
		tatico_container.add_child(btn)

	# Render Military Hand
	for i in range(p.get("hand", []).size()):
		var card = p["hand"][i]
		var btn = Button.new()
		btn.text = card.get("nome", "?")
		btn.custom_minimum_size = Vector2(100, 120)
		btn.pressed.connect(func(): _play_unit(i))
		hand_container.add_child(btn)

	# Update HUD
	hud_label.text = "CORREDOR — Godot\nTurno %d / 12 | %s\nUnidades: %d/3" % [
		engine.round,
		"A tua vez" if engine.activePlayer == "player" else "Vez do adversário",
		engine.players["player"].get("unitPlaysThisRound", 0)
	]

func _play_tatico(idx: int):
	var result = engine.play_tatico_card("player", idx, {})
	if result.get("ok"):
		print("Jogou: %s" % result.get("card", {}).get("nome", "?"))
		_render_game()
	else:
		print("Erro: %s" % result.get("error", "?"))

func _play_unit(idx: int):
	# Simplificado: coloca sempre na primeira slot livre
	var p = engine.players["player"]
	var card = p["hand"][idx]

	var slot_type = "frente"
	var slot_idx = 0
	for i in range(6):
		if p["front"][i] == null:
			slot_idx = i
			break

	var result = engine.play_unit("player", idx, slot_type, slot_idx)
	if result.get("ok"):
		print("Jogou unidade: %s" % result.get("card", {}).get("nome", "?"))
		_render_game()
	else:
		print("Erro: %s" % result.get("error", "?"))

func _on_pass():
	var result = engine.pass_turn("player")
	if result.get("ok"):
		print("Passou")
		_render_game()

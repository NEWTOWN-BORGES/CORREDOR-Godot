extends Control

# Ligação provisória entre o motor e a UI (será substituída nas Fases 3-6
# por MenuController + BoardRenderer + HandRenderer). Serve para validar que
# o motor arranca, distribui mão e aceita jogadas.

# Usadas só se a cena for aberta directamente, sem passar pelo menu.
const FALLBACK_PLAYER_FACTION := "reinos"
const FALLBACK_AI_FACTION := "coro"

var engine: Game = null
var cartas: Dictionary = {}
var log_lines: Array = []

@onready var tatico_container: HBoxContainer = $VBoxContainer/TacticoHand/CardContainer
@onready var hand_container: HBoxContainer = $VBoxContainer/Hand/HandContainer
@onready var hud_label: Label = $VBoxContainer/HUD
@onready var pass_button: Button = $VBoxContainer/ButtonPass

func _ready() -> void:
	engine = Game.new()
	if not _load_cards():
		hud_label.text = "Erro: não foi possível carregar res://resources/cartas.json"
		return
	_start_game()
	_render_game()
	pass_button.pressed.connect(_on_pass)

# As cartas vêm do autoload Cards (scripts/CardLoader.gd), que também serve
# as texturas a pedido — ver Fase 2.
func _load_cards() -> bool:
	if not Cards.load_all():
		return false
	cartas = Cards.as_dictionary()
	print("Carregadas %d unidades, %d apoios, %d táticos" % [
		(cartas["unidades"] as Array).size(),
		(cartas["apoios"] as Array).size(),
		(cartas["taticos"] as Array).size()
	])
	return true

func _start_game() -> void:
	var player_slug := FALLBACK_PLAYER_FACTION
	var ai_slug := FALLBACK_AI_FACTION
	if Session.has_match():
		player_slug = Session.player_faction
		ai_slug = Session.ai_faction

	print("Partida: %s contra %s" % [player_slug, ai_slug])
	var player_deck := DeckManager.build_faction_deck(cartas, player_slug)
	var ai_deck := DeckManager.build_faction_deck(cartas, ai_slug)
	engine.init_game(player_deck, ai_deck, _on_engine_log)

func _on_engine_log(msg: String) -> void:
	log_lines.append(msg)
	print(msg)

func _render_game() -> void:
	for child in tatico_container.get_children():
		child.queue_free()
	for child in hand_container.get_children():
		child.queue_free()

	var p: Dictionary = engine.players["player"]
	var my_turn: bool = engine.active_player == "player" and engine.phase == "placement"

	var tactico_hand: Array = p["tacticoHand"]
	for i in range(tactico_hand.size()):
		var btn := Button.new()
		btn.text = str(tactico_hand[i].get("nome", "?"))
		btn.custom_minimum_size = Vector2(110, 90)
		btn.disabled = not my_turn
		var idx := i
		btn.pressed.connect(func(): _play_tatico(idx))
		tatico_container.add_child(btn)

	var hand: Array = p["hand"]
	for i in range(hand.size()):
		var card: Dictionary = hand[i]
		var btn := Button.new()
		btn.text = "%s\n%d/%d" % [
			str(card.get("nome", "?")),
			int(card.get("ataque", 0)),
			int(card.get("vida", 0))
		]
		btn.custom_minimum_size = Vector2(110, 120)
		btn.disabled = not my_turn
		var idx := i
		btn.pressed.connect(func(): _play_unit(idx))
		hand_container.add_child(btn)

	pass_button.disabled = not my_turn
	_render_hud()

func _render_hud() -> void:
	var turn_text := ""
	if engine.phase == "gameover":
		turn_text = "Fim de jogo — vencedor: %s" % engine.winner
	elif engine.active_player == "player":
		turn_text = "A tua vez"
	else:
		turn_text = "Vez do adversário"

	hud_label.text = "CORREDOR — Turno %d/%d | %s\nTorres  tu %d  ·  adversário %d   |   Unidades %d/%d" % [
		engine.current_round, Game.ROUND_LIMIT, turn_text,
		engine.towers["player"], engine.towers["ai"],
		engine.players["player"]["unitPlaysThisRound"], engine.get_unit_cap("player")
	]

func _play_tatico(idx: int) -> void:
	var result := engine.play_tatico_card("player", idx, {})
	if not result.get("ok", false):
		print("Não deu: %s" % result.get("error", "?"))
	_render_game()
	_maybe_advance_ai()

func _play_unit(idx: int) -> void:
	var p: Dictionary = engine.players["player"]
	if idx >= (p["hand"] as Array).size():
		return
	var card: Dictionary = p["hand"][idx]

	# Escolhe automaticamente a primeira casa válida para o papel da carta.
	var placed := false
	for slot_type in ["frente", "retaguarda"]:
		var lanes: Array = range(Game.FRONT_LANES) if slot_type == "frente" else Game.BACK_LANES
		for lane in lanes:
			if engine.can_place_unit("player", card, slot_type, lane):
				var result := engine.play_unit("player", idx, slot_type, lane)
				if result.get("ok", false):
					placed = true
				else:
					print("Não deu: %s" % result.get("error", "?"))
				break
		if placed:
			break

	if not placed:
		print("Sem casa livre para %s" % card.get("nome", "?"))
	_render_game()
	_maybe_advance_ai()

func _on_pass() -> void:
	engine.pass_turn("player")
	_render_game()
	_maybe_advance_ai()

# A IA a sério chega na Fase 8; por agora passa, para o turno poder avançar.
func _maybe_advance_ai() -> void:
	while engine.phase == "placement" and engine.active_player == "ai":
		engine.pass_turn("ai")
	_render_game()

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
@onready var board_area: AspectRatioContainer = $VBoxContainer/BoardArea
@onready var board: BoardRenderer = $VBoxContainer/BoardArea/Board

func _ready() -> void:
	engine = Game.new()
	if not _load_cards():
		hud_label.text = "Erro: não foi possível carregar res://resources/cartas.json"
		return
	_setup_board()
	_start_game()
	_render_game()
	pass_button.pressed.connect(_on_pass)

func _setup_board() -> void:
	board.slot_clicked.connect(_on_slot_clicked)
	get_viewport().size_changed.connect(_update_orientation)
	_update_orientation()

# A arte tem duas versões, paisagem e retrato, com geometrias diferentes.
func _update_orientation() -> void:
	var tamanho := get_viewport_rect().size
	var portrait := tamanho.y > tamanho.x
	board.set_portrait(portrait)
	board_area.ratio = BoardGeometry.aspect_ratio(portrait)

func _on_slot_clicked(owner_id: String, slot_type: String, lane: int) -> void:
	# A colocação por clique na casa chega na Fase 6.
	print("casa clicada: %s %s %d" % [owner_id, slot_type, lane])

func _on_board_card_clicked(card: Dictionary) -> void:
	# A pré-visualização ampliada chega na Fase 6.
	print("carta: %s (%d/%d)" % [
		card.get("nome", "?"), engine.get_effective_ataque(card), card.get("vidaAtual", 0)
	])

# Clicar num equipamento retira-o e devolve os bónus, como no web.
func _on_equipment_clicked(card: Dictionary, equip_index: int) -> void:
	if str(card.get("ownerId", "")) != "player":
		return
	engine.remove_equipamento(str(card.get("uid", "")), equip_index)
	_render_game()

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
	_render_board()
	_render_hands()

	var my_turn: bool = engine.active_player == "player" and engine.phase == "placement"
	pass_button.disabled = not my_turn
	_render_hud()

# Cada casa do tabuleiro guarda a CardView do uid que lá está; se o motor
# tiver outra carta (ou nenhuma), refaz-se só essa casa.
func _render_board() -> void:
	for owner_id in ["player", "ai"]:
		var p: Dictionary = engine.players[owner_id]
		for slot_type in ["frente", "retaguarda"]:
			var arr: Array = p["front"] if slot_type == "frente" else p["back"]
			for lane in range(Game.FRONT_LANES):
				_sync_slot(owner_id, slot_type, lane, arr[lane])

	board.set_tower("player", int(engine.towers["player"]))
	board.set_tower("ai", int(engine.towers["ai"]))
	board.update_board_art(int(engine.towers["player"]), int(engine.towers["ai"]))

func _sync_slot(owner_id: String, slot_type: String, lane: int, card) -> void:
	var holder := board.card_holder(owner_id, slot_type, lane)
	if holder == null:
		return

	var existente: CardView = null
	for child in holder.get_children():
		if child is CardView:
			existente = child
			break

	if card == null:
		if existente != null:
			holder.remove_child(existente)
			existente.queue_free()
		return

	var uid := str(card.get("uid", ""))
	if existente != null and str(existente.card.get("uid", "")) == uid:
		existente.refresh()
		return

	# remove_child antes de queue_free, senão a vista antiga ainda aparece
	# na lista de filhos até ao fim do frame
	if existente != null:
		holder.remove_child(existente)
		existente.queue_free()

	var vista := CardView.new()
	vista.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vista.card_clicked.connect(_on_board_card_clicked)
	vista.equipment_clicked.connect(_on_equipment_clicked)
	holder.add_child(vista)
	vista.bind(engine, card)

func _render_hands() -> void:
	for container in [tatico_container, hand_container]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()

	var p: Dictionary = engine.players["player"]
	var my_turn: bool = engine.active_player == "player" and engine.phase == "placement"

	var tactico_hand: Array = p["tacticoHand"]
	for i in range(tactico_hand.size()):
		tatico_container.add_child(_make_hand_card(tactico_hand[i], i, my_turn, true))

	var hand: Array = p["hand"]
	for i in range(hand.size()):
		hand_container.add_child(_make_hand_card(hand[i], i, my_turn, false))

# Na mão o web mostra só a arte da carta, sem stats sobrepostos.
func _make_hand_card(card_def: Dictionary, index: int, playable: bool, tatico: bool) -> Control:
	var altura := 84.0 if tatico else 116.0
	var largura := altura * (750.0 / 1050.0)

	var vista := CardView.new()
	vista.show_overlays = false
	vista.custom_minimum_size = Vector2(largura, altura)
	vista.modulate = Color(1, 1, 1, 1) if playable else Color(0.55, 0.55, 0.55, 1)
	if playable:
		if tatico:
			vista.card_clicked.connect(func(_c): _play_tatico(index))
		else:
			vista.card_clicked.connect(func(_c): _play_unit(index))
	vista.bind(engine, card_def)
	return vista

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

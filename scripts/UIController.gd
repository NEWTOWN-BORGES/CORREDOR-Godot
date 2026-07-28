extends Control

# Cena de jogo — tradução do fluxo de interacção do js/ui-controller.js.
#
# O caminho de uma jogada é o mesmo do web, de propósito:
#   1. clicar na carta da mão abre a pré-visualização ampliada
#   2. lê-se a carta toda; só ao carregar em "Jogar" é que se entra em modo
#      de escolher casa ou alvo
#   3. unidades acendem as casas válidas; Apoios e Equipamentos acendem as
#      cartas que podem receber
#   4. clicar confirma

# Usadas só se a cena for aberta directamente, sem passar pelo menu.
const FALLBACK_PLAYER_FACTION := "reinos"
const FALLBACK_AI_FACTION := "coro"
const MENU_SCENE := "res://scenes/MainMenu.tscn"

# Tempos das animações de combate, iguais aos do web (em segundos).
const T_LUNGE := 0.55
const T_HIT := 0.35
const T_DEATH := 0.45
const T_SIEGE := 0.50
const T_AI_THINK := 0.50

# Os testes põem isto a 0 para não esperarem por animações.
var animation_speed: float = 1.0

var engine: Game = null
var ai: AIPlayer = null
var cartas: Dictionary = {}
var log_lines: Array = []

# Estado da interacção
var _selected_hand_index: int = -1
var _pending_apoio: Dictionary = {}     # hand_index, def, card_def, pair_from
var _pending_tactico: Dictionary = {}   # index, card_def
var _busy: bool = false

@onready var tatico_container: HBoxContainer = $VBoxContainer/TacticoHand/CardContainer
@onready var hand_container: HBoxContainer = $VBoxContainer/Hand/HandContainer
@onready var hud_label: Label = $VBoxContainer/HUD
@onready var pass_button: Button = $VBoxContainer/ButtonPass
@onready var board_area: AspectRatioContainer = $VBoxContainer/BoardArea
@onready var board: BoardRenderer = $VBoxContainer/BoardArea/Board

@onready var zoom_overlay: Control = $ZoomOverlay
@onready var zoom_card: TextureRect = $ZoomOverlay/Center/Column/ZoomCard
@onready var zoom_actions: HBoxContainer = $ZoomOverlay/Center/Column/Actions
@onready var zoom_play: Button = $ZoomOverlay/Center/Column/Actions/ZoomPlay
@onready var zoom_cancel: Button = $ZoomOverlay/Center/Column/Actions/ZoomCancel
@onready var zoom_backdrop: ColorRect = $ZoomOverlay/Backdrop

@onready var target_bar: PanelContainer = $TargetBar
@onready var target_prompt: Label = $TargetBar/Row/Prompt
@onready var target_cancel: Button = $TargetBar/Row/CancelTarget

@onready var fx_layer: FxLayer = $FxLayer
@onready var gameover_overlay: Control = $GameOverOverlay
@onready var gameover_title: Label = $GameOverOverlay/Center/Card/Column/Title
@onready var gameover_subtitle: Label = $GameOverOverlay/Center/Card/Column/Subtitle
@onready var gameover_restart: Button = $GameOverOverlay/Center/Card/Column/Restart

var _gameover_shown: bool = false

func _ready() -> void:
	engine = Game.new()
	if not _load_cards():
		hud_label.text = "Erro: não foi possível carregar res://resources/cartas.json"
		return
	_setup_board()
	_setup_overlays()
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

func _setup_board() -> void:
	board.slot_clicked.connect(_on_slot_clicked)
	board.pulse_speed = animation_speed
	fx_layer.speed = animation_speed
	get_viewport().size_changed.connect(_update_orientation)
	_update_orientation()

# Os testes mexem em animation_speed depois do _ready; isto reparte o valor
# pelos nós que também animam.
func set_animation_speed(value: float) -> void:
	animation_speed = value
	if board != null:
		board.pulse_speed = value
	if fx_layer != null:
		fx_layer.speed = value

func _setup_overlays() -> void:
	zoom_overlay.visible = false
	target_bar.visible = false
	gameover_overlay.visible = false
	zoom_cancel.pressed.connect(_close_zoom)
	target_cancel.pressed.connect(_clear_targeting)
	zoom_backdrop.gui_input.connect(_on_backdrop_input)
	gameover_restart.pressed.connect(_on_restart)
	UITheme.apply_ember(zoom_play)
	UITheme.apply_ember(zoom_cancel, true)
	UITheme.apply_ember(target_cancel, true)
	UITheme.apply_ember(pass_button)
	UITheme.apply_ember(gameover_restart)
	gameover_title.add_theme_color_override("font_color", Palette.EMBER_300)
	gameover_subtitle.add_theme_color_override("font_color", Palette.PARCHMENT_DIM)

# A arte tem duas versões, paisagem e retrato, com geometrias diferentes.
func _update_orientation() -> void:
	var tamanho := get_viewport_rect().size
	var portrait := tamanho.y > tamanho.x
	board.set_portrait(portrait)
	board_area.ratio = BoardGeometry.aspect_ratio(portrait)

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
	ai = AIPlayer.new("ai")

func _on_engine_log(msg: String) -> void:
	log_lines.append(msg)
	print(msg)

# ---------------------------------------------------------------- estado

func is_my_turn() -> bool:
	return engine.phase == "placement" and engine.active_player == "player" and not _busy

func is_targeting() -> bool:
	return not _pending_apoio.is_empty() or not _pending_tactico.is_empty()

# Espelha anyOpenSlot() do web.
func any_open_slot(card_def: Dictionary) -> bool:
	for i in range(Game.FRONT_LANES):
		if engine.can_place_unit("player", card_def, "frente", i):
			return true
	for i in Game.BACK_LANES:
		if engine.can_place_unit("player", card_def, "retaguarda", i):
			return true
	return false

func is_hand_card_playable(card_def: Dictionary) -> bool:
	if not is_my_turn():
		return false
	if card_def.get("isApoio", false):
		return not engine.players["player"]["apoiosBlocked"]
	return any_open_slot(card_def)

# ---------------------------------------------------------------- render

func _render_game() -> void:
	_render_board()
	_render_hands()
	_render_hud()
	pass_button.disabled = not is_my_turn() or is_targeting()

# Cada casa guarda a CardView do uid que lá está; se o motor tiver outra
# carta (ou nenhuma), refaz-se só essa casa.
func _render_board() -> void:
	for owner_id in ["player", "ai"]:
		var p: Dictionary = engine.players[owner_id]
		for slot_type in ["frente", "retaguarda"]:
			var arr: Array = p["front"] if slot_type == "frente" else p["back"]
			for lane in range(Game.FRONT_LANES):
				# As pontas da retaguarda são a zona de Apoio; quem trata
				# delas é _render_apoio_zones, senão apagavam-se a cada render.
				if BoardGeometry.is_apoio_slot(slot_type, lane):
					continue
				_sync_slot(owner_id, slot_type, lane, arr[lane])

	_render_apoio_zones()
	board.set_tower("player", int(engine.towers["player"]))
	board.set_tower("ai", int(engine.towers["ai"]))
	board.update_board_art(int(engine.towers["player"]), int(engine.towers["ai"]))

# As pontas da retaguarda são a zona de Apoio: mostram o último Apoio jogado,
# sem stats nem Pressão, e não ocupam espaço de unidade.
func _render_apoio_zones() -> void:
	for owner_id in ["player", "ai"]:
		var holder := board.card_holder(owner_id, "retaguarda", 0)
		if holder == null:
			continue

		var existente: CardView = null
		for child in holder.get_children():
			if child is CardView:
				existente = child
				break

		var ultimo = engine.players[owner_id]["lastApoio"]
		if ultimo == null:
			if existente != null:
				holder.remove_child(existente)
				existente.queue_free()
			continue

		var id_actual := str(ultimo.get("id", ""))
		if existente != null and str(existente.card.get("id", "")) == id_actual:
			continue

		if existente != null:
			holder.remove_child(existente)
			existente.queue_free()

		var vista := CardView.new()
		vista.show_overlays = false
		vista.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vista.card_clicked.connect(func(c): _open_zoom_readonly(c))
		holder.add_child(vista)
		vista.bind(engine, ultimo)

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
	vista.play_enter_animation(animation_speed)

func _render_hands() -> void:
	for container in [tatico_container, hand_container]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()

	var p: Dictionary = engine.players["player"]

	var tactico_hand: Array = p["tacticoHand"]
	for i in range(tactico_hand.size()):
		tatico_container.add_child(_make_hand_card(tactico_hand[i], i, true))

	var hand: Array = p["hand"]
	for i in range(hand.size()):
		hand_container.add_child(_make_hand_card(hand[i], i, false))

# Na mão o web mostra só a arte da carta, sem stats sobrepostos.
func _make_hand_card(card_def: Dictionary, index: int, tatico: bool) -> Control:
	var altura := 84.0 if tatico else 116.0
	var largura := altura * (750.0 / 1050.0)

	var vista := CardView.new()
	vista.show_overlays = false
	vista.custom_minimum_size = Vector2(largura, altura)

	var jogavel := is_my_turn() if tatico else is_hand_card_playable(card_def)
	var escolhida := (not tatico) and index == _selected_hand_index

	if escolhida:
		vista.modulate = Color(1.15, 1.05, 0.9, 1)
	elif jogavel:
		vista.modulate = Color(1, 1, 1, 1)
	else:
		vista.modulate = Color(0.55, 0.55, 0.55, 1)

	if tatico:
		vista.card_clicked.connect(func(_c): _on_tactico_card_click(index))
	else:
		vista.card_clicked.connect(func(_c): _on_hand_card_click(index))

	vista.bind(engine, card_def)
	return vista

func _render_hud() -> void:
	var turn_text := ""
	if engine.phase == "gameover":
		turn_text = "Fim de jogo — vencedor: %s" % engine.winner
	elif engine.phase == "combat":
		turn_text = "Combate..."
	elif engine.active_player == "player":
		turn_text = "A tua vez"
	else:
		turn_text = "Vez do adversário"

	hud_label.text = "CORREDOR — Turno %d/%d | %s\nTorres  tu %d  ·  adversário %d   |   Unidades %d/%d" % [
		engine.current_round, Game.ROUND_LIMIT, turn_text,
		engine.towers["player"], engine.towers["ai"],
		engine.players["player"]["unitPlaysThisRound"], engine.get_unit_cap("player")
	]

# ---------------------------------------------------------------- zoom

# Mostra a carta ampliada com "Jogar"/"Cancelar" — lê-se a carta toda antes
# de decidir; só ao carregar em "Jogar" é que entra no modo de escolher.
func _open_zoom(card_def: Dictionary, playable: bool, on_play: Callable) -> void:
	var tex := Cards.texture_for(card_def)
	if tex != null:
		zoom_card.texture = tex

	# Escala a carta a 70% da altura do ecrã, mantendo a proporção
	var altura: float = max(240.0, get_viewport_rect().size.y * 0.7)
	zoom_card.custom_minimum_size = Vector2(altura * (750.0 / 1050.0), altura)

	zoom_actions.visible = true
	zoom_play.visible = playable
	zoom_overlay.visible = true

	for ligacao in zoom_play.pressed.get_connections():
		zoom_play.pressed.disconnect(ligacao["callable"])
	if playable:
		zoom_play.pressed.connect(func():
			_close_zoom()
			on_play.call()
		)

# Carta do tabuleiro fora de modo de escolha: só para ler.
func _open_zoom_readonly(card_def: Dictionary) -> void:
	var tex := Cards.texture_for(card_def)
	if tex != null:
		zoom_card.texture = tex
	var altura: float = max(240.0, get_viewport_rect().size.y * 0.7)
	zoom_card.custom_minimum_size = Vector2(altura * (750.0 / 1050.0), altura)
	zoom_actions.visible = false
	zoom_overlay.visible = true

func _close_zoom() -> void:
	zoom_overlay.visible = false

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_close_zoom()

# ---------------------------------------------------------------- mão militar

func _on_hand_card_click(idx: int) -> void:
	if _busy or engine.phase != "placement" or engine.active_player != "player":
		return
	var hand: Array = engine.players["player"]["hand"]
	if idx < 0 or idx >= hand.size():
		return

	# Clicar outra vez na mesma carta desiste
	if _selected_hand_index == idx:
		_clear_targeting()
		return

	var card_def: Dictionary = hand[idx]
	_open_zoom(card_def, is_hand_card_playable(card_def), func(): _commit_hand_selection(idx, card_def))

func _commit_hand_selection(idx: int, card_def: Dictionary) -> void:
	_clear_targeting()

	if not card_def.get("isApoio", false):
		_selected_hand_index = idx
		_highlight_valid_slots(card_def)
		_render_hands()
		return

	# Apoio
	if engine.players["player"]["apoiosBlocked"]:
		return
	var def := engine.abilities.get_apoio_ability(str(card_def.get("id", "")))
	if def.is_empty():
		return

	if def.get("needsTarget") == null:
		_play_apoio(idx, {})
		return

	_pending_apoio = {"hand_index": idx, "def": def, "card_def": card_def, "pair_from": null}
	_selected_hand_index = idx
	_begin_apoio_targeting()
	_render_hands()

func _highlight_valid_slots(card_def: Dictionary) -> void:
	for i in range(Game.FRONT_LANES):
		if engine.can_place_unit("player", card_def, "frente", i):
			board.highlight_slot("player", "frente", i, true)
	for i in Game.BACK_LANES:
		if engine.can_place_unit("player", card_def, "retaguarda", i):
			board.highlight_slot("player", "retaguarda", i, true)

func _on_slot_clicked(owner_id: String, slot_type: String, lane: int) -> void:
	if _busy or _selected_hand_index < 0 or is_targeting():
		return
	if owner_id != "player":
		return

	var hand: Array = engine.players["player"]["hand"]
	if _selected_hand_index >= hand.size():
		return
	var card_def: Dictionary = hand[_selected_hand_index]
	if card_def.get("isApoio", false):
		return
	if not engine.can_place_unit("player", card_def, slot_type, lane):
		return

	var idx := _selected_hand_index
	# Capturar antes de limpar a mão, senão a carta já não está lá para copiar
	var viagem := _travel_rects(idx, owner_id, slot_type, lane)
	_clear_targeting()
	await _fly_card(card_def, viagem)
	await _run_action(func(): return engine.play_unit("player", idx, slot_type, lane))

# De onde para onde a carta voa: da posição dela na mão até à casa escolhida.
func _travel_rects(hand_index: int, owner_id: String, slot_type: String, lane: int) -> Dictionary:
	if hand_index < 0 or hand_index >= hand_container.get_child_count():
		return {}
	var origem: Control = hand_container.get_child(hand_index)
	var destino := board.slot_control(owner_id, slot_type, lane)
	if origem == null or destino == null:
		return {}
	return {
		"de": Rect2(origem.global_position, origem.size),
		"para": Rect2(destino.global_position, destino.size)
	}

func _fly_card(card_def: Dictionary, viagem: Dictionary) -> void:
	if viagem.is_empty() or animation_speed <= 0.0:
		return
	await fx_layer.travel_card(Cards.texture_for(card_def), viagem["de"], viagem["para"])

# ---------------------------------------------------------------- apoios

func _begin_apoio_targeting() -> void:
	var def: Dictionary = _pending_apoio["def"]
	var needs = def.get("needsTarget")

	if needs == "ally":
		_show_target_bar("Escolhe uma carta tua")
		for c in engine.allies("player"):
			_mark_card_if_valid(c, def)
	elif needs == "enemy":
		_show_target_bar("Escolhe uma carta inimiga")
		for c in engine.enemies("player"):
			_mark_card_if_valid(c, def)
	elif needs == "allyPair":
		_show_target_bar("Escolhe a carta de origem")
		for c in engine.allies("player"):
			_mark_card(c, true)

func _mark_card_if_valid(card: Dictionary, def: Dictionary) -> void:
	if def.has("requireFn") and not def["requireFn"].call(engine, "player", card):
		return
	_mark_card(card, true)

func _mark_card(card: Dictionary, on: bool) -> void:
	var vista := _find_card_view(str(card.get("uid", "")))
	if vista != null:
		vista.modulate = Color(1.3, 1.1, 0.85, 1) if on else Color(1, 1, 1, 1)
		vista.set_meta("targetable", on)

func _clear_card_marks() -> void:
	for owner_id in ["player", "ai"]:
		for slot_type in ["frente", "retaguarda"]:
			for lane in range(Game.FRONT_LANES):
				var holder := board.card_holder(owner_id, slot_type, lane)
				if holder == null:
					continue
				for child in holder.get_children():
					if child is CardView:
						(child as CardView).modulate = Color(1, 1, 1, 1)
						(child as CardView).set_meta("targetable", false)

func _find_card_view(uid: String) -> CardView:
	for owner_id in ["player", "ai"]:
		for slot_type in ["frente", "retaguarda"]:
			for lane in range(Game.FRONT_LANES):
				var holder := board.card_holder(owner_id, slot_type, lane)
				if holder == null:
					continue
				for child in holder.get_children():
					if child is CardView and str((child as CardView).card.get("uid", "")) == uid:
						return child
	return null

func _play_apoio(idx: int, spec: Dictionary) -> void:
	# O Apoio voa da mão para a zona de Apoio, onde se resolve e fica
	var card_def: Dictionary = engine.players["player"]["hand"][idx] if idx < (engine.players["player"]["hand"] as Array).size() else {}
	var viagem := _travel_rects(idx, "player", "retaguarda", 0)
	_clear_targeting()
	if not card_def.is_empty():
		await _fly_card(card_def, viagem)
	await _run_action(func(): return engine.play_apoio("player", idx, spec))

# ---------------------------------------------------------------- táticas

func _on_tactico_card_click(idx: int) -> void:
	if _busy or engine.phase != "placement" or engine.active_player != "player":
		return
	var mao: Array = engine.players["player"]["tacticoHand"]
	if idx < 0 or idx >= mao.size():
		return
	var card_def: Dictionary = mao[idx]
	_open_zoom(card_def, is_my_turn(), func(): _play_tactico(idx, card_def))

func _play_tactico(idx: int, card_def: Dictionary) -> void:
	# Equipamentos precisam de uma unidade amiga para vestir
	if str(card_def.get("tipo_tatico", "")) == "Equipamento":
		_clear_targeting()
		_pending_tactico = {"index": idx, "card_def": card_def}
		_show_target_bar("Escolhe uma unidade para equipar com %s" % card_def.get("nome", ""))
		for c in engine.allies("player"):
			_mark_card(c, true)
		_render_hands()
		return

	_clear_targeting()
	await _run_action(func(): return engine.play_tatico_card("player", idx, {}))

func _confirm_tactico_target(target_card: Dictionary) -> void:
	var idx: int = int(_pending_tactico["index"])
	_clear_targeting()
	await _run_action(func(): return engine.play_tatico_card("player", idx, {"targetCard": target_card}))

# ---------------------------------------------------------------- alvos

func _show_target_bar(texto: String) -> void:
	target_prompt.text = texto
	target_bar.visible = true

func _clear_targeting() -> void:
	_pending_apoio = {}
	_pending_tactico = {}
	_selected_hand_index = -1
	board.clear_highlights()
	_clear_card_marks()
	target_bar.visible = false
	_render_hands()
	pass_button.disabled = not is_my_turn()

func _on_board_card_clicked(card: Dictionary) -> void:
	if _busy:
		return

	# Equipamento à espera de alvo
	if not _pending_tactico.is_empty():
		if str(card.get("ownerId", "")) != "player":
			return
		_confirm_tactico_target(card)
		return

	# Apoio à espera de alvo
	if not _pending_apoio.is_empty():
		_resolve_apoio_target(card)
		return

	# Fora de modo de escolha, clicar numa carta é só para a ler
	_open_zoom_readonly(card)

func _resolve_apoio_target(card: Dictionary) -> void:
	var def: Dictionary = _pending_apoio["def"]
	var hand_index: int = int(_pending_apoio["hand_index"])
	var needs = def.get("needsTarget")

	if needs == "allyPair":
		var pair_from = _pending_apoio["pair_from"]
		if pair_from == null:
			if str(card.get("ownerId", "")) != "player":
				return
			_pending_apoio["pair_from"] = card
			_clear_card_marks()
			for c in engine.allies("player"):
				if str(c.get("uid", "")) != str(card.get("uid", "")):
					_mark_card(c, true)
			target_prompt.text = "Escolhe a carta que recebe"
			return
		if str(card.get("uid", "")) == str(pair_from.get("uid", "")):
			return
		if str(card.get("ownerId", "")) != "player":
			return
		_play_apoio(hand_index, {"from": pair_from, "to": card})
		return

	var dono_certo := "player" if needs == "ally" else "ai"
	if str(card.get("ownerId", "")) != dono_certo:
		return
	if def.has("requireFn") and not def["requireFn"].call(engine, "player", card):
		return
	_play_apoio(hand_index, {"target": card})

# Clicar num equipamento retira-o e devolve os bónus, como no web.
func _on_equipment_clicked(card: Dictionary, equip_index: int) -> void:
	if not is_my_turn() or is_targeting():
		return
	if str(card.get("ownerId", "")) != "player":
		return
	engine.remove_equipamento(str(card.get("uid", "")), equip_index)
	_render_game()

# ---------------------------------------------------------------- turno

func _on_pass() -> void:
	if not is_my_turn():
		return
	_clear_targeting()
	await _run_action(func(): return engine.pass_turn("player"))

# ---------------------------------------------------------------- combate

func _wait(seconds: float) -> void:
	if animation_speed <= 0.0:
		return
	await get_tree().create_timer(seconds / animation_speed).timeout

# Toda a jogada passa por aqui. O motor resolve tudo de uma vez e deixa a
# lista de passos em combat_steps; nós só a voltamos a contar em imagens.
# Não se pode redesenhar o tabuleiro antes de a animação acabar, senão as
# cartas que morreram desaparecem antes de se ver o golpe.
func _run_action(action: Callable) -> void:
	_busy = true
	_render_hud()

	var combates_antes: int = engine.combat_counter
	action.call()

	if engine.combat_counter != combates_antes and not engine.combat_steps.is_empty():
		await _animate_combat(engine.combat_steps)

	_render_game()
	_busy = false
	_check_game_over()
	if engine.winner == "":
		await _maybe_advance_ai()

func _animate_combat(steps: Array) -> void:
	for step in steps:
		var tipo := str(step.get("type", ""))
		if tipo == "attack":
			await _animate_attack(step)
		else:
			await _animate_siege(step)

func _animate_attack(step: Dictionary) -> void:
	var atacante := _find_card_view(str(step.get("attacker", "")))
	var alvo := _find_card_view(str(step.get("target", "")))
	if atacante == null or alvo == null:
		return

	var centro_alvo := alvo.global_position + alvo.size * 0.5
	fx_layer.attack_trail(atacante.global_position + atacante.size * 0.5, centro_alvo)
	await _lunge(atacante, centro_alvo)

	fx_layer.float_number(alvo.global_position + Vector2(alvo.size.x * 0.5, alvo.size.y * 0.25),
		"-%d" % int(step.get("amount", 0)), "dano")
	_shake(alvo)
	await _wait(T_HIT)

	# Se o motor já a tirou do tabuleiro, mostra-a a morrer antes de sumir
	if engine.get_card(str(step.get("target", ""))) == null:
		fx_layer.skull_pop(centro_alvo)
		await _animate_death(alvo)

func _animate_siege(step: Dictionary) -> void:
	var atacante := _find_card_view(str(step.get("attacker", "")))
	var dono := str(step.get("towerOwner", ""))
	var barra: Control = board._tower_bars.get(dono)

	if atacante != null and barra != null:
		var centro_torre := barra.global_position + barra.size * 0.5
		fx_layer.attack_trail(atacante.global_position + atacante.size * 0.5, centro_torre)
		await _lunge(atacante, centro_torre)

	board.set_tower(dono, int(step.get("towerAfter", 0)))
	if barra != null:
		fx_layer.float_number(barra.global_position + barra.size * 0.5,
			"-%d" % int(step.get("amount", 0)), "dano")
		_flash(barra)
	await _wait(T_SIEGE)

# Sacudidela de quem leva o golpe (.slot.attack-target no web).
func _shake(vista: CardView) -> void:
	if animation_speed <= 0.0:
		return
	var origem := vista.position
	var tw := create_tween()
	for deslocamento in [6.0, -5.0, 3.0, 0.0]:
		tw.tween_property(vista, "position", origem + Vector2(deslocamento, 0), 0.08 / animation_speed)

# A carta avança 65% do caminho até ao alvo e volta, como no web.
func _lunge(vista: CardView, destino_global: Vector2) -> void:
	if animation_speed <= 0.0:
		return
	var origem := vista.position
	var centro := vista.global_position + vista.size * 0.5
	var desvio := (destino_global - centro) * 0.65

	vista.z_index = 90
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(vista, "position", origem + desvio, T_LUNGE * 0.45 / animation_speed)
	tw.parallel().tween_property(vista, "scale", Vector2(1.22, 1.22), T_LUNGE * 0.45 / animation_speed)
	tw.tween_property(vista, "position", origem, T_LUNGE * 0.55 / animation_speed)
	tw.parallel().tween_property(vista, "scale", Vector2.ONE, T_LUNGE * 0.55 / animation_speed)
	await tw.finished
	vista.z_index = 0

func _animate_death(vista: CardView) -> void:
	if animation_speed <= 0.0:
		return
	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN)
	tw.tween_property(vista, "modulate", Color(0.35, 0.35, 0.35, 0.0), T_DEATH / animation_speed)
	tw.parallel().tween_property(vista, "scale", Vector2(0.6, 0.6), T_DEATH / animation_speed)
	await tw.finished

func _flash(alvo: Control) -> void:
	if animation_speed <= 0.0:
		return
	var tw := create_tween()
	tw.tween_property(alvo, "modulate", Color(2.2, 1.6, 1.4, 1), 0.2 / animation_speed)
	tw.tween_property(alvo, "modulate", Color(1, 1, 1, 1), 0.3 / animation_speed)

# ---------------------------------------------------------------- fim de jogo

func _check_game_over() -> void:
	if engine.phase != "gameover" or _gameover_shown:
		return
	_gameover_shown = true

	var empate := engine.winner == "empate"
	var ganhou := engine.winner == "player"

	if empate:
		gameover_title.text = "Empate"
		gameover_subtitle.text = "Nenhuma Torre caiu antes do limite de turnos — venceu quem deixou a Torre do outro mais perto de cair."
	elif ganhou:
		gameover_title.text = "Vitória"
		gameover_subtitle.text = "Derrubaste a Torre do adversário."
	else:
		gameover_title.text = "Derrota"
		gameover_subtitle.text = "O adversário derrubou a tua Torre."

	gameover_overlay.visible = true

func _on_restart() -> void:
	gameover_overlay.visible = false
	Session.clear()
	get_tree().change_scene_to_file(MENU_SCENE)

# ---------------------------------------------------------------- adversário

# A IA joga uma acção de cada vez, para se ver o que ela fez em vez de o
# turno inteiro aparecer feito.
func _maybe_advance_ai() -> void:
	var guard := 0
	while engine.phase == "placement" and engine.active_player == "ai" and guard < 60:
		guard += 1
		_busy = true
		_render_hud()
		await _wait(T_AI_THINK)

		var combates_antes: int = engine.combat_counter
		if ai != null:
			ai.step(engine)
		else:
			engine.pass_turn("ai")

		if engine.combat_counter != combates_antes and not engine.combat_steps.is_empty():
			await _animate_combat(engine.combat_steps)

		_render_game()
		_busy = false
		_check_game_over()
		if engine.winner != "":
			return
	_render_game()

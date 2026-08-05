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

@onready var hand_container: HBoxContainer = $HandRow/Hand/HandContainer
@onready var hud_label: Label = $TopRow/HUD
@onready var music_button: Button = $TopRow/ButtonMusic
@onready var pass_button: Button = $HandRow/ButtonPass
@onready var board_area: AspectRatioContainer = $BoardArea
@onready var board: BoardRenderer = $BoardArea/Board

@onready var reinforcement_panel: PanelContainer = $ReinforcementPanel
@onready var reinforcement_slots: VBoxContainer = $ReinforcementPanel/Column/Slots
@onready var reinforcement_count: Label = $ReinforcementPanel/Column/Count
@onready var reinforcement_title: Label = $ReinforcementPanel/Column/Title

# Qual reforço está escolhido para entrar em campo (-1 = nenhum)
var _selected_reinforcement: int = -1

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
	Sfx.start_music()

# F11 alterna ecrã cheio, Esc devolve à janela — para não ficar preso.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var tecla := (event as InputEventKey).keycode
	if tecla == KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
	elif tecla == KEY_ESCAPE and _is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_viewport().set_input_as_handled()

func _is_fullscreen() -> bool:
	var modo := DisplayServer.window_get_mode()
	return modo == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or modo == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func _toggle_fullscreen() -> void:
	if _is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

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
	UITheme.apply_ember(music_button, true)
	music_button.pressed.connect(_on_toggle_music)
	_refresh_music_button()
	gameover_title.add_theme_color_override("font_color", Palette.EMBER_300)
	gameover_subtitle.add_theme_color_override("font_color", Palette.PARCHMENT_DIM)
	_style_reinforcement_panel()

func _style_reinforcement_panel() -> void:
	var moldura := StyleBoxFlat.new()
	moldura.bg_color = Color(Palette.STONE_900, 0.85)
	moldura.border_color = Palette.EMBER_400
	moldura.set_border_width_all(2)
	moldura.set_corner_radius_all(10)
	moldura.set_content_margin_all(10)
	reinforcement_panel.add_theme_stylebox_override("panel", moldura)

	reinforcement_title.text = "RESERVA MILITAR"
	reinforcement_title.add_theme_color_override("font_color", Palette.EMBER_300)
	reinforcement_count.add_theme_color_override("font_color", Palette.PARCHMENT)

func _on_toggle_music() -> void:
	Sfx.toggle_muted()
	_refresh_music_button()

func _refresh_music_button() -> void:
	music_button.text = "Sem som" if Sfx.is_muted() else "Som"

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

# Há casa livre no tabuleiro para esta unidade?
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
	# Um Equipamento sem unidade amiga em campo não tem onde ir
	if str(card_def.get("tipo_tatico", "")) == "Equipamento":
		return not engine.allies("player").is_empty()
	return true

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
				# As pontas da retaguarda são os dois baralhos; quem trata
				# delas é _render_deck_zones.
				if BoardGeometry.is_deck_slot(slot_type, lane):
					continue
				_sync_slot(owner_id, slot_type, lane, arr[lane])

	_render_deck_zones()
	_render_graveyards()
	board.set_tower("player", int(engine.towers["player"]))
	board.set_tower("ai", int(engine.towers["ai"]))
	board.update_board_art(int(engine.towers["player"]), int(engine.towers["ai"]))
	_watch_tower_alert()

# Toca o aviso na primeira vez que a minha Torre entra em perigo — uma vez
# só, senão soava a cada render.
var _alerta_dado := false

func _watch_tower_alert() -> void:
	var limite := float(Game.TOWER_MAX) * BoardGeometry.RUINED_THRESHOLD
	var em_perigo := float(engine.towers["player"]) <= limite
	if em_perigo and not _alerta_dado:
		_alerta_dado = true
		Sfx.alerta()
	elif not em_perigo:
		_alerta_dado = false

# As pontas da retaguarda são os dois baralhos, como no TABULEIRO.pdf:
# o jogador tem o Apoio à esquerda e o Militar à direita, a IA ao contrário.
func _render_deck_zones() -> void:
	for owner_id in ["player", "ai"]:
		var p: Dictionary = engine.players[owner_id]
		board.set_deck_count(owner_id, "militar", (p["militaryDeck"] as Array).size())
		board.set_deck_count(owner_id, "apoio", (p["deck"] as Array).size())

# O cemitério mostra a última carta que saiu de campo e o total acumulado.
# Conta as unidades mortas e os Apoios e Táticas já gastos.
func _render_graveyards() -> void:
	for owner_id in ["player", "ai"]:
		var p: Dictionary = engine.players[owner_id]
		var total: int = (p["graveyard"] as Array).size() + (p["discard"] as Array).size()
		board.set_graveyard_count(owner_id, total)
		_sync_graveyard_card(owner_id, _last_card_out(p))

# A última carta a sair de campo: a unidade que morreu ou o Apoio que se
# resolveu, o que tiver acontecido mais recentemente.
func _last_card_out(p: Dictionary):
	var morta = p["lastDeadCard"]
	var apoio = p["lastApoio"]
	if morta != null:
		return morta
	return apoio

func _sync_graveyard_card(owner_id: String, card) -> void:
	var holder := board.graveyard_holder(owner_id)
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

	# A chave serve para não refazer a vista quando é a mesma carta
	var chave := str(card.get("uid", card.get("id", "")))
	if existente != null and str(existente.get_meta("grave_key", "")) == chave:
		return

	if existente != null:
		holder.remove_child(existente)
		existente.queue_free()

	var vista := CardView.new()
	vista.show_overlays = false
	vista.modulate = Color(0.75, 0.72, 0.68, 1)   # esbatida: já saiu de campo
	vista.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vista.set_meta("grave_key", chave)
	vista.card_clicked.connect(func(c): _open_zoom_readonly(c))
	holder.add_child(vista)
	vista.bind(engine, card)

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
	_render_hand()
	_render_reinforcements()

# A mão é uma só — Apoios e Táticas, com a arte inteira e sem stats por cima.
func _render_hand() -> void:
	for child in hand_container.get_children():
		hand_container.remove_child(child)
		child.queue_free()

	var mao: Array = engine.players["player"]["hand"]
	for i in range(mao.size()):
		hand_container.add_child(_make_hand_card(mao[i], i))

func _make_hand_card(card_def: Dictionary, index: int) -> Control:
	var altura := 158.0
	var largura := altura * (69.0 / 94.0)

	var vista := CardView.new()
	vista.show_overlays = false
	# As cartas sobrepõem-se; o realce ao passar o rato levanta a de baixo do
	# rato para se poder ler, como no Gwent.
	vista.hover_enabled = true
	vista.mouse_entered.connect(func(): Sfx.realce())
	vista.custom_minimum_size = Vector2(largura, altura)
	vista.modulate = Color(1, 1, 1, 1) if is_hand_card_playable(card_def) else Color(0.55, 0.55, 0.55, 1)
	vista.card_clicked.connect(func(_c): _on_hand_card_click(index))
	vista.bind(engine, card_def)
	return vista

# Reserva de reforços: MAX_REFORCOS casas, as vazias com marca ténue.
func _render_reinforcements() -> void:
	for child in reinforcement_slots.get_children():
		reinforcement_slots.remove_child(child)
		child.queue_free()

	var reserva: Array = engine.players["player"]["reinforcements"]
	for i in range(Game.MAX_REFORCOS):
		if i < reserva.size():
			reinforcement_slots.add_child(_make_reinforcement_card(reserva[i], i))
		else:
			reinforcement_slots.add_child(_make_empty_reinforcement_slot())

	var cheia := engine.reinforcements_full("player")
	reinforcement_count.text = "%d / %d" % [reserva.size(), Game.MAX_REFORCOS]
	# Reserva cheia avisa que o reforço do próximo turno se perde
	reinforcement_count.add_theme_color_override("font_color",
		Palette.EMBER_400 if cheia else Palette.PARCHMENT_DIM)

func _make_reinforcement_card(card_def: Dictionary, index: int) -> Control:
	var vista := CardView.new()
	vista.show_overlays = false
	vista.custom_minimum_size = Vector2(0, 104)
	vista.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var escolhido := index == _selected_reinforcement
	if escolhido:
		vista.modulate = Color(1.3, 1.15, 0.95, 1)
	elif is_my_turn():
		vista.modulate = Color(1, 1, 1, 1)
	else:
		vista.modulate = Color(0.6, 0.6, 0.6, 1)

	vista.card_clicked.connect(func(_c): _on_reinforcement_click(index))
	vista.bind(engine, card_def)
	return vista

func _make_empty_reinforcement_slot() -> Control:
	var casa := Panel.new()
	casa.custom_minimum_size = Vector2(0, 104)
	casa.size_flags_vertical = Control.SIZE_EXPAND_FILL
	casa.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0, 0, 0, 0.25)
	estilo.border_color = Palette.STONE_600
	estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(6)
	casa.add_theme_stylebox_override("panel", estilo)
	return casa

func _render_hud() -> void:
	var turn_text := ""
	if engine.phase == "gameover":
		turn_text = "Fim de jogo — vencedor: %s" % engine.winner
	elif engine.phase == "combat":
		turn_text = "Combate..."
	elif engine.active_player == "player":
		if _selected_reinforcement >= 0:
			turn_text = "Clica numa casa livre do tabuleiro para colocar a unidade!"
		else:
			turn_text = "A tua vez: Seleciona um Reforço (painel da esquerda) ou joga um Apoio da Mão"
	else:
		turn_text = "Vez do adversário"

	var acoes: int = int(engine.tactical_actions.get("player", 0))
	hud_label.text = "CORREDOR — Turno %d/%d | %s\nTorres  tu %d/%d  ·  adv %d/%d   |   Reforços %d/%d   |   Ações Táticas %d/%d" % [
		engine.current_round, Game.ROUND_LIMIT, turn_text,
		engine.towers["player"], Game.TOWER_MAX,
		engine.towers["ai"], Game.TOWER_MAX,
		engine.reinforcement_count("player"), Game.MAX_REFORCOS,
		acoes, Game.TACTICAL_ACTIONS_PER_TURN
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
	zoom_card.custom_minimum_size = Vector2(altura * (69.0 / 94.0), altura)

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
	zoom_card.custom_minimum_size = Vector2(altura * (69.0 / 94.0), altura)
	zoom_actions.visible = false
	zoom_overlay.visible = true

func _close_zoom() -> void:
	zoom_overlay.visible = false

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_close_zoom()

# ---------------------------------------------------------------- mão

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
	Sfx.clique()
	_open_zoom(card_def, is_hand_card_playable(card_def), func(): _commit_hand_selection(idx, card_def))

func _commit_hand_selection(idx: int, card_def: Dictionary) -> void:
	_clear_targeting()

	# Apoio com alvo
	if card_def.get("isApoio", false):
		if engine.players["player"]["apoiosBlocked"]:
			return
		var def := engine.abilities.get_apoio_ability(str(card_def.get("id", "")))
		if def.is_empty():
			return
		if def.get("needsTarget") == null:
			_play_hand_card(idx, {})
			return
		_pending_apoio = {"hand_index": idx, "def": def, "card_def": card_def, "pair_from": null}
		_selected_hand_index = idx
		_begin_apoio_targeting()
		_render_hands()
		return

	# Equipamento precisa de uma unidade amiga
	if str(card_def.get("tipo_tatico", "")) == "Equipamento":
		_pending_tactico = {"index": idx, "card_def": card_def}
		_selected_hand_index = idx
		_show_target_bar("Escolhe uma unidade para equipar com %s" % card_def.get("nome", ""))
		for c in engine.allies("player"):
			_mark_card(c, true)
		_render_hands()
		return

	# As outras táticas resolvem-se logo
	_play_hand_card(idx, {})

# ---------------------------------------------------------------- reforços

func _on_reinforcement_click(idx: int) -> void:
	if _busy or engine.phase != "placement" or engine.active_player != "player":
		return
	var reserva: Array = engine.players["player"]["reinforcements"]
	if idx < 0 or idx >= reserva.size():
		return

	# Clicar outra vez no mesmo reforço desiste
	if _selected_reinforcement == idx:
		_clear_targeting()
		return

	var card_def: Dictionary = reserva[idx]
	Sfx.clique()
	_open_zoom(card_def, true, func(): _commit_reinforcement_selection(idx, card_def))

func _commit_reinforcement_selection(idx: int, card_def: Dictionary) -> void:
	_clear_targeting()
	_selected_reinforcement = idx
	_highlight_valid_slots(card_def)
	_render_hands()

func _highlight_valid_slots(card_def: Dictionary) -> void:
	for i in range(Game.FRONT_LANES):
		if engine.can_place_unit("player", card_def, "frente", i):
			board.highlight_slot("player", "frente", i, true)
	for i in Game.BACK_LANES:
		if engine.can_place_unit("player", card_def, "retaguarda", i):
			board.highlight_slot("player", "retaguarda", i, true)

func _on_slot_clicked(owner_id: String, slot_type: String, lane: int) -> void:
	if _busy or _selected_reinforcement < 0 or is_targeting():
		return
	if owner_id != "player":
		return

	var reserva: Array = engine.players["player"]["reinforcements"]
	if _selected_reinforcement >= reserva.size():
		return
	var card_def: Dictionary = reserva[_selected_reinforcement]
	if not engine.can_place_unit("player", card_def, slot_type, lane):
		return

	var idx := _selected_reinforcement
	# Capturar antes de limpar, senão a carta já não está lá para copiar
	var viagem := _travel_rects(idx, owner_id, slot_type, lane)
	_clear_targeting()
	await _fly_card(card_def, viagem)
	Sfx.unidade()
	await _run_action(func(): return engine.place_reinforcement("player", idx, slot_type, lane))

# De onde para onde a carta voa: da casa da reserva até à casa do tabuleiro.
func _travel_rects(reinforcement_index: int, owner_id: String, slot_type: String, lane: int) -> Dictionary:
	if reinforcement_index < 0 or reinforcement_index >= reinforcement_slots.get_child_count():
		return {}
	var origem: Control = reinforcement_slots.get_child(reinforcement_index)
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

# Uma carta da mão sai sempre por aqui, seja Apoio ou Tática.
func _play_hand_card(idx: int, spec: Dictionary) -> void:
	var mao: Array = engine.players["player"]["hand"]
	var card_def: Dictionary = mao[idx] if idx < mao.size() else {}
	var apoio: bool = card_def.get("isApoio", false)
	_clear_targeting()

	if apoio:
		Sfx.apoio()
	else:
		Sfx.carta()
	await _run_action(func(): return engine.play_hand_card("player", idx, spec))

# Mantido pelo nome antigo — o Apoio é só mais uma carta da mão.
func _play_apoio(idx: int, spec: Dictionary) -> void:
	await _play_hand_card(idx, spec)

func _confirm_tactico_target(target_card: Dictionary) -> void:
	var idx: int = int(_pending_tactico["index"])
	Sfx.equipar()
	await _play_hand_card(idx, {"targetCard": target_card})

# ---------------------------------------------------------------- alvos

func _show_target_bar(texto: String) -> void:
	target_prompt.text = texto
	target_bar.visible = true

func _clear_targeting() -> void:
	_pending_apoio = {}
	_pending_tactico = {}
	_selected_hand_index = -1
	_selected_reinforcement = -1
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
	Sfx.clique()
	_render_game()

# ---------------------------------------------------------------- turno

func _on_pass() -> void:
	if not is_my_turn():
		return
	_clear_targeting()
	Sfx.passar()
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
	var turno_antes: int = engine.current_round
	action.call()

	if engine.combat_counter != combates_antes and not engine.combat_steps.is_empty():
		await _animate_combat(engine.combat_steps)

	# Sino a marcar a passagem de turno, e o reforço que o Baralho Militar
	# largou a seguir ao combate
	if engine.current_round != turno_antes:
		Sfx.turno()
		if engine.reinforcement_count("player") > 0:
			Sfx.reforco()

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
	Sfx.golpe()
	await _lunge(atacante, centro_alvo)

	fx_layer.float_number(alvo.global_position + Vector2(alvo.size.x * 0.5, alvo.size.y * 0.25),
		"-%d" % int(step.get("amount", 0)), "dano")
	_shake(alvo)
	Sfx.impacto()
	await _wait(T_HIT)

	# Se o motor já a tirou do tabuleiro, mostra-a a morrer antes de sumir
	if engine.get_card(str(step.get("target", ""))) == null:
		fx_layer.skull_pop(centro_alvo)
		Sfx.morte()
		await _animate_death(alvo)

func _animate_siege(step: Dictionary) -> void:
	var atacante := _find_card_view(str(step.get("attacker", "")))
	var dono := str(step.get("towerOwner", ""))
	var barra: Control = board._tower_bars.get(dono)

	if atacante != null and barra != null:
		var centro_torre := barra.global_position + barra.size * 0.5
		fx_layer.attack_trail(atacante.global_position + atacante.size * 0.5, centro_torre)
		Sfx.golpe()
		await _lunge(atacante, centro_torre)

	board.set_tower(dono, int(step.get("towerAfter", 0)))
	if str(step.get("type", "")) == "rupture":
		Sfx.ruptura()
	else:
		Sfx.cerco()
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

	if empate:
		pass   # o web também não tem som próprio para empate
	elif ganhou:
		Sfx.vitoria()
	else:
		Sfx.derrota()

	gameover_overlay.visible = true

func _on_restart() -> void:
	Sfx.clique()
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

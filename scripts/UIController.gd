extends Control

var engine: GameEngine
var cartas: Dictionary = {}
var player_faction: String = ""
var ai_faction: String = ""

func _ready():
	engine = $".."  # GameEngine node
	_load_cards()
	_setup_ui()
	_start_game()

func _load_cards():
	var json_str = FileAccess.get_file_as_string("res://resources/cartas.json")
	cartas = JSON.parse_string(json_str)
	print("Carregadas: %d unidades, %d apoios, %d táticos" % [
		cartas.get("unidades", []).size(),
		cartas.get("apoios", []).size(),
		cartas.get("taticos", []).size()
	])

func _setup_ui():
	# Mostrar menu de seleção de facção
	_show_faction_menu()

func _show_faction_menu():
	var factions = {}
	for unit in cartas.get("unidades", []):
		var faccao = unit.get("faccao_slug", "")
		if faccao and not faccao in factions:
			factions[faccao] = unit.get("faccao", "")

	print("Facções disponíveis: ", factions)
	# Por enquanto, seleciona aleatoriamente
	var faction_keys = factions.keys()
	player_faction = faction_keys[randi() % faction_keys.size()]
	ai_faction = faction_keys[randi() % faction_keys.size()]

func _start_game():
	print("Jogador: %s vs IA: %s" % [player_faction, ai_faction])

	var player_deck = _build_faction_deck(player_faction)
	var ai_deck = _build_faction_deck(ai_faction)

	engine.init_game(player_deck, ai_deck)
	_render_game()

func _build_faction_deck(faction_slug: String) -> Array:
	var apoios = cartas.get("apoios", [])
	var unidades = cartas.get("unidades", [])
	var taticos = cartas.get("taticos", [])

	var faction_apoios = apoios.filter(func(c): return c.get("faccao_slug") == faction_slug)
	var faction_unidades = unidades.filter(func(c): return c.get("faccao_slug") == faction_slug)
	var faction_taticos = taticos.filter(func(c): return c.get("faccao_slug") == faction_slug)

	# Montar deck: apoios + unidades + táticos
	var deck: Array = []
	deck.append_array(faction_apoios)

	var remaining = maxi(0, 20 - faction_apoios.size())
	faction_unidades.sort_custom(func(a, b): return a.get("custo", 0) < b.get("custo", 0))
	deck.append_array(faction_unidades.slice(0, remaining))

	deck.append_array(faction_taticos)

	return deck

func _render_game():
	_render_tatico_hand()
	_render_hand()
	_update_hud()

func _render_tatico_hand():
	var container = $"../TacticoHand/CardContainer"
	# Limpar
	for child in container.get_children():
		child.queue_free()

	var p = engine.players["player"]
	for card in p.get("tacticoHand", []):
		var card_ui = _create_card_ui(card)
		container.add_child(card_ui)

func _render_hand():
	var container = $"../Hand"
	# Limpar
	for child in container.get_children():
		child.queue_free()

	var p = engine.players["player"]
	for card in p.get("hand", []):
		var card_ui = _create_card_ui(card)
		container.add_child(card_ui)

func _create_card_ui(card: Dictionary) -> Control:
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(100, 140)

	# Imagem
	var img = TextureRect.new()
	var card_name = card.get("imagem", "")
	if card_name:
		var tipo = card.get("tipo_tatico", "")
		var path = "res://assets/taticos-3d/%s" % card_name if tipo else "res://assets/cartas-3d/%s" % card_name
		img.texture = load(path)
		img.expand_mode = TextureRect.EXPAND_FIT_WIDTH_IGNORED
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT

	vbox.add_child(img)

	# Nome
	var label = Label.new()
	label.text = card.get("nome", "?")
	label.custom_minimum_size = Vector2(100, 40)
	vbox.add_child(label)

	return vbox

func _update_hud():
	$"../HUD/RoundLabel".text = "Turno %d / %d" % [engine.round, engine.ROUND_LIMIT]
	$"../HUD/TurnIndicator".text = "A tua vez" if engine.activePlayer == "player" else "Vez do adversário"

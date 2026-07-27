extends Node
class_name GameEngine

const TOWER_MAX = 30
const ROUND_LIMIT = 12
const FRONT_LANES = 6
const BACK_LANES = [1, 2, 3, 4]
const BASE_UNIT_CAP = 3

var towers: Dictionary = {"player": TOWER_MAX, "ai": TOWER_MAX}
var round: int = 1
var phase: String = "placement"  # placement | combat | gameover
var activePlayer: String = "player"
var winner: String = ""
var log_lines: Array = []

var players: Dictionary = {}
var all_cards_data: Dictionary = {}

func _ready():
	# Carregar dados das cartas
	var cartas_json = JSON.parse_string(FileAccess.get_file_as_string("res://resources/cartas.json"))
	all_cards_data = cartas_json

func _log(msg: String):
	log_lines.append(msg)
	print(msg)

func init_game(player_deck: Array, ai_deck: Array):
	players = {
		"player": _make_player_state(player_deck, _filter_taticos(player_deck)),
		"ai": _make_player_state(ai_deck, _filter_taticos(ai_deck))
	}
	_draw_initial_hand("player")
	_draw_initial_hand("ai")
	_log("Jogo iniciado!")

func _filter_taticos(deck: Array) -> Array:
	var taticos = []
	for card in deck:
		if card.has("tipo_tatico"):
			taticos.append(card)
	return taticos

func _make_player_state(military_deck: Array, tatico_deck: Array) -> Dictionary:
	return {
		"deck": military_deck.duplicate(),
		"hand": [],
		"graveyard": [],
		"tacticoDeck": tatico_deck.duplicate(),
		"tacticoHand": [],
		"tacticoGraveyard": [],
		"front": [null, null, null, null, null, null],
		"back": [null, null, null, null, null, null],
		"activeTactics": [],
		"unitPlaysThisRound": 0,
		"donePlacing": false
	}

func _draw_initial_hand(owner_id: String):
	var p = players[owner_id]

	# Desenhar 5 cartas táticas
	for i in range(5):
		if p["tacticoDeck"].size() > 0:
			p["tacticoHand"].append(p["tacticoDeck"].pop_front())

func play_unit(owner_id: String, hand_index: int, slot_type: String, slot_index: int) -> Dictionary:
	if phase != "placement" or activePlayer != owner_id:
		return {"ok": false, "error": "não é a tua vez"}

	var p = players[owner_id]
	if hand_index >= p["hand"].size():
		return {"ok": false, "error": "carta inválida"}

	var card_def = p["hand"][hand_index]
	p["hand"].remove_at(hand_index)

	var card = _instantiate(card_def, owner_id)
	var slot_array = p["front"] if slot_type == "frente" else p["back"]
	slot_array[slot_index] = card

	p["unitPlaysThisRound"] += 1
	_log("%s colocou %s" % [owner_id, card_def["nome"]])

	_advance_priority(owner_id)
	return {"ok": true, "card": card}

func play_tatico_card(owner_id: String, tatico_hand_index: int, target_spec: Dictionary = {}) -> Dictionary:
	if phase != "placement" or activePlayer != owner_id:
		return {"ok": false, "error": "não é a tua vez"}

	var p = players[owner_id]
	if tatico_hand_index >= p["tacticoHand"].size():
		return {"ok": false, "error": "carta tática inválida"}

	var card_def = p["tacticoHand"][tatico_hand_index]
	var tipo = card_def.get("tipo_tatico", "")

	# Equipamento requer alvo
	if tipo == "Equipamento":
		if not target_spec.has("targetCard"):
			return {"ok": false, "error": "escolhe uma unidade", "needsTarget": "card"}

		var target_card = target_spec["targetCard"]
		p["tacticoHand"].remove_at(tatico_hand_index)
		target_card["equipamentos"].append(card_def)

		if card_def.has("bonus_ataque"):
			target_card["permBuffAtk"] += card_def["bonus_ataque"]
		if card_def.has("bonus_vida"):
			target_card["vidaMaxima"] += card_def["bonus_vida"]
			target_card["vidaAtual"] += card_def["bonus_vida"]

		_log("%s equipou %s em %s" % [owner_id, card_def["nome"], target_card["nome"]])

		# Recarregar baralho
		if p["tacticoDeck"].size() > 0:
			p["tacticoHand"].append(p["tacticoDeck"].pop_front())

		return {"ok": true, "card": card_def, "target": target_card}

	# Outras cartas táticas
	p["tacticoHand"].remove_at(tatico_hand_index)

	match tipo:
		"Magia":
			if card_def.has("dano"):
				var targets = get_allies(owner_id, true)
				if targets.size() > 0:
					targets[0]["vidaAtual"] -= card_def["dano"]
					_log("%s lançou %s (%d dano)" % [owner_id, card_def["nome"], card_def["dano"]])

		"Consumível":
			if card_def.has("cura"):
				var allies = get_allies(owner_id)
				if allies.size() > 0:
					var old_hp = allies[0]["vidaAtual"]
					allies[0]["vidaAtual"] = min(allies[0]["vidaMaxima"], allies[0]["vidaAtual"] + card_def["cura"])
					var healed = allies[0]["vidaAtual"] - old_hp
					_log("%s usou %s (+%d HP)" % [owner_id, card_def["nome"], healed])
			p["tacticoGraveyard"].append(card_def)

		"Construção":
			var construct = card_def.duplicate()
			construct["vidaAtual"] = card_def.get("vida_construcao", 8)
			construct["vidaMaxima"] = card_def.get("vida_construcao", 8)
			construct["ownerId"] = owner_id
			p["activeTactics"].append(construct)
			_log("%s colocou %s" % [owner_id, card_def["nome"]])

		"Clima":
			_log("%s ativou %s" % [owner_id, card_def["nome"]])

		"Bênção":
			var allies = get_allies(owner_id)
			if allies.size() > 0:
				allies[0]["tempBuffAtk"] = allies[0].get("tempBuffAtk", 0) + 2
				_log("%s invocou %s (+2 ATK)" % [owner_id, card_def["nome"]])

	# Recarregar baralho
	if p["tacticoDeck"].size() > 0:
		p["tacticoHand"].append(p["tacticoDeck"].pop_front())

	return {"ok": true, "card": card_def}

func get_allies(owner_id: String, enemies: bool = false) -> Array:
	var target_id = owner_id if not enemies else ("ai" if owner_id == "player" else "player")
	var p = players[target_id]
	var result = []

	for card in p["front"]:
		if card != null:
			result.append(card)
	for card in p["back"]:
		if card != null:
			result.append(card)

	return result

func _instantiate(card_def: Dictionary, owner_id: String) -> Dictionary:
	return {
		"cardId": card_def.get("id", ""),
		"nome": card_def.get("nome", ""),
		"imagem": card_def.get("imagem", ""),
		"baseAtaque": card_def.get("ataque", 0),
		"baseVida": card_def.get("vida", 0),
		"vidaMaxima": card_def.get("vida", 0),
		"vidaAtual": card_def.get("vida", 0),
		"escudoAtual": card_def.get("escudo", 0),
		"permBuffAtk": 0,
		"tempBuffAtk": 0,
		"pressaoMarcas": 0,
		"equipamentos": [],
		"ownerId": owner_id
	}

func _advance_priority(owner_id: String):
	activePlayer = "ai" if owner_id == "player" else "player"

func pass_turn(owner_id: String) -> Dictionary:
	if phase != "placement" or activePlayer != owner_id:
		return {"ok": false}

	players[owner_id]["donePlacing"] = true
	_log("%s passou" % owner_id)

	# Verificar se ambos passaram
	if players["player"].get("donePlacing", false) and players["ai"].get("donePlacing", false):
		phase = "gameover"  # Simplificado por agora

	return {"ok": true}

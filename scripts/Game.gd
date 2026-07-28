extends Node
class_name Game

# Motor de jogo — CORREDOR (traduzido de game-engine.js)
# Regras: 6 frente + 6 retaguarda, 30 HP torres, 12 rounds max, 3 unidades/turno

const FRONT_ROLES = {"TANQUE", "GUERREIRO"}
const BACK_ROLES = {"ASSASSINO", "CURADOR", "ATIRADOR"}
const FRONT_LANES = 6
const BACK_LANES = [1, 2, 3, 4]
const BASE_UNIT_CAP = 3
const TOWER_MAX = 30
const ROUND_LIMIT = 12

const FAMILY_A = {"ORDEM", "PUREZA"}
const FAMILY_B = {"SELVA", "MAGIA"}

const STRONG_AGAINST = {
	"FOGO": ["PLANTAS", "METAL"],
	"ÁGUA": ["FOGO", "TERRA"],
	"PLANTAS": ["ÁGUA", "TERRA"],
	"VENTO": ["PLANTAS", "BESTA"],
	"TERRA": ["METAL", "FOGO"],
	"ANJO": ["DEMONIO", "SOMBRA"],
	"DEMONIO": ["ANCESTRAL", "NORMAL"],
	"ANCESTRAL": ["ANJO", "DEMONIO"],
	"FADA": ["METAL", "TERRA"],
	"LUZ": ["SOMBRA", "DEMONIO"],
	"SOMBRA": ["LUZ", "ANJO"],
	"METAL": ["FADA", "PLANTAS"],
	"BESTA": ["PLANTAS", "NORMAL"],
	"NORMAL": []
}

const WEAK_TO = {
	"FOGO": ["ÁGUA", "TERRA"],
	"ÁGUA": ["PLANTAS", "VENTO"],
	"PLANTAS": ["FOGO", "VENTO"],
	"VENTO": ["ÁGUA", "TERRA"],
	"TERRA": ["ÁGUA", "PLANTAS"],
	"ANJO": ["DEMONIO"],
	"DEMONIO": ["ANJO", "LUZ"],
	"ANCESTRAL": ["FOGO"],
	"FADA": ["METAL"],
	"LUZ": ["SOMBRA"],
	"SOMBRA": ["LUZ"],
	"METAL": ["FOGO", "TERRA", "VENTO"],
	"BESTA": ["VENTO", "ANJO"],
	"NORMAL": []
}

# Estado global do jogo
var towers: Dictionary = {"player": TOWER_MAX, "ai": TOWER_MAX}
var round: int = 1
var phase: String = "placement" # placement | combat | gameover
var activePlayer: String = "player"
var winner: String = ""
var combatSteps: Array = []
var players: Dictionary = {}

var _uid_counter: int = 1
var _log_callback: Callable = Callable()
var _ability_dispatcher: AbilityDispatcher = null

func _next_uid() -> String:
	var uid = "c" + str(_uid_counter)
	_uid_counter += 1
	return uid

func _shuffle(arr: Array) -> Array:
	var a = arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = a[i]
		a[i] = a[j]
		a[j] = temp
	return a

# ========== INICIALIZAÇÃO ==========

func init_game(player_deck: Array, ai_deck: Array, log_callback: Callable = Callable()) -> void:
	_log_callback = log_callback
	if !_ability_dispatcher:
		_ability_dispatcher = AbilityDispatcher.new()

	# Separar decks militares e táticos
	var player_mil = player_deck.filter(func(c): return !c.has("tipo_tatico") or c["tipo_tatico"] == "")
	var player_tac = player_deck.filter(func(c): return c.has("tipo_tatico") and c["tipo_tatico"] != "")
	var ai_mil = ai_deck.filter(func(c): return !c.has("tipo_tatico") or c["tipo_tatico"] == "")
	var ai_tac = ai_deck.filter(func(c): return c.has("tipo_tatico") and c["tipo_tatico"] != "")

	players = {
		"player": _make_player_state(player_mil, player_tac),
		"ai": _make_player_state(ai_mil, ai_tac)
	}

	players["player"]["hasSombra"] = player_mil.any(func(c): return c.get("alinhamento") == "SOMBRA")
	players["ai"]["hasSombra"] = ai_mil.any(func(c): return c.get("alinhamento") == "SOMBRA")

	players["player"]["cohesionBroken"] = _compute_cohesion_broken(player_mil)
	players["ai"]["cohesionBroken"] = _compute_cohesion_broken(ai_mil)

	_draw_initial_hand("player")
	_draw_initial_hand("ai")
	_run_turn_start_triggers()

func _compute_cohesion_broken(deck: Array) -> bool:
	var hasA = false
	var hasB = false
	for c in deck:
		var align = c.get("alinhamento", "")
		if align in FAMILY_A:
			hasA = true
		if align in FAMILY_B:
			hasB = true
	return hasA and hasB

func _make_player_state(military_deck: Array, tatico_deck: Array) -> Dictionary:
	return {
		# Baralho militar
		"deck": _shuffle(military_deck),
		"hand": [],
		"graveyard": [],

		# Baralho tático
		"tacticoDeck": _shuffle(tatico_deck),
		"tacticoHand": [],
		"tacticoGraveyard": [],

		# Tabuleiro
		"front": [null, null, null, null, null, null],
		"back": [null, null, null, null, null, null],

		# Cartas táticas ativas
		"activeTactics": [],

		# Estado do turno
		"unitPlaysThisRound": 0,
		"extraUnitCap": 0,
		"freeNextUnit": false,
		"apoioDoubleNext": false,
		"apoiosBlocked": false,
		"apoiosBlockedNextRound": false,
		"donePlacing": false,
		"lastDeadCard": null,
		"flags": {},

		# Propriedades adicionadas depois
		"hasSombra": false,
		"cohesionBroken": false
	}

# ========== UTILITÁRIOS ==========

func opponent_of(owner_id: String) -> String:
	return "ai" if owner_id == "player" else "player"

func all_in_play() -> Array:
	var all = []
	all.append_array(allies("player"))
	all.append_array(allies("ai"))
	return all

func allies(owner_id: String) -> Array:
	var p = players[owner_id]
	var cards = []
	cards.append_array(p["front"].filter(func(c): return c != null))
	cards.append_array(p["back"].filter(func(c): return c != null))
	return cards

func enemies(owner_id: String) -> Array:
	return allies(opponent_of(owner_id))

func get_card(uid: String):
	for card in all_in_play():
		if card["uid"] == uid:
			return card
	return null

func lane_enemies_of(card) -> Array:
	return enemies(card["ownerId"]).filter(func(e): return _same_lane(card, e))

func _same_lane(a, b) -> bool:
	return a["slotIndex"] == b["slotIndex"]

func _targetable(card, by_enemy: bool = false) -> bool:
	if card == null:
		return false
	if card.get("cannotBeTargeted", false) and round <= card.get("cannotBeTargetedUntilRound", 0):
		return false
	if by_enemy and card.get("cannotBeTargetedByEnemies", false):
		return false
	return true

func pick_highest_ataque_enemy(owner_id: String):
	var list = enemies(owner_id).filter(func(c): return _targetable(c, true))
	if list.is_empty():
		return null
	return list.reduce(func(a, b): return get_effective_ataque(b) > get_effective_ataque(a) ? b : a)

func pick_lowest_vida_enemy(owner_id: String):
	var list = enemies(owner_id).filter(func(c): return _targetable(c, true))
	if list.is_empty():
		return null
	return list.reduce(func(a, b): return b["vidaAtual"] < a["vidaAtual"] ? b : a)

func pick_lowest_vida_enemy_for_combat(owner_id: String):
	var list = enemies(owner_id)
	if list.is_empty():
		return null
	return list.reduce(func(a, b): return b["vidaAtual"] < a["vidaAtual"] ? b : a)

func pick_most_wounded_ally(owner_id: String):
	var list = allies(owner_id).filter(func(c): return _targetable(c))
	var wounded = list.filter(func(c): return c["vidaAtual"] < c["vidaMaxima"])
	if !wounded.is_empty():
		return wounded.reduce(func(a, b): return b["vidaAtual"] < a["vidaAtual"] ? b : a)
	return list[0] if !list.is_empty() else null

func pick_nearest_ally(card):
	var list = allies(card["ownerId"]).filter(func(c): return c["uid"] != card["uid"])
	if list.is_empty():
		return null
	return list.reduce(func(a, b): return abs(b["slotIndex"] - card["slotIndex"]) < abs(a["slotIndex"] - card["slotIndex"]) ? b : a)

func get_graveyard_count(owner_id: String) -> int:
	return players[owner_id]["graveyard"].size()

func set_flag(owner_id: String, key: String, value) -> void:
	players[owner_id]["flags"][key] = value

func get_flag(owner_id: String, key: String):
	return players[owner_id]["flags"].get(key)

# ========== STATS & BONUSES ==========

func get_effective_ataque(card) -> int:
	var v = card["baseAtaque"] + card["permBuffAtk"] + card["staticBonusAtk"] + card["tempBuffAtk"]
	return max(0, v)

func get_vida_maxima(card) -> int:
	return max(1, card["baseVida"] + card["permBuffVida"] + card["staticBonusVida"] - card["permVidaMaxLoss"])

func recompute_statics() -> void:
	all_in_play().forEach(func(c):
		c["staticBonusAtk"] = 0
		c["staticBonusVida"] = 0
	)
	# TODO: Run ability triggers for 'static'
	all_in_play().forEach(func(c):
		c["vidaMaxima"] = get_vida_maxima(c)
		if c["vidaAtual"] > c["vidaMaxima"]:
			c["vidaAtual"] = c["vidaMaxima"]
	)

func has_alignment_bonus(card) -> bool:
	if card.get("noAlignmentBonus", false):
		return false
	if players[card["ownerId"]]["cohesionBroken"]:
		return false
	var blocked = get_flag(opponent_of(card["ownerId"]), "alignmentBlockedTipos")
	if blocked and card.get("tipo", []).any(func(t): return blocked.has(t)):
		return false
	return true

func get_alignment_atk_bonus(card) -> int:
	if !has_alignment_bonus(card):
		return 0
	if card.get("alinhamento") == "ORDEM" and card.get("custo", 0) >= 3:
		return 1
	return 0

func get_matchup_multiplier(attacker, defender) -> float:
	var mult = 1.0
	var is_weak = defender.get("tipo", []).any(func(dt):
		return attacker.get("tipo", []).any(func(at):
			return (WEAK_TO.get(dt, []) as Array).has(at)
		)
	)
	var is_resisted = defender.get("tipo", []).any(func(dt):
		return (STRONG_AGAINST.get(dt, []) as Array).any(func(s):
			return (attacker.get("tipo", []) as Array).has(s)
		)
	)
	if is_weak:
		mult += 0.4
	if is_resisted:
		mult -= 0.4
	return mult

func _log(msg: String) -> void:
	if _log_callback.is_valid():
		_log_callback.call(msg)
	else:
		print(msg)

# ========== DRAW & HAND ==========

func _draw_card(owner_id: String, n: int) -> void:
	var p = players[owner_id]
	for i in range(n):
		if p["deck"].is_empty() or p["hand"].size() >= 10:
			break
		p["hand"].append(p["deck"].pop_front())

func draw_card(owner_id: String, n: int) -> void:
	_draw_card(owner_id, n)

func _draw_initial_hand(owner_id: String) -> void:
	var p = players[owner_id]
	var front_indices = []
	for i in range(p["deck"].size()):
		if front_indices.size() >= 4:
			break
		if FRONT_ROLES.has(p["deck"][i].get("papel", "")):
			front_indices.append(i)

	var back_indices = []
	for i in range(p["deck"].size()):
		if back_indices.size() >= 2:
			break
		if !front_indices.has(i) and BACK_ROLES.has(p["deck"][i].get("papel", "")):
			back_indices.append(i)

	var selected_indices = front_indices + back_indices
	var selected_cards = []
	var remaining_deck = []
	for idx in range(p["deck"].size()):
		if selected_indices.has(idx):
			selected_cards.append(p["deck"][idx])
		else:
			remaining_deck.append(p["deck"][idx])

	p["hand"].append_array(selected_cards)
	p["deck"] = remaining_deck

	if p["hand"].size() < 6:
		_draw_card(owner_id, 6 - p["hand"].size())

	# Draw 5 tactical cards initially
	for i in range(5):
		if p["tacticoDeck"].is_empty():
			break
		p["tacticoHand"].append(p["tacticoDeck"].pop_front())

func grant_extra_unit_cap(owner_id: String, n: int) -> void:
	players[owner_id]["extraUnitCap"] += n

func grant_free_next_unit(owner_id: String) -> void:
	players[owner_id]["freeNextUnit"] = true

func get_unit_cap(owner_id: String) -> int:
	var base_cap = 6 if round == 1 else BASE_UNIT_CAP
	return base_cap + players[owner_id]["extraUnitCap"]

func heal_tower(owner_id: String, amount: int) -> void:
	towers[owner_id] = min(TOWER_MAX, towers[owner_id] + amount)
	_log("Torre de %s recupera %d. (%d/%d)" % [owner_id, amount, towers[owner_id], TOWER_MAX])

func damage_tower(target_owner_id: String, amount: int) -> void:
	towers[target_owner_id] = max(0, towers[target_owner_id] - amount)
	_log("Torre de %s leva %d de dano. (%d/%d)" % [target_owner_id, amount, towers[target_owner_id], TOWER_MAX])
	_check_win()

func add_pressure_mark(card, delta: int) -> void:
	card["pressaoMarcas"] = max(0, card["pressaoMarcas"] + delta)

func add_atk_mod(card, delta: int) -> void:
	card["tempBuffAtk"] += delta

func perm_buff(card, atk: int, vida: int) -> void:
	card["permBuffAtk"] += atk
	card["permBuffVida"] += vida
	card["vidaAtual"] += vida

func reduce_vida_maxima(card, n: int) -> void:
	card["permVidaMaxLoss"] += n
	card["vidaMaxima"] = get_vida_maxima(card)
	if card["vidaAtual"] > card["vidaMaxima"]:
		card["vidaAtual"] = card["vidaMaxima"]

func add_shield(card, n: int) -> void:
	card["escudoAtual"] += n

func heal(card, n: int) -> void:
	if !card or card["vidaAtual"] <= 0 or card.get("cannotBeHealed", false):
		return
	card["vidaAtual"] = min(card["vidaMaxima"], card["vidaAtual"] + n)
	_emit_ally_healed(card)

func clear_negative_effects(card) -> void:
	card["tempBuffAtk"] = max(0, card["tempBuffAtk"])
	card["pressureLocked"] = 0
	card["_laneDebuffTemp"] = 0

func move_card(card, slot_type: String, slot_index: int) -> void:
	var p = players[card["ownerId"]]
	var from_arr = p["back"] if card["slotType"] == "retaguarda" else p["front"]
	from_arr[card["slotIndex"]] = null
	var to_arr = p["back"] if slot_type == "retaguarda" else p["front"]
	if to_arr[slot_index]:
		return # ocupado
	card["slotType"] = slot_type
	card["slotIndex"] = slot_index
	to_arr[slot_index] = card

func set_apoio_double(owner_id: String) -> void:
	players[owner_id]["apoioDoubleNext"] = true

func apoio_mult() -> int:
	return players[activePlayer].get("_currentApoioMult", 1)

func block_apoios(owner_id: String) -> void:
	players[owner_id]["apoiosBlockedNextRound"] = true

func force_rupture(card) -> void:
	card["forcedRupture"] = true

func return_last_dead_to_hand(owner_id: String) -> void:
	var p = players[owner_id]
	var last = p["lastDeadCard"]
	if last:
		p["hand"].append(last)
		p["lastDeadCard"] = null
		_log("%s volta à mão." % last["nome"])

# ========== INSTANTIATE CARD ==========

func _instantiate(card_def: Dictionary, owner_id: String) -> Dictionary:
	return {
		"uid": _next_uid(),
		"cardId": card_def.get("id", ""),
		"nome": card_def.get("nome", ""),
		"faccao": card_def.get("faccao", ""),
		"faccao_slug": card_def.get("faccao_slug", ""),
		"subgrupo": card_def.get("subgrupo", ""),
		"tipo": card_def.get("tipo", []),
		"papel": card_def.get("papel", ""),
		"alinhamento": card_def.get("alinhamento", ""),
		"raridade": card_def.get("raridade", ""),
		"custo": card_def.get("custo", 0),
		"imagem": card_def.get("imagem", ""),
		"habilidade_nome": card_def.get("habilidade_nome", ""),
		"habilidade_texto": card_def.get("habilidade_texto", ""),
		"lore": card_def.get("lore", ""),
		"baseAtaque": card_def.get("ataque", 0),
		"baseVida": card_def.get("vida", 1),
		"permBuffAtk": 0,
		"permBuffVida": 0,
		"permVidaMaxLoss": 0,
		"tempBuffAtk": 0,
		"tempDamageReduction": 0,
		"staticBonusAtk": 0,
		"staticBonusVida": 0,
		"escudoAtual": card_def.get("escudo", 0),
		"vidaMaxima": card_def.get("vida", 1),
		"vidaAtual": card_def.get("vida", 1),
		"pressaoMarcas": 0,
		"turnosEmCampo": 0,
		"enteredRound": round,
		"tookDamageThisRound": false,
		"attackedThisRound": false,
		"attackedLastRound": false,
		"cannotBeTargeted": false,
		"cannotBeTargetedByEnemies": false,
		"cannotBeTargetedUntilRound": 0,
		"cannotDieThisRound": false,
		"pressureLocked": 0,
		"forcedRupture": false,
		"cannotBeHealed": false,
		"noAlignmentBonus": false,
		"readyToAttack": false,
		"usedSecondLife": false,
		"ownerId": owner_id,
		"isApoio": false,
		"slotType": null,
		"slotIndex": null,
		"equipamentos": []
	}

# ========== PLAY UNIT ==========

func can_place_unit(owner_id: String, card_def: Dictionary, slot_type: String, slot_index: int) -> bool:
	var p = players[owner_id]
	var roles = FRONT_ROLES if slot_type == "frente" else BACK_ROLES
	if !roles.has(card_def.get("papel", "")):
		return false
	if slot_type == "retaguarda" and !BACK_LANES.has(slot_index):
		return false
	var arr = p["front"] if slot_type == "frente" else p["back"]
	if arr[slot_index]:
		return false
	if !p["freeNextUnit"] and p["unitPlaysThisRound"] >= get_unit_cap(owner_id):
		return false
	return true

func play_unit(owner_id: String, hand_index: int, slot_type: String, slot_index: int) -> Dictionary:
	if phase != "placement" or activePlayer != owner_id:
		return {"ok": false, "error": "não é a tua vez"}
	var p = players[owner_id]
	var card_def = p["hand"][hand_index] if hand_index < p["hand"].size() else null
	if !card_def or card_def.get("isApoio", false):
		return {"ok": false, "error": "carta inválida"}
	if !can_place_unit(owner_id, card_def, slot_type, slot_index):
		return {"ok": false, "error": "jogada inválida"}

	p["hand"].remove_at(hand_index)
	var card = _instantiate(card_def, owner_id)
	card["slotType"] = slot_type
	card["slotIndex"] = slot_index
	var target_arr = p["front"] if slot_type == "frente" else p["back"]
	target_arr[slot_index] = card

	if p["freeNextUnit"]:
		p["freeNextUnit"] = false
	else:
		p["unitPlaysThisRound"] += 1

	_log("%s colocaste %s." % [owner_id, card["nome"]])
	_on_enter_lane_debuff_hooks(card)
	_run_trigger(card, "onEnter")
	_advance_priority(owner_id)
	return {"ok": true, "card": card}

func _on_enter_lane_debuff_hooks(new_card) -> void:
	for e in enemies(new_card["ownerId"]):
		# TODO: run ability triggers for 'onEnterLaneDebuff'
		pass

func play_apoio(owner_id: String, hand_index: int, target_spec: Dictionary = {}) -> Dictionary:
	if phase != "placement" or activePlayer != owner_id:
		return {"ok": false, "error": "não é a tua vez"}
	var p = players[owner_id]
	if p["apoiosBlocked"]:
		return {"ok": false, "error": "apoios bloqueados este turno"}
	var card_def = p["hand"][hand_index] if hand_index < p["hand"].size() else null
	if !card_def or !card_def.get("isApoio", false):
		return {"ok": false, "error": "carta inválida"}

	p["hand"].remove_at(hand_index)
	var mult = 2 if p["apoioDoubleNext"] else 1
	p["apoioDoubleNext"] = false

	# TODO: Run ability for apoio
	_draw_card(owner_id, 1)
	_log("%s jogaste o Apoio %s." % [owner_id, card_def["nome"]])
	_check_auto_advance(owner_id)
	return {"ok": true}

func play_tatico_card(owner_id: String, tatico_hand_index: int, target_spec: Dictionary = {}) -> Dictionary:
	if phase != "placement" or activePlayer != owner_id:
		return {"ok": false, "error": "não é a tua vez"}
	var p = players[owner_id]
	var card_def = p["tacticoHand"][tatico_hand_index] if tatico_hand_index < p["tacticoHand"].size() else null
	if !card_def:
		return {"ok": false, "error": "carta tática inválida"}

	var tipo = card_def.get("tipo_tatico", "")

	# Equipamentos
	if tipo == "Equipamento":
		if !target_spec.has("targetCard"):
			return {"ok": false, "error": "escolhe uma unidade para equipar", "needsTarget": "card"}
		var target_card = target_spec["targetCard"]
		if target_card["ownerId"] != owner_id:
			return {"ok": false, "error": "só podes equipar unidades amigas"}

		p["tacticoHand"].remove_at(tatico_hand_index)
		target_card["equipamentos"].append(card_def)

		if card_def.has("bonus_ataque"):
			target_card["permBuffAtk"] += card_def["bonus_ataque"]
		if card_def.has("bonus_vida"):
			target_card["vidaMaxima"] += card_def["bonus_vida"]
			target_card["vidaAtual"] += card_def["bonus_vida"]

		_log("%s equipaste %s em %s." % [owner_id, card_def["nome"], target_card["nome"]])

		if !p["tacticoDeck"].is_empty():
			p["tacticoHand"].append(p["tacticoDeck"].pop_front())
		_check_auto_advance(owner_id)
		return {"ok": true, "card": card_def, "target": target_card}

	# Outras cartas táticas
	p["tacticoHand"].remove_at(tatico_hand_index)

	if !p["tacticoDeck"].is_empty():
		p["tacticoHand"].append(p["tacticoDeck"].pop_front())

	match tipo:
		"Magia":
			if card_def.has("dano"):
				var targets = enemies(owner_id)
				if !targets.is_empty():
					var target = targets[0]
					target["vidaAtual"] -= card_def["dano"]
					_log("%s lançaste %s (%d dano)." % [owner_id, card_def["nome"], card_def["dano"]])
		"Consumível":
			if card_def.has("cura"):
				var allies_list = allies(owner_id)
				if !allies_list.is_empty():
					var target = allies_list[0]
					var old_hp = target["vidaAtual"]
					target["vidaAtual"] = min(target["vidaMaxima"], target["vidaAtual"] + card_def["cura"])
					var healed = target["vidaAtual"] - old_hp
					_log("%s usaste %s (+%d HP)." % [owner_id, card_def["nome"], healed])
			p["tacticoGraveyard"].append(card_def)
		"Construção":
			var construct = card_def.duplicate()
			construct["vidaAtual"] = construct.get("vida_construcao", 8)
			construct["vidaMaxima"] = construct.get("vida_construcao", 8)
			construct["ownerId"] = owner_id
			construct["uid"] = _next_uid()
			p["activeTactics"].append(construct)
			_log("%s colocaste a Construção %s." % [owner_id, card_def["nome"]])
		"Clima":
			_log("%s ativaste o Clima %s." % [owner_id, card_def["nome"]])
		"Bênção":
			var allies_list = allies(owner_id)
			if !allies_list.is_empty():
				allies_list[0]["tempBuffAtk"] = (allies_list[0].get("tempBuffAtk", 0) + 2)
				_log("%s invocaste %s (+2 ATK)." % [owner_id, card_def["nome"]])

	_check_auto_advance(owner_id)
	return {"ok": true, "card": card_def}

func remove_equipamento(card_uid: String, equip_idx: int) -> Dictionary:
	var card = get_card(card_uid)
	if !card or !card.has("equipamentos") or equip_idx >= card["equipamentos"].size():
		return {"ok": false}

	var equip = card["equipamentos"][equip_idx]
	card["equipamentos"].remove_at(equip_idx)

	if equip.has("bonus_ataque"):
		card["permBuffAtk"] -= equip["bonus_ataque"]
	if equip.has("bonus_vida"):
		card["vidaMaxima"] -= equip["bonus_vida"]
		card["vidaAtual"] = min(card["vidaAtual"], card["vidaMaxima"])

	_log("%s removeste %s de %s." % [card["ownerId"], equip["nome"], card["nome"]])
	return {"ok": true}

func all_cards() -> Array:
	var cards = []
	for owner_id in ["player", "ai"]:
		var p = players[owner_id]
		cards.append_array(p["front"].filter(func(c): return c != null))
		cards.append_array(p["back"].filter(func(c): return c != null))
		cards.append_array(p["graveyard"])
	return cards

# ========== TURN FLOW ==========

func pass_turn(owner_id: String) -> Dictionary:
	if phase != "placement" or activePlayer != owner_id:
		return {"ok": false}
	players[owner_id]["donePlacing"] = true
	_log("%s passaste." % owner_id)
	_advance_priority(owner_id, true)
	return {"ok": true}

func _advance_priority(acted_owner_id: String, passed: bool = false) -> void:
	var other = opponent_of(acted_owner_id)
	var p = players[acted_owner_id]
	if !p["freeNextUnit"] and p["unitPlaysThisRound"] >= get_unit_cap(acted_owner_id) and !_has_playable_apoio(acted_owner_id):
		p["donePlacing"] = true
	if players["player"]["donePlacing"] and players["ai"]["donePlacing"]:
		_resolve_combat()
		return
	activePlayer = players[other]["donePlacing"] ? acted_owner_id : other

func _check_auto_advance(owner_id: String) -> void:
	var p = players[owner_id]
	if !_has_playable_apoio(owner_id) and (p["freeNextUnit"] or p["unitPlaysThisRound"] < get_unit_cap(owner_id)) and _has_playable_unit(owner_id):
		return
	if !_has_playable_apoio(owner_id) and !_has_playable_unit(owner_id):
		p["donePlacing"] = true
		if players["player"]["donePlacing"] and players["ai"]["donePlacing"]:
			_resolve_combat()
			return
		activePlayer = opponent_of(owner_id)

func _has_playable_apoio(owner_id: String) -> bool:
	var p = players[owner_id]
	return !p["apoiosBlocked"] and p["hand"].any(func(c): return c.get("isApoio", false))

func _has_playable_unit(owner_id: String) -> bool:
	var p = players[owner_id]
	return p["hand"].any(func(c):
		if c.get("isApoio", false):
			return false
		for i in range(FRONT_LANES):
			if can_place_unit(owner_id, c, "frente", i):
				return true
		for i in BACK_LANES:
			if can_place_unit(owner_id, c, "retaguarda", i):
				return true
		return false
	)

# ========== DEATH & DAMAGE ==========

func destroy_card(card, killer = null) -> void:
	if !card or (card["vidaAtual"] > 0 and card["escudoAtual"] > 0):
		return
	if card.get("cannotDieThisRound", false):
		card["vidaAtual"] = 1
		return
	var p = players[card["ownerId"]]
	var arr = p["back"] if card["slotType"] == "retaguarda" else p["front"]
	if arr[card["slotIndex"]] == card:
		arr[card["slotIndex"]] = null
	p["graveyard"].append(card)
	p["lastDeadCard"] = card
	_log("%s morreu." % card["nome"])

	# TODO: run onDeath trigger
	if killer:
		_run_on_kill(killer)
	_emit_ally_death(card)

func deal_damage(target, amount: int, source = null, opts: Dictionary = {}) -> void:
	if !target or amount <= 0:
		return
	if !opts.get("trueDamage", false):
		amount = max(0, amount - (target.get("tempDamageReduction", 0)) - (target.get("_laneReduction", 0)))
	if amount <= 0:
		return
	if target["escudoAtual"] > 0:
		var absorb = min(target["escudoAtual"], amount)
		target["escudoAtual"] -= absorb
		amount -= absorb
	target["vidaAtual"] -= amount
	target["tookDamageThisRound"] = true
	if target["vidaAtual"] <= 0:
		if target.get("cannotDieThisRound", false):
			target["vidaAtual"] = 1
		else:
			destroy_card(target, source)

func _run_trigger(card, trigger: String) -> void:
	if _ability_dispatcher:
		_ability_dispatcher.run_trigger(self, card, trigger)

func _run_on_kill(card) -> void:
	if _ability_dispatcher:
		_ability_dispatcher.run_trigger(self, card, "onKill")

func _emit_ally_death(dead_card) -> void:
	for c in allies(dead_card["ownerId"]):
		# TODO: run onAllyDeath trigger
		pass

func _emit_ally_healed(healed_card) -> void:
	for c in allies(healed_card["ownerId"]):
		# TODO: run onAllyHealed trigger
		pass

# ========== COMBAT ==========

func _run_turn_start_triggers() -> void:
	recompute_statics()
	all_in_play().forEach(func(c):
		c["tookDamageThisRound"] = false
		c["attackedThisRound"] = false
	)
	# TODO: run turnStart triggers
	for owner_id in ["player", "ai"]:
		var p = players[owner_id]
		p["apoiosBlocked"] = p["apoiosBlockedNextRound"]
		p["apoiosBlockedNextRound"] = false
		p["unitPlaysThisRound"] = 0
		p["donePlacing"] = false

func _resolve_combat() -> void:
	phase = "combat"
	combatSteps = []
	recompute_statics()

	var order = []
	# Assassins first
	for owner_id in ["player", "ai"]:
		for c in allies(owner_id):
			if c["papel"] == "ASSASSINO" and _can_act(c):
				order.append({"kind": "assassino", "card": c})
	# Then archers
	for owner_id in ["player", "ai"]:
		for c in allies(owner_id):
			if c["papel"] == "ATIRADOR" and _can_act(c):
				order.append({"kind": "atirador", "card": c})
	# Then front rows by lane
	for lane in range(FRONT_LANES):
		for owner_id in ["player", "ai"]:
			var c = players[owner_id]["front"][lane]
			if c and _can_act(c) and c["papel"] in ["TANQUE", "GUERREIRO"]:
				order.append({"kind": "frente", "card": c})

	for step in order:
		if step["card"]["vidaAtual"] <= 0:
			continue
		_resolve_attack(step["card"], step["kind"])

	_end_of_round()

func _can_act(card) -> bool:
	if card["papel"] == "ASSASSINO" or card.get("readyToAttack", false):
		return true
	return card["turnosEmCampo"] > 0

func _rupture_threshold(card) -> int:
	return 3 if players[opponent_of(card["ownerId"])]["hasSombra"] else 2

func _resolve_attack(attacker, kind: String) -> void:
	attacker["attackedThisRound"] = true
	var threshold = _rupture_threshold(attacker)
	if attacker.get("forcedRupture", false) or attacker["pressaoMarcas"] >= threshold:
		attacker["forcedRupture"] = false
		attacker["pressaoMarcas"] = 0
		var dmg = get_effective_ataque(attacker) + get_alignment_atk_bonus(attacker)
		var tower_owner = opponent_of(attacker["ownerId"])
		damage_tower(tower_owner, dmg)
		combatSteps.append({"type": "rupture", "attacker": attacker["uid"], "amount": dmg, "towerOwner": tower_owner, "towerAfter": towers[tower_owner]})
		return

	if kind == "assassino":
		var back = BACK_LANES.map(func(i): return players[opponent_of(attacker["ownerId"])]["back"][i]).filter(func(c): return c != null)
		var target = back.reduce(func(a, b): return b["vidaAtual"] < a["vidaAtual"] ? b : a, null) if !back.is_empty() else null
		_strike(attacker, target, {"siegeIfNoTarget": true})
		return

	if kind == "atirador":
		var target = pick_lowest_vida_enemy_for_combat(attacker["ownerId"])
		_strike(attacker, target, {"siegeIfNoTarget": true})
		return

	# Front row combat by lane
	var opp = players[opponent_of(attacker["ownerId"])]
	var lane = attacker["slotIndex"]
	var target = opp["front"][lane]
	if !target and BACK_LANES.has(lane):
		target = opp["back"][lane]
	_strike(attacker, target, {"siegeIfNoTarget": true})

func _strike(attacker, target, opts: Dictionary = {}) -> void:
	if !target:
		if opts.get("siegeIfNoTarget", false):
			var dmg = get_effective_ataque(attacker) + get_alignment_atk_bonus(attacker)
			var tower_owner = opponent_of(attacker["ownerId"])
			damage_tower(tower_owner, dmg)
			combatSteps.append({"type": "siege", "attacker": attacker["uid"], "amount": dmg, "towerOwner": tower_owner, "towerAfter": towers[tower_owner]})
		return

	# TODO: run target onEnter trigger
	_apply_lane_reductions(target)

	var dmg = get_effective_ataque(attacker)
	dmg += get_alignment_atk_bonus(attacker)
	# TODO: dmg += get_combat_mod_bonus(attacker, target)
	dmg = int(dmg * get_matchup_multiplier(attacker, target))
	dmg = max(0, dmg)

	_run_on_attacked(target, attacker)
	var was_alive = target["vidaAtual"] > 0
	deal_damage(target, dmg, attacker)
	if was_alive and target["vidaAtual"] <= 0:
		_run_on_kill(attacker)
	combatSteps.append({"type": "attack", "attacker": attacker["uid"], "target": target["uid"], "amount": dmg})

func _apply_lane_reductions(target) -> void:
	target["_laneReduction"] = 0
	for c in allies(target["ownerId"]):
		# TODO: run damage reduction triggers
		pass

func _run_on_attacked(target, attacker) -> void:
	# TODO: run onAttacked trigger
	pass

func _end_of_round() -> void:
	for c in all_in_play():
		# TODO: run turnEnd and special_countdown triggers
		pass

	all_in_play().forEach(func(c):
		c["tempBuffAtk"] = 0
		c["tempDamageReduction"] = 0
		c["_laneReduction"] = 0
		c["_laneDebuffTemp"] = 0
		c["attackedLastRound"] = c["attackedThisRound"]
		c["turnosEmCampo"] += 1
		if c.get("pressureLocked", 0) > 0:
			c["pressureLocked"] -= 1
		else:
			add_pressure_mark(c, 1)
		c["cannotDieThisRound"] = false
	)

	if _check_win():
		return
	if round >= ROUND_LIMIT:
		winner = "player" if towers["ai"] < towers["player"] else ("ai" if towers["player"] < towers["ai"] else "empate")
		phase = "gameover"
		_log("Limite de turnos atingido. Vencedor: %s." % winner)
		return

	round += 1
	activePlayer = "ai" if round % 2 == 0 else "player"
	phase = "placement"
	_draw_card("player", 1)
	_draw_card("ai", 1)
	_run_turn_start_triggers()

func _check_win() -> bool:
	if towers["player"] <= 0:
		winner = "ai"
		phase = "gameover"
		return true
	if towers["ai"] <= 0:
		winner = "player"
		phase = "gameover"
		return true
	return false

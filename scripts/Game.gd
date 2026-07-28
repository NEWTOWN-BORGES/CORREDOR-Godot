extends RefCounted
class_name Game

# Motor de jogo — CORREDOR (tradução 1:1 de js/game-engine.js, v4 torres)
#
#   - Sem Energia/mana. Cada jogador pode jogar até 3 unidades por turno
#     (6 no turno 1).
#   - Jogo alternado ao estilo Gwent: alterna prioridade, uma carta de cada vez,
#     até ambos passarem ou esgotarem o limite de unidades.
#   - Apoios custam 0, sem limite; jogar um Apoio não passa prioridade.
#   - Tabuleiro: 6 colunas na frente (Tanque/Guerreiro). Retaguarda tem 4
#     colunas de combate (1-4); as colunas 0 e 5 são só para Apoios.
#   - Cada jogador tem a sua Torre (30 de vida). Coluna limpa → ataque à Torre.
#   - Pressão/Ruptura e invocação lenta (Assassino ataca já ao entrar).

const FRONT_ROLES := ["TANQUE", "GUERREIRO"]
const BACK_ROLES := ["ASSASSINO", "CURADOR", "ATIRADOR"]
const FRONT_LANES := 6
const BACK_LANES := [1, 2, 3, 4]
const BASE_UNIT_CAP := 3
const TOWER_MAX := 30
const ROUND_LIMIT := 12
const HAND_LIMIT := 10

const FAMILY_A := ["ORDEM", "PUREZA"]
const FAMILY_B := ["SELVA", "MAGIA"]

const STRONG_AGAINST := {
	"FOGO": ["PLANTAS", "METAL"],
	"ÁGUA": ["FOGO", "TERRA"],
	"PLANTAS": ["ÁGUA", "TERRA"],
	"VENTO": ["PLANTAS", "BESTA"],
	"TERRA": ["METAL", "FOGO"],
	"ANJO": ["DEMÓNIO", "SOMBRA"],
	"DEMÓNIO": ["ANCESTRAL", "NORMAL"],
	"ANCESTRAL": ["ANJO", "DEMÓNIO"],
	"FADA": ["METAL", "TERRA"],
	"LUZ": ["SOMBRA", "DEMÓNIO"],
	"SOMBRA": ["LUZ", "ANJO"],
	"METAL": ["FADA", "PLANTAS"],
	"BESTA": ["PLANTAS", "NORMAL"],
	"NORMAL": []
}

const WEAK_TO := {
	"FOGO": ["ÁGUA", "TERRA"],
	"ÁGUA": ["PLANTAS", "VENTO"],
	"PLANTAS": ["FOGO", "VENTO"],
	"VENTO": ["ÁGUA", "TERRA"],
	"TERRA": ["ÁGUA", "PLANTAS"],
	"ANJO": ["DEMÓNIO"],
	"DEMÓNIO": ["ANJO", "LUZ"],
	"ANCESTRAL": ["FOGO"],
	"FADA": ["METAL"],
	"LUZ": ["SOMBRA"],
	"SOMBRA": ["LUZ"],
	"METAL": ["FOGO", "TERRA", "VENTO"],
	"BESTA": ["VENTO", "ANJO"],
	"NORMAL": []
}

# Estado global
var towers: Dictionary = {"player": TOWER_MAX, "ai": TOWER_MAX}
var current_round: int = 1
var phase: String = "placement"      # placement | combat | gameover
var active_player: String = "player"
var winner: String = ""
var combat_steps: Array = []
var players: Dictionary = {}

var abilities: AbilityDispatcher = null

var _uid_counter: int = 1
var _log_callback: Callable = Callable()
var _current_apoio_mult: int = 1

# ---------------------------------------------------------------------------
# Utilitários internos
# ---------------------------------------------------------------------------

func _next_uid() -> String:
	var uid := "c%d" % _uid_counter
	_uid_counter += 1
	return uid

func _shuffle(arr: Array) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a

func _log(msg: String) -> void:
	if _log_callback.is_valid():
		_log_callback.call(msg)
	else:
		print(msg)

func _side_name(owner_id: String) -> String:
	return "Tu" if owner_id == "player" else "Adversário"

# ---------------------------------------------------------------------------
# Inicialização
# ---------------------------------------------------------------------------

func init_game(player_deck: Array, ai_deck: Array, log_callback: Callable = Callable()) -> void:
	_log_callback = log_callback
	if abilities == null:
		abilities = AbilityDispatcher.new()

	towers = {"player": TOWER_MAX, "ai": TOWER_MAX}
	current_round = 1
	phase = "placement"
	active_player = "player"
	winner = ""
	combat_steps = []

	var player_mil := _filter_military(player_deck)
	var player_tac := _filter_tactical(player_deck)
	var ai_mil := _filter_military(ai_deck)
	var ai_tac := _filter_tactical(ai_deck)

	players = {
		"player": _make_player_state(player_mil, player_tac),
		"ai": _make_player_state(ai_mil, ai_tac)
	}

	players["player"]["hasSombra"] = _deck_has_alignment(player_mil, "SOMBRA")
	players["ai"]["hasSombra"] = _deck_has_alignment(ai_mil, "SOMBRA")
	players["player"]["cohesionBroken"] = _compute_cohesion_broken(player_mil)
	players["ai"]["cohesionBroken"] = _compute_cohesion_broken(ai_mil)

	_draw_initial_hand("player")
	_draw_initial_hand("ai")
	_run_turn_start_triggers()

func _filter_military(deck: Array) -> Array:
	var out := []
	for c in deck:
		if str(c.get("tipo_tatico", "")) == "":
			out.append(c)
	return out

func _filter_tactical(deck: Array) -> Array:
	var out := []
	for c in deck:
		if str(c.get("tipo_tatico", "")) != "":
			out.append(c)
	return out

func _deck_has_alignment(deck: Array, alignment: String) -> bool:
	for c in deck:
		if str(c.get("alinhamento", "")) == alignment:
			return true
	return false

func _compute_cohesion_broken(deck: Array) -> bool:
	var has_a := false
	var has_b := false
	for c in deck:
		var align := str(c.get("alinhamento", ""))
		if FAMILY_A.has(align):
			has_a = true
		if FAMILY_B.has(align):
			has_b = true
	return has_a and has_b

func _make_player_state(military_deck: Array, tactical_deck: Array) -> Dictionary:
	return {
		# Baralho militar
		"deck": _shuffle(military_deck),
		"hand": [],
		"graveyard": [],

		# Baralho tático
		"tacticoDeck": _shuffle(tactical_deck),
		"tacticoHand": [],
		"tacticoGraveyard": [],

		# Tabuleiro
		"front": [null, null, null, null, null, null],
		"back": [null, null, null, null, null, null],
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

		"hasSombra": false,
		"cohesionBroken": false
	}

# ---------------------------------------------------------------------------
# Consultas ao tabuleiro
# ---------------------------------------------------------------------------

func opponent_of(owner_id: String) -> String:
	return "ai" if owner_id == "player" else "player"

func allies(owner_id: String) -> Array:
	var p: Dictionary = players[owner_id]
	var out := []
	for c in p["front"]:
		if c != null:
			out.append(c)
	for c in p["back"]:
		if c != null:
			out.append(c)
	return out

func enemies(owner_id: String) -> Array:
	return allies(opponent_of(owner_id))

func all_in_play() -> Array:
	var out := allies("player")
	out.append_array(allies("ai"))
	return out

func get_card(uid) -> Variant:
	if uid == null:
		return null
	for c in all_in_play():
		if c["uid"] == uid:
			return c
	return null

func lane_enemies_of(card: Dictionary) -> Array:
	var out := []
	for e in enemies(card["ownerId"]):
		if _same_lane(card, e):
			out.append(e)
	return out

func _same_lane(a: Dictionary, b: Dictionary) -> bool:
	return a["slotIndex"] == b["slotIndex"]

func _targetable(card, by_enemy: bool = false) -> bool:
	if card == null:
		return false
	if card.get("cannotBeTargeted", false) and current_round <= int(card.get("cannotBeTargetedUntilRound", 0)):
		return false
	if by_enemy and card.get("cannotBeTargetedByEnemies", false):
		return false
	return true

func pick_highest_ataque_enemy(owner_id: String) -> Variant:
	var best = null
	for c in enemies(owner_id):
		if not _targetable(c, true):
			continue
		if best == null or get_effective_ataque(c) > get_effective_ataque(best):
			best = c
	return best

func pick_lowest_vida_enemy(owner_id: String) -> Variant:
	var best = null
	for c in enemies(owner_id):
		if not _targetable(c, true):
			continue
		if best == null or c["vidaAtual"] < best["vidaAtual"]:
			best = c
	return best

func pick_lowest_vida_enemy_for_combat(owner_id: String) -> Variant:
	var best = null
	for c in enemies(owner_id):
		if best == null or c["vidaAtual"] < best["vidaAtual"]:
			best = c
	return best

func pick_most_wounded_ally(owner_id: String) -> Variant:
	var list := []
	for c in allies(owner_id):
		if _targetable(c):
			list.append(c)
	var best = null
	for c in list:
		if c["vidaAtual"] < c["vidaMaxima"]:
			if best == null or c["vidaAtual"] < best["vidaAtual"]:
				best = c
	if best != null:
		return best
	return list[0] if not list.is_empty() else null

func pick_nearest_ally(card: Dictionary) -> Variant:
	var best = null
	for c in allies(card["ownerId"]):
		if c["uid"] == card["uid"]:
			continue
		if best == null:
			best = c
		elif abs(c["slotIndex"] - card["slotIndex"]) < abs(best["slotIndex"] - card["slotIndex"]):
			best = c
	return best

func get_graveyard_count(owner_id: String) -> int:
	return (players[owner_id]["graveyard"] as Array).size()

func set_flag(owner_id: String, key: String, value) -> void:
	players[owner_id]["flags"][key] = value

func get_flag(owner_id: String, key: String) -> Variant:
	return players[owner_id]["flags"].get(key)

func all_cards() -> Array:
	var out := []
	for owner_id in ["player", "ai"]:
		var p: Dictionary = players[owner_id]
		for c in p["front"]:
			if c != null:
				out.append(c)
		for c in p["back"]:
			if c != null:
				out.append(c)
		out.append_array(p["graveyard"])
	return out

# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------

func get_effective_ataque(card: Dictionary) -> int:
	var v: int = int(card["baseAtaque"]) + int(card["permBuffAtk"]) \
		+ int(card["staticBonusAtk"]) + int(card["tempBuffAtk"]) \
		+ int(card.get("_laneDebuffTemp", 0))
	return max(0, v)

func get_vida_maxima(card: Dictionary) -> int:
	var v: int = int(card["baseVida"]) + int(card["permBuffVida"]) \
		+ int(card["staticBonusVida"]) - int(card["permVidaMaxLoss"])
	return max(1, v)

func recompute_statics() -> void:
	var board := all_in_play()
	for c in board:
		c["staticBonusAtk"] = 0
		c["staticBonusVida"] = 0
		c["_laneDebuffTemp"] = 0
	for c in board:
		var def := abilities.get_unit_ability(str(c.get("habilidade_texto", "")))
		if def.is_empty():
			continue
		var trigger := str(def.get("trigger", ""))
		if trigger == "static" and def.has("run"):
			def["run"].call(self, c, null, null)
		elif trigger == "staticLaneDebuff":
			var amount := int(def.get("amount", 0))
			for e in lane_enemies_of(c):
				e["_laneDebuffTemp"] = int(e.get("_laneDebuffTemp", 0)) - amount
	for c in board:
		c["vidaMaxima"] = get_vida_maxima(c)
		if c["vidaAtual"] > c["vidaMaxima"]:
			c["vidaAtual"] = c["vidaMaxima"]

func has_alignment_bonus(card: Dictionary) -> bool:
	if card.get("noAlignmentBonus", false):
		return false
	if players[card["ownerId"]]["cohesionBroken"]:
		return false
	var blocked = get_flag(opponent_of(card["ownerId"]), "alignmentBlockedTipos")
	if blocked != null:
		for t in card.get("tipo", []):
			if (blocked as Array).has(t):
				return false
	return true

func get_alignment_atk_bonus(card: Dictionary) -> int:
	if not has_alignment_bonus(card):
		return 0
	if str(card.get("alinhamento", "")) == "ORDEM" and int(card.get("custo", 0)) >= 3:
		return 1
	return 0

func get_matchup_multiplier(attacker: Dictionary, defender: Dictionary) -> float:
	var mult := 1.0
	var atk_types: Array = attacker.get("tipo", [])
	var def_types: Array = defender.get("tipo", [])

	var is_weak := false
	for dt in def_types:
		var weak_list: Array = WEAK_TO.get(dt, [])
		for at in atk_types:
			if weak_list.has(at):
				is_weak = true
				break
		if is_weak:
			break

	var is_resisted := false
	for dt in def_types:
		var strong_list: Array = STRONG_AGAINST.get(dt, [])
		for s in strong_list:
			if atk_types.has(s):
				is_resisted = true
				break
		if is_resisted:
			break

	if is_weak:
		mult += 0.4
	if is_resisted:
		mult -= 0.4
	return mult

func get_combat_mod_bonus(card: Dictionary, defender: Dictionary) -> int:
	var def := abilities.get_unit_ability(str(card.get("habilidade_texto", "")))
	if def.is_empty() or str(def.get("trigger", "")) != "combatMod" or not def.has("run"):
		return 0
	var result = def["run"].call(self, card, defender, null)
	return int(result) if result != null else 0

# ---------------------------------------------------------------------------
# Compra de cartas
# ---------------------------------------------------------------------------

func draw_card(owner_id: String, n: int) -> void:
	var p: Dictionary = players[owner_id]
	for i in range(n):
		if (p["deck"] as Array).is_empty():
			break
		if (p["hand"] as Array).size() >= HAND_LIMIT:
			break
		p["hand"].append(p["deck"].pop_front())

func _draw_initial_hand(owner_id: String) -> void:
	var p: Dictionary = players[owner_id]
	var deck: Array = p["deck"]

	var front_indices := []
	for i in range(deck.size()):
		if front_indices.size() >= 4:
			break
		if FRONT_ROLES.has(str(deck[i].get("papel", ""))):
			front_indices.append(i)

	var back_indices := []
	for i in range(deck.size()):
		if back_indices.size() >= 2:
			break
		if front_indices.has(i):
			continue
		if BACK_ROLES.has(str(deck[i].get("papel", ""))):
			back_indices.append(i)

	var selected := []
	var remaining := []
	for i in range(deck.size()):
		if front_indices.has(i) or back_indices.has(i):
			selected.append(deck[i])
		else:
			remaining.append(deck[i])

	p["hand"].append_array(selected)
	p["deck"] = remaining

	if (p["hand"] as Array).size() < 6:
		draw_card(owner_id, 6 - (p["hand"] as Array).size())

	# 5 cartas táticas iniciais
	for i in range(5):
		if (p["tacticoDeck"] as Array).is_empty():
			break
		p["tacticoHand"].append(p["tacticoDeck"].pop_front())

# ---------------------------------------------------------------------------
# Mutadores expostos às habilidades
# ---------------------------------------------------------------------------

func grant_extra_unit_cap(owner_id: String, n: int) -> void:
	players[owner_id]["extraUnitCap"] += n

func grant_free_next_unit(owner_id: String) -> void:
	players[owner_id]["freeNextUnit"] = true

func get_unit_cap(owner_id: String) -> int:
	var base_cap := 6 if current_round == 1 else BASE_UNIT_CAP
	return base_cap + int(players[owner_id]["extraUnitCap"])

func heal_tower(owner_id: String, amount: int) -> void:
	towers[owner_id] = min(TOWER_MAX, int(towers[owner_id]) + amount)
	_log("A Torre de %s recupera %d. (%d/%d)" % [_side_name(owner_id), amount, towers[owner_id], TOWER_MAX])

func damage_tower(target_owner_id: String, amount: int) -> void:
	towers[target_owner_id] = max(0, int(towers[target_owner_id]) - amount)
	_log("A Torre de %s leva %d de dano. (%d/%d)" % [_side_name(target_owner_id), amount, towers[target_owner_id], TOWER_MAX])
	_check_win()

func add_pressure_mark(card: Dictionary, delta: int) -> void:
	card["pressaoMarcas"] = max(0, int(card["pressaoMarcas"]) + delta)

func add_atk_mod(card: Dictionary, delta: int) -> void:
	card["tempBuffAtk"] = int(card["tempBuffAtk"]) + delta

func perm_buff(card: Dictionary, atk: int, vida: int) -> void:
	card["permBuffAtk"] = int(card["permBuffAtk"]) + atk
	card["permBuffVida"] = int(card["permBuffVida"]) + vida
	card["vidaAtual"] = int(card["vidaAtual"]) + vida

func reduce_vida_maxima(card: Dictionary, n: int) -> void:
	card["permVidaMaxLoss"] = int(card["permVidaMaxLoss"]) + n
	card["vidaMaxima"] = get_vida_maxima(card)
	if card["vidaAtual"] > card["vidaMaxima"]:
		card["vidaAtual"] = card["vidaMaxima"]

func add_shield(card: Dictionary, n: int) -> void:
	card["escudoAtual"] = int(card["escudoAtual"]) + n

func heal(card, n: int) -> void:
	if card == null:
		return
	if int(card["vidaAtual"]) <= 0 or card.get("cannotBeHealed", false):
		return
	card["vidaAtual"] = min(int(card["vidaMaxima"]), int(card["vidaAtual"]) + n)
	_emit_ally_healed(card)

func clear_negative_effects(card: Dictionary) -> void:
	card["tempBuffAtk"] = max(0, int(card["tempBuffAtk"]))
	card["pressureLocked"] = 0
	card["_laneDebuffTemp"] = 0

func move_card(card: Dictionary, slot_type: String, slot_index: int) -> void:
	var p: Dictionary = players[card["ownerId"]]
	var from_arr: Array = p["back"] if card["slotType"] == "retaguarda" else p["front"]
	var to_arr: Array = p["back"] if slot_type == "retaguarda" else p["front"]
	if to_arr[slot_index] != null:
		return
	from_arr[card["slotIndex"]] = null
	card["slotType"] = slot_type
	card["slotIndex"] = slot_index
	to_arr[slot_index] = card

func set_apoio_double(owner_id: String) -> void:
	players[owner_id]["apoioDoubleNext"] = true

func apoio_mult() -> int:
	return _current_apoio_mult

func block_apoios(owner_id: String) -> void:
	players[owner_id]["apoiosBlockedNextRound"] = true

func force_rupture(card: Dictionary) -> void:
	card["forcedRupture"] = true

func return_last_dead_to_hand(owner_id: String) -> void:
	var p: Dictionary = players[owner_id]
	var last = p["lastDeadCard"]
	if last != null:
		p["hand"].append(last)
		p["lastDeadCard"] = null
		_log("%s volta à mão." % last["nome"])

# ---------------------------------------------------------------------------
# Instanciação
# ---------------------------------------------------------------------------

func _instantiate(card_def: Dictionary, owner_id: String) -> Dictionary:
	var vida := int(card_def.get("vida", 1))
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
		"baseAtaque": int(card_def.get("ataque", 0)),
		"baseVida": vida,
		"permBuffAtk": 0,
		"permBuffVida": 0,
		"permVidaMaxLoss": 0,
		"tempBuffAtk": 0,
		"tempDamageReduction": 0,
		"staticBonusAtk": 0,
		"staticBonusVida": 0,
		"escudoAtual": int(card_def.get("escudo", 0)),
		"vidaMaxima": vida,
		"vidaAtual": vida,
		"pressaoMarcas": 0,
		"turnosEmCampo": 0,
		"enteredRound": current_round,
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
		"equipamentos": [],
		"_laneReduction": 0,
		"_laneDebuffTemp": 0,
		"_raizProfundaStacks": 0
	}

# ---------------------------------------------------------------------------
# Colocação de unidades
# ---------------------------------------------------------------------------

func can_place_unit(owner_id: String, card_def: Dictionary, slot_type: String, slot_index: int) -> bool:
	var p: Dictionary = players[owner_id]
	var roles: Array = FRONT_ROLES if slot_type == "frente" else BACK_ROLES
	if not roles.has(str(card_def.get("papel", ""))):
		return false
	if slot_type == "retaguarda" and not BACK_LANES.has(slot_index):
		return false
	if slot_index < 0 or slot_index >= FRONT_LANES:
		return false
	var arr: Array = p["front"] if slot_type == "frente" else p["back"]
	if arr[slot_index] != null:
		return false
	if not p["freeNextUnit"] and int(p["unitPlaysThisRound"]) >= get_unit_cap(owner_id):
		return false
	return true

func play_unit(owner_id: String, hand_index: int, slot_type: String, slot_index: int) -> Dictionary:
	if phase != "placement" or active_player != owner_id:
		return {"ok": false, "error": "não é a tua vez"}
	var p: Dictionary = players[owner_id]
	if hand_index < 0 or hand_index >= (p["hand"] as Array).size():
		return {"ok": false, "error": "carta inválida"}
	var card_def: Dictionary = p["hand"][hand_index]
	if card_def.get("isApoio", false):
		return {"ok": false, "error": "carta inválida"}
	if not can_place_unit(owner_id, card_def, slot_type, slot_index):
		return {"ok": false, "error": "jogada inválida"}

	p["hand"].remove_at(hand_index)
	var card := _instantiate(card_def, owner_id)
	card["slotType"] = slot_type
	card["slotIndex"] = slot_index
	var arr: Array = p["front"] if slot_type == "frente" else p["back"]
	arr[slot_index] = card

	if p["freeNextUnit"]:
		p["freeNextUnit"] = false
	else:
		p["unitPlaysThisRound"] = int(p["unitPlaysThisRound"]) + 1

	_log("%s colocaste %s." % [_side_name(owner_id), card["nome"]])
	_on_enter_lane_debuff_hooks(card)
	_run_trigger(card, "onEnter")

	_advance_priority(owner_id)
	return {"ok": true, "card": card}

func _on_enter_lane_debuff_hooks(new_card: Dictionary) -> void:
	for e in enemies(new_card["ownerId"]):
		var def := abilities.get_unit_ability(str(e.get("habilidade_texto", "")))
		if def.is_empty():
			continue
		var trigger := str(def.get("trigger", ""))
		if trigger == "onEnterLaneDebuff" and _same_lane(e, new_card):
			add_atk_mod(new_card, -int(def.get("amount", 0)))
		elif trigger == "onEnterLaneDebuff_special":
			reduce_vida_maxima(new_card, int(def.get("amount", 1)))

# ---------------------------------------------------------------------------
# Apoios
# ---------------------------------------------------------------------------

func play_apoio(owner_id: String, hand_index: int, target_spec: Dictionary = {}) -> Dictionary:
	if phase != "placement" or active_player != owner_id:
		return {"ok": false, "error": "não é a tua vez"}
	var p: Dictionary = players[owner_id]
	if p["apoiosBlocked"]:
		return {"ok": false, "error": "apoios bloqueados este turno"}
	if hand_index < 0 or hand_index >= (p["hand"] as Array).size():
		return {"ok": false, "error": "carta inválida"}
	var card_def: Dictionary = p["hand"][hand_index]
	if not card_def.get("isApoio", false):
		return {"ok": false, "error": "carta inválida"}

	var apoio_id := str(card_def.get("id", ""))
	var def := abilities.get_apoio_ability(apoio_id)
	if def.is_empty():
		return {"ok": false, "error": "apoio desconhecido"}

	p["hand"].remove_at(hand_index)
	_current_apoio_mult = 2 if p["apoioDoubleNext"] else 1
	p["apoioDoubleNext"] = false

	# needsTarget é null ou String — sem tipo inferido, senão o Godot recusa
	var needs = def.get("needsTarget")
	if needs == "allyPair":
		abilities.run_apoio(self, apoio_id, owner_id, target_spec.get("from"), target_spec.get("to"))
	else:
		abilities.run_apoio(self, apoio_id, owner_id, target_spec.get("target"), target_spec.get("extra"))
	_current_apoio_mult = 1

	draw_card(owner_id, 1)
	_log("%s jogaste o Apoio %s." % [_side_name(owner_id), card_def.get("nome", "")])
	_check_auto_advance(owner_id)
	return {"ok": true, "card": card_def}

# ---------------------------------------------------------------------------
# Cartas táticas
# ---------------------------------------------------------------------------

func play_tatico_card(owner_id: String, tactico_hand_index: int, target_spec: Dictionary = {}) -> Dictionary:
	if phase != "placement" or active_player != owner_id:
		return {"ok": false, "error": "não é a tua vez"}
	var p: Dictionary = players[owner_id]
	if tactico_hand_index < 0 or tactico_hand_index >= (p["tacticoHand"] as Array).size():
		return {"ok": false, "error": "carta tática inválida"}
	var card_def: Dictionary = p["tacticoHand"][tactico_hand_index]
	var tipo := str(card_def.get("tipo_tatico", ""))

	if tipo == "Equipamento":
		var target_card = target_spec.get("targetCard")
		if target_card == null:
			return {"ok": false, "error": "escolhe uma unidade para equipar", "needsTarget": "card"}
		if target_card["ownerId"] != owner_id:
			return {"ok": false, "error": "só podes equipar unidades amigas"}

		p["tacticoHand"].remove_at(tactico_hand_index)
		target_card["equipamentos"].append(card_def)

		var bonus_atk := int(card_def.get("bonus_ataque", 0))
		var bonus_vida := int(card_def.get("bonus_vida", 0))
		if bonus_atk != 0:
			target_card["permBuffAtk"] = int(target_card["permBuffAtk"]) + bonus_atk
		if bonus_vida != 0:
			target_card["permBuffVida"] = int(target_card["permBuffVida"]) + bonus_vida
			target_card["vidaMaxima"] = get_vida_maxima(target_card)
			target_card["vidaAtual"] = int(target_card["vidaAtual"]) + bonus_vida

		_log("%s equipaste %s em %s." % [_side_name(owner_id), card_def.get("nome", ""), target_card["nome"]])
		_refill_tactico(owner_id)
		_check_auto_advance(owner_id)
		return {"ok": true, "card": card_def, "target": target_card}

	p["tacticoHand"].remove_at(tactico_hand_index)
	_refill_tactico(owner_id)

	match tipo:
		"Magia":
			var dano := int(card_def.get("dano", 0))
			if dano > 0:
				var foes := enemies(owner_id)
				if not foes.is_empty():
					deal_damage(foes[0], dano, null)
					_log("%s lançaste %s (%d de dano)." % [_side_name(owner_id), card_def.get("nome", ""), dano])
			p["tacticoGraveyard"].append(card_def)
		"Consumível":
			var cura := int(card_def.get("cura", 0))
			if cura > 0:
				var friends := allies(owner_id)
				if not friends.is_empty():
					var target: Dictionary = friends[0]
					var old_hp := int(target["vidaAtual"])
					heal(target, cura)
					_log("%s usaste %s (+%d HP)." % [_side_name(owner_id), card_def.get("nome", ""), int(target["vidaAtual"]) - old_hp])
			p["tacticoGraveyard"].append(card_def)
		"Construção":
			var construct := card_def.duplicate(true)
			var vida_c := int(card_def.get("vida_construcao", 8))
			construct["vidaAtual"] = vida_c
			construct["vidaMaxima"] = vida_c
			construct["ownerId"] = owner_id
			construct["uid"] = _next_uid()
			p["activeTactics"].append(construct)
			_log("%s colocaste a Construção %s." % [_side_name(owner_id), card_def.get("nome", "")])
		"Clima":
			p["activeTactics"].append({
				"uid": _next_uid(),
				"ownerId": owner_id,
				"nome": card_def.get("nome", ""),
				"tipo_tatico": "Clima",
				"turnosRestantes": int(card_def.get("duracao_turnos", 2))
			})
			_log("%s ativaste o Clima %s." % [_side_name(owner_id), card_def.get("nome", "")])
		"Bênção":
			var friends_b := allies(owner_id)
			if not friends_b.is_empty():
				add_atk_mod(friends_b[0], 2)
				_log("%s invocaste %s (+2 de Ataque)." % [_side_name(owner_id), card_def.get("nome", "")])
			p["tacticoGraveyard"].append(card_def)
		_:
			_log("%s jogaste %s." % [_side_name(owner_id), card_def.get("nome", "")])

	_check_auto_advance(owner_id)
	return {"ok": true, "card": card_def}

func _refill_tactico(owner_id: String) -> void:
	var p: Dictionary = players[owner_id]
	if not (p["tacticoDeck"] as Array).is_empty():
		p["tacticoHand"].append(p["tacticoDeck"].pop_front())

func remove_equipamento(card_uid: String, equip_idx: int) -> Dictionary:
	var card = get_card(card_uid)
	if card == null:
		return {"ok": false}
	var equips: Array = card["equipamentos"]
	if equip_idx < 0 or equip_idx >= equips.size():
		return {"ok": false}

	var equip: Dictionary = equips[equip_idx]
	equips.remove_at(equip_idx)

	var bonus_atk := int(equip.get("bonus_ataque", 0))
	var bonus_vida := int(equip.get("bonus_vida", 0))
	if bonus_atk != 0:
		card["permBuffAtk"] = int(card["permBuffAtk"]) - bonus_atk
	if bonus_vida != 0:
		card["permBuffVida"] = int(card["permBuffVida"]) - bonus_vida
		card["vidaMaxima"] = get_vida_maxima(card)
		card["vidaAtual"] = min(int(card["vidaAtual"]), int(card["vidaMaxima"]))

	_log("%s removeste %s de %s." % [_side_name(card["ownerId"]), equip.get("nome", ""), card["nome"]])
	return {"ok": true}

# ---------------------------------------------------------------------------
# Prioridade e passagem de turno
# ---------------------------------------------------------------------------

func pass_turn(owner_id: String) -> Dictionary:
	if phase != "placement" or active_player != owner_id:
		return {"ok": false}
	players[owner_id]["donePlacing"] = true
	_log("%s passaste." % _side_name(owner_id))
	_advance_priority(owner_id)
	return {"ok": true}

func _advance_priority(acted_owner_id: String) -> void:
	var other := opponent_of(acted_owner_id)
	var p: Dictionary = players[acted_owner_id]
	if not p["freeNextUnit"] \
		and int(p["unitPlaysThisRound"]) >= get_unit_cap(acted_owner_id) \
		and not _has_playable_apoio(acted_owner_id):
		p["donePlacing"] = true
	if players["player"]["donePlacing"] and players["ai"]["donePlacing"]:
		_resolve_combat()
		return
	active_player = acted_owner_id if players[other]["donePlacing"] else other

func _check_auto_advance(owner_id: String) -> void:
	# Jogar um Apoio/Tático não passa prioridade, mas se o jogador ficou sem
	# jogadas possíveis, marca-o como pronto.
	var p: Dictionary = players[owner_id]
	var has_apoio := _has_playable_apoio(owner_id)
	var has_unit := _has_playable_unit(owner_id)
	if not has_apoio and (p["freeNextUnit"] or int(p["unitPlaysThisRound"]) < get_unit_cap(owner_id)) and has_unit:
		return
	if not has_apoio and not has_unit:
		p["donePlacing"] = true
		if players["player"]["donePlacing"] and players["ai"]["donePlacing"]:
			_resolve_combat()
			return
		active_player = opponent_of(owner_id)

func _has_playable_apoio(owner_id: String) -> bool:
	var p: Dictionary = players[owner_id]
	if p["apoiosBlocked"]:
		return false
	for c in p["hand"]:
		if c.get("isApoio", false):
			return true
	return false

func _has_playable_unit(owner_id: String) -> bool:
	var p: Dictionary = players[owner_id]
	for c in p["hand"]:
		if c.get("isApoio", false):
			continue
		for i in range(FRONT_LANES):
			if can_place_unit(owner_id, c, "frente", i):
				return true
		for i in BACK_LANES:
			if can_place_unit(owner_id, c, "retaguarda", i):
				return true
	return false

# ---------------------------------------------------------------------------
# Dano e morte
# ---------------------------------------------------------------------------

func deal_damage(target, amount: int, source = null, opts: Dictionary = {}) -> void:
	if target == null or amount <= 0:
		return
	if not opts.get("trueDamage", false):
		amount = max(0, amount - int(target.get("tempDamageReduction", 0)) - int(target.get("_laneReduction", 0)))
	if amount <= 0:
		return
	if int(target["escudoAtual"]) > 0:
		var absorb: int = min(int(target["escudoAtual"]), amount)
		target["escudoAtual"] = int(target["escudoAtual"]) - absorb
		amount -= absorb
	if amount <= 0:
		target["tookDamageThisRound"] = true
		return
	target["vidaAtual"] = int(target["vidaAtual"]) - amount
	target["tookDamageThisRound"] = true
	if int(target["vidaAtual"]) <= 0:
		if target.get("cannotDieThisRound", false):
			target["vidaAtual"] = 1
		else:
			destroy_card(target, source)

func destroy_card(card, killer = null) -> void:
	if card == null:
		return
	if card.get("cannotDieThisRound", false):
		card["vidaAtual"] = 1
		return
	var p: Dictionary = players[card["ownerId"]]
	var arr: Array = p["back"] if card["slotType"] == "retaguarda" else p["front"]
	var slot_index = card["slotIndex"]
	if slot_index != null and arr[slot_index] == card:
		arr[slot_index] = null
	p["graveyard"].append(card)
	p["lastDeadCard"] = card
	_log("%s morreu." % card["nome"])

	var def := abilities.get_unit_ability(str(card.get("habilidade_texto", "")))
	if not def.is_empty() and str(def.get("trigger", "")) == "onDeath" and def.has("run"):
		var result = def["run"].call(self, card, null, null)
		if result == "revive":
			p["graveyard"].erase(card)
			p["lastDeadCard"] = null
			card["vidaAtual"] = 1
			card["escudoAtual"] = 0
			if slot_index != null:
				arr[slot_index] = card
			_log("%s volta ao corredor com 1 de Vida." % card["nome"])
			return
	# Handler secundário (algumas cartas têm onDeath além do gatilho principal)
	if not def.is_empty() and def.has("onDeath"):
		def["onDeath"].call(self, card, null, null)

	if killer != null:
		_run_on_kill(killer)
	_emit_ally_death(card)

# ---------------------------------------------------------------------------
# Gatilhos
# ---------------------------------------------------------------------------

func _run_trigger(card: Dictionary, trigger: String) -> void:
	abilities.run_trigger(self, card, trigger, null, null)

func _run_on_kill(card: Dictionary) -> void:
	abilities.run_trigger(self, card, "onKill", null, null)
	abilities.run_secondary(self, card, "onKill", null, null)

func _emit_ally_death(dead_card: Dictionary) -> void:
	for c in allies(dead_card["ownerId"]):
		abilities.run_trigger(self, c, "onAllyDeath", dead_card, null)
		abilities.run_secondary(self, c, "onAllyDeath", dead_card, null)

func _emit_ally_healed(healed_card: Dictionary) -> void:
	for c in allies(healed_card["ownerId"]):
		abilities.run_trigger(self, c, "onAllyHealed", healed_card, null)

func _run_on_attacked(target: Dictionary, attacker: Dictionary) -> void:
	abilities.run_trigger(self, target, "onAttacked", attacker, null)

func activated_ability(owner_id: String, card_uid: String, arg1 = null, arg2 = null) -> Dictionary:
	var card = get_card(card_uid)
	if card == null or card["ownerId"] != owner_id:
		return {"ok": false}
	var def := abilities.get_unit_ability(str(card.get("habilidade_texto", "")))
	if def.is_empty() or str(def.get("trigger", "")) != "activated":
		return {"ok": false}
	def["run"].call(self, card, arg1, arg2)
	return {"ok": true}

# ---------------------------------------------------------------------------
# Ciclo de turno
# ---------------------------------------------------------------------------

func _run_turn_start_triggers() -> void:
	recompute_statics()
	for c in all_in_play():
		c["tookDamageThisRound"] = false
		c["attackedThisRound"] = false
	for c in all_in_play():
		abilities.run_trigger(self, c, "turnStart", null, null)
	for owner_id in ["player", "ai"]:
		var p: Dictionary = players[owner_id]
		p["apoiosBlocked"] = p["apoiosBlockedNextRound"]
		p["apoiosBlockedNextRound"] = false
		p["unitPlaysThisRound"] = 0
		p["donePlacing"] = false

func _resolve_combat() -> void:
	phase = "combat"
	combat_steps = []
	recompute_statics()

	var order := []
	for owner_id in ["player", "ai"]:
		for c in allies(owner_id):
			if c["papel"] == "ASSASSINO" and _can_act(c):
				order.append({"kind": "assassino", "card": c})
	for owner_id in ["player", "ai"]:
		for c in allies(owner_id):
			if c["papel"] == "ATIRADOR" and _can_act(c):
				order.append({"kind": "atirador", "card": c})
	for lane in range(FRONT_LANES):
		for owner_id in ["player", "ai"]:
			var c = players[owner_id]["front"][lane]
			if c != null and _can_act(c) and (c["papel"] == "TANQUE" or c["papel"] == "GUERREIRO"):
				order.append({"kind": "frente", "card": c})

	for step in order:
		var card: Dictionary = step["card"]
		if int(card["vidaAtual"]) <= 0:
			continue
		_resolve_attack(card, str(step["kind"]))

	_end_of_round()

func _can_act(card: Dictionary) -> bool:
	if card["papel"] == "ASSASSINO" or card.get("readyToAttack", false):
		return true
	return int(card["turnosEmCampo"]) > 0

func _rupture_threshold(card: Dictionary) -> int:
	return 3 if players[opponent_of(card["ownerId"])]["hasSombra"] else 2

func _resolve_attack(attacker: Dictionary, kind: String) -> void:
	attacker["attackedThisRound"] = true
	var threshold := _rupture_threshold(attacker)
	if attacker.get("forcedRupture", false) or int(attacker["pressaoMarcas"]) >= threshold:
		attacker["forcedRupture"] = false
		attacker["pressaoMarcas"] = 0
		var dmg := get_effective_ataque(attacker) + get_alignment_atk_bonus(attacker)
		var tower_owner := opponent_of(attacker["ownerId"])
		damage_tower(tower_owner, dmg)
		combat_steps.append({
			"type": "rupture", "attacker": attacker["uid"], "amount": dmg,
			"towerOwner": tower_owner, "towerAfter": towers[tower_owner]
		})
		return

	if kind == "assassino":
		# Ignora a frente inimiga, ataca a retaguarda directamente
		var opp_back: Array = players[opponent_of(attacker["ownerId"])]["back"]
		var target = null
		for i in BACK_LANES:
			var c = opp_back[i]
			if c == null:
				continue
			if target == null or int(c["vidaAtual"]) < int(target["vidaAtual"]):
				target = c
		_strike(attacker, target, true)
		return

	if kind == "atirador":
		_strike(attacker, pick_lowest_vida_enemy_for_combat(attacker["ownerId"]), true)
		return

	# Frente: combate por coluna, progride para a retaguarda e depois a Torre
	var opp: Dictionary = players[opponent_of(attacker["ownerId"])]
	var lane: int = int(attacker["slotIndex"])
	var target = opp["front"][lane]
	if target == null and BACK_LANES.has(lane):
		target = opp["back"][lane]
	_strike(attacker, target, true)

func _strike(attacker: Dictionary, target, siege_if_no_target: bool) -> void:
	if target == null:
		if siege_if_no_target:
			var dmg := get_effective_ataque(attacker) + get_alignment_atk_bonus(attacker)
			var tower_owner := opponent_of(attacker["ownerId"])
			damage_tower(tower_owner, dmg)
			combat_steps.append({
				"type": "siege", "attacker": attacker["uid"], "amount": dmg,
				"towerOwner": tower_owner, "towerAfter": towers[tower_owner]
			})
		return

	_apply_lane_reductions(target)

	var dmg := get_effective_ataque(attacker)
	dmg += get_alignment_atk_bonus(attacker)
	dmg += get_combat_mod_bonus(attacker, target)
	dmg = int(round(float(dmg) * get_matchup_multiplier(attacker, target)))
	dmg = max(0, dmg)

	_run_on_attacked(target, attacker)
	var was_alive := int(target["vidaAtual"]) > 0
	deal_damage(target, dmg, attacker)
	if was_alive and int(target["vidaAtual"]) <= 0:
		_run_on_kill(attacker)
	combat_steps.append({
		"type": "attack", "attacker": attacker["uid"],
		"target": target["uid"], "amount": dmg
	})

func _apply_lane_reductions(target: Dictionary) -> void:
	target["_laneReduction"] = 0
	for c in allies(target["ownerId"]):
		var def := abilities.get_unit_ability(str(c.get("habilidade_texto", "")))
		if def.is_empty():
			continue
		var trigger := str(def.get("trigger", ""))
		var amount := int(def.get("amount", 0))
		if trigger == "damageReductionGlobal":
			target["_laneReduction"] = int(target["_laneReduction"]) + amount
		elif trigger == "damageReductionLane" and _same_lane(c, target):
			target["_laneReduction"] = int(target["_laneReduction"]) + amount
		elif trigger == "damageReductionSelf" and c["uid"] == target["uid"]:
			target["_laneReduction"] = int(target["_laneReduction"]) + amount

func _end_of_round() -> void:
	for c in all_in_play():
		abilities.run_trigger(self, c, "turnEnd", null, null)
		abilities.run_trigger(self, c, "special_countdown", null, null)

	for c in all_in_play():
		c["tempBuffAtk"] = 0
		c["tempDamageReduction"] = 0
		c["_laneReduction"] = 0
		c["_laneDebuffTemp"] = 0
		c["attackedLastRound"] = c["attackedThisRound"]
		c["turnosEmCampo"] = int(c["turnosEmCampo"]) + 1
		if int(c.get("pressureLocked", 0)) > 0:
			c["pressureLocked"] = int(c["pressureLocked"]) - 1
		else:
			add_pressure_mark(c, 1)
		c["cannotDieThisRound"] = false

	# Clima expira
	for owner_id in ["player", "ai"]:
		var active: Array = players[owner_id]["activeTactics"]
		for i in range(active.size() - 1, -1, -1):
			var t: Dictionary = active[i]
			if t.get("tipo_tatico", "") == "Clima":
				t["turnosRestantes"] = int(t.get("turnosRestantes", 0)) - 1
				if int(t["turnosRestantes"]) <= 0:
					active.remove_at(i)

	if _check_win():
		return
	if current_round >= ROUND_LIMIT:
		if int(towers["ai"]) < int(towers["player"]):
			winner = "player"
		elif int(towers["player"]) < int(towers["ai"]):
			winner = "ai"
		else:
			winner = "empate"
		phase = "gameover"
		_log("Limite de turnos atingido. Vencedor: %s." % winner)
		return

	current_round += 1
	active_player = "ai" if current_round % 2 == 0 else "player"
	phase = "placement"
	draw_card("player", 1)
	draw_card("ai", 1)
	_run_turn_start_triggers()

func _check_win() -> bool:
	if int(towers["player"]) <= 0:
		winner = "ai"
		phase = "gameover"
		return true
	if int(towers["ai"]) <= 0:
		winner = "player"
		phase = "gameover"
		return true
	return false

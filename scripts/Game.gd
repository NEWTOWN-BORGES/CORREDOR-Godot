extends RefCounted
class_name Game

# Motor de jogo — CORREDOR (Game Design Bible v1.0)
#
#   - Uma só mão, de 10 cartas: Apoios. Custam 0 e jogar uma não
#     passa a prioridade ao adversário.
#   - O Baralho Militar está oculto. Quando uma unidade morre, ganha-se
#     1 reforço da reserva (máx 5). Um reforço entra em qualquer casa válida
#     livre — é isso que passa a prioridade.
#   - Jogo alternado, até ambos passarem.
#   - Tabuleiro: 6 colunas na Frente (Guerreiro/Tanque/Lanceiro).
#     Retaguarda tem 4 colunas de combate (1-4); as colunas 0 e 5 são baralhos.
#   - Sem custo, mana ou energia. Sem matriz global de tipos.
#   - Cada jogador tem a sua Torre (100 PV). Coluna limpa → ataque à Torre.
#   - 3 Ações Táticas por turno para Arqueiros, Sacerdotes e habilidades ativas.
#   - Ordem de ataque determinada pela ordem de entrada em campo (entryOrder).

# Frente: Guerreiro, Tanque, Lanceiro
const FRONT_ROLES := ["GUERREIRO", "TANQUE", "LANCEIRO"]
# Retaguarda: Assassino, Atirador, Mago, Curador/Sacerdote, Suporte
const BACK_ROLES := ["ASSASSINO", "ATIRADOR", "CURADOR", "MAGO", "SACERDOTE", "SUPORTE"]
const FRONT_LANES := 6
const BACK_LANES := [1, 2, 3, 4]
const TOWER_MAX := 100
const ROUND_LIMIT := 12
const TACTICAL_ACTIONS_PER_TURN := 3

# Sistema de reforços: o Baralho Militar está oculto.
# Sempre que uma unidade é destruída, ganha-se 1 carta da Reserva Militar.
# Capacidade máxima: 5 cartas. Reserva cheia = próximo reforço perde-se.
const MAX_REFORCOS := 5
const REFORCO_POR_TURNO := 1
const REFORCOS_INICIAIS := 3

# A mão é uma só: Apoios. Máximo 4 — a facção com menos Apoios (Despertos) só
# tem 4 no total; um tecto maior nunca seria alcançável para essa facção.
const MAO_MAX := 4

const FAMILY_A := ["ORDEM", "PUREZA"]
const FAMILY_B := ["SELVA", "MAGIA"]

# A Bíblia descartou a tipagem universal: não existe matriz global de
# fraquezas e vantagens. As vantagens específicas vivem nas habilidades das
# cartas — ver os textos que falam de Sombra, Demónio, Metal e Anjo no
# AbilityDispatcher, que continuam a ler o campo `tipo`.

# Estado global
var towers: Dictionary = {"player": TOWER_MAX, "ai": TOWER_MAX}
var current_round: int = 1
var phase: String = "placement"      # placement | combat | gameover
var active_player: String = "player"
var winner: String = ""
var combat_steps: Array = []
# Sobe a cada resolução de combate. A UI usa-o para saber se houve combate
# desde a última jogada — comparar o tamanho de combat_steps não chega,
# porque dois combates seguidos podem ter o mesmo número de passos.
var combat_counter: int = 0
var players: Dictionary = {}

# Ações Táticas por turno (3/turno): usadas para Arqueiros, Sacerdotes, etc.
var tactical_actions: Dictionary = {"player": 0, "ai": 0}

# Contador global de entrada em campo — determina a ordem de ataque.
var _entry_order_counter: int = 0

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

# Cada baralho é o dicionário que o DeckManager devolve: {militar, mao}.
func init_game(player_deck: Dictionary, ai_deck: Dictionary, log_callback: Callable = Callable()) -> void:
	_log_callback = log_callback
	if abilities == null:
		abilities = AbilityDispatcher.new()

	towers = {"player": TOWER_MAX, "ai": TOWER_MAX}
	current_round = 1
	phase = "placement"
	active_player = "player"
	winner = ""
	combat_steps = []

	var player_mil: Array = player_deck.get("militar", [])
	var ai_mil: Array = ai_deck.get("militar", [])

	players = {
		"player": _make_player_state(player_mil, player_deck.get("mao", [])),
		"ai": _make_player_state(ai_mil, ai_deck.get("mao", []))
	}

	# O alinhamento e a coesão lêem-se do Baralho Militar: são as unidades que
	# combatem, e é delas que vêm os bónus.
	players["player"]["hasSombra"] = _deck_has_alignment(player_mil, "SOMBRA")
	players["ai"]["hasSombra"] = _deck_has_alignment(ai_mil, "SOMBRA")
	players["player"]["cohesionBroken"] = _compute_cohesion_broken(player_mil)
	players["ai"]["cohesionBroken"] = _compute_cohesion_broken(ai_mil)

	_setup_start("player")
	_setup_start("ai")
	_run_turn_start_triggers()

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

func _make_player_state(military_deck: Array, hand_deck: Array) -> Dictionary:
	return {
		# Baralho Militar — oculto, larga reforços quando uma unidade morre
		"militaryDeck": _shuffle(military_deck),
		"reinforcements": [],
		"graveyard": [],

		# A única mão: Apoios (máx 10 cartas)
		"deck": _shuffle(hand_deck),
		"hand": [],
		"discard": [],

		# Tabuleiro: Frente 6 slots, Retaguarda 6 slots (0 e 5 são baralhos)
		"front": [null, null, null, null, null, null],
		"back": [null, null, null, null, null, null],
		"activeTactics": [],

		# Estado do turno
		"apoioDoubleNext": false,
		"apoiosBlocked": false,
		"apoiosBlockedNextRound": false,
		"donePlacing": false,
		"lastDeadCard": null,
		"lastApoio": null,
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

func pick_highest_vida_enemy(owner_id: String) -> Variant:
	var best = null
	for c in enemies(owner_id):
		if not _targetable(c, true):
			continue
		if best == null or c["vidaAtual"] > best["vidaAtual"]:
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

# ORDEM dá +1 de Ataque às cartas de topo. Era "custo 3+"; a Bíblia tirou o
# custo do sistema, por isso passa a ser pela raridade — mesma intenção.
const RARIDADES_ALTAS := ["RARA", "ÉPICA", "LENDÁRIA", "HERÓI"]

func get_alignment_atk_bonus(card: Dictionary) -> int:
	if not has_alignment_bonus(card):
		return 0
	if str(card.get("alinhamento", "")) != "ORDEM":
		return 0
	return 1 if RARIDADES_ALTAS.has(str(card.get("raridade", ""))) else 0

func get_combat_mod_bonus(card: Dictionary, defender: Dictionary) -> int:
	var def := abilities.get_unit_ability(str(card.get("habilidade_texto", "")))
	if def.is_empty() or str(def.get("trigger", "")) != "combatMod" or not def.has("run"):
		return 0
	var result = def["run"].call(self, card, defender, null)
	return int(result) if result != null else 0

# ---------------------------------------------------------------------------
# Compra de cartas
# ---------------------------------------------------------------------------

# Enche a mão até MAO_MAX a partir do baralho de Apoios e Táticas.
func refill_hand(owner_id: String) -> void:
	var p: Dictionary = players[owner_id]
	while (p["hand"] as Array).size() < MAO_MAX:
		if (p["deck"] as Array).is_empty():
			break
		p["hand"].append(p["deck"].pop_front())

# Tira n unidades do topo do Baralho Militar para a reserva de reforços.
# Devolve quantas entraram mesmo — a reserva tem tecto, e o que passa perde-se.
func gain_reinforcement(owner_id: String, n: int = 1) -> int:
	var p: Dictionary = players[owner_id]
	var entraram := 0
	for i in range(n):
		if (p["reinforcements"] as Array).size() >= MAX_REFORCOS:
			break
		if (p["militaryDeck"] as Array).is_empty():
			break
		p["reinforcements"].append(p["militaryDeck"].pop_front())
		entraram += 1
	return entraram

# As habilidades com texto de "Energia" continuam a chamar isto. Deixou de
# comprar cartas para a mão: agora chama reforços, que é o que faz sentido
# com o Baralho Militar oculto.
func draw_card(owner_id: String, n: int) -> void:
	gain_reinforcement(owner_id, n)

func reinforcement_count(owner_id: String) -> int:
	return (players[owner_id]["reinforcements"] as Array).size()

func reinforcements_full(owner_id: String) -> bool:
	return reinforcement_count(owner_id) >= MAX_REFORCOS

func _setup_start(owner_id: String) -> void:
	# Arranca com a reserva cheia — o jogador escolhe onde põe as três — e a
	# mão completa.
	gain_reinforcement(owner_id, REFORCOS_INICIAIS)
	refill_hand(owner_id)

# ---------------------------------------------------------------------------
# Mutadores expostos às habilidades
# ---------------------------------------------------------------------------

# Deixou de haver limite de unidades por turno — a reserva é que manda. As
# habilidades que davam mais margem passam a chamar reforços.
func grant_extra_unit_cap(owner_id: String, n: int) -> void:
	gain_reinforcement(owner_id, n)

func grant_free_next_unit(owner_id: String) -> void:
	gain_reinforcement(owner_id, 1)

func get_unit_cap(owner_id: String) -> int:
	return reinforcement_count(owner_id)

func heal_tower(owner_id: String, amount: int) -> void:
	towers[owner_id] = min(TOWER_MAX, int(towers[owner_id]) + amount)
	_log("A Torre de %s recupera %d. (%d/%d)" % [_side_name(owner_id), amount, towers[owner_id], TOWER_MAX])

func damage_tower(target_owner_id: String, amount: int) -> void:
	towers[target_owner_id] = max(0, int(towers[target_owner_id]) - amount)
	_log("A Torre de %s leva %d de dano. (%d/%d)" % [_side_name(target_owner_id), amount, towers[target_owner_id], TOWER_MAX])
	_check_win()

func add_pressure_mark(card: Dictionary, delta: int) -> void:
	if card == null or typeof(card) != TYPE_DICTIONARY:
		return
	card["pressaoMarcas"] = max(0, int(card["pressaoMarcas"]) + delta)

func add_atk_mod(card: Dictionary, delta: int) -> void:
	if card == null or typeof(card) != TYPE_DICTIONARY:
		return
	card["tempBuffAtk"] = int(card["tempBuffAtk"]) + delta

func perm_buff(card: Dictionary, atk: int, vida: int) -> void:
	if card == null or typeof(card) != TYPE_DICTIONARY:
		return
	card["permBuffAtk"] = int(card["permBuffAtk"]) + atk
	card["permBuffVida"] = int(card["permBuffVida"]) + vida
	card["vidaAtual"] = int(card["vidaAtual"]) + vida

func reduce_vida_maxima(card: Dictionary, n: int) -> void:
	if card == null or typeof(card) != TYPE_DICTIONARY:
		return
	card["permVidaMaxLoss"] = int(card["permVidaMaxLoss"]) + n
	card["vidaMaxima"] = get_vida_maxima(card)
	if card["vidaAtual"] > card["vidaMaxima"]:
		card["vidaAtual"] = card["vidaMaxima"]

func add_shield(card, n: int) -> void:
	if card == null or typeof(card) != TYPE_DICTIONARY:
		return
	card["escudoAtual"] = int(card["escudoAtual"]) + n

func heal(card, n: int) -> void:
	if card == null or typeof(card) != TYPE_DICTIONARY:
		return
	if int(card["vidaAtual"]) <= 0 or card.get("cannotBeHealed", false):
		return
	card["vidaAtual"] = min(int(card["vidaMaxima"]), int(card["vidaAtual"]) + n)
	_emit_ally_healed(card)

func clear_negative_effects(card) -> void:
	if card == null or typeof(card) != TYPE_DICTIONARY:
		return
	card["tempBuffAtk"] = max(0, int(card["tempBuffAtk"]))
	card["pressureLocked"] = 0
	card["_laneDebuffTemp"] = 0

func move_card(card, slot_type: String, slot_index: int) -> void:
	if card == null or typeof(card) != TYPE_DICTIONARY:
		return
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

func force_rupture(card) -> void:
	if card == null or typeof(card) != TYPE_DICTIONARY:
		return
	card["forcedRupture"] = true

# AP-26: o último morto volta — agora à reserva de reforços, não à mão.
func return_last_dead_to_hand(owner_id: String) -> void:
	var p: Dictionary = players[owner_id]
	var last = p["lastDeadCard"]
	if last == null:
		return
	if (p["reinforcements"] as Array).size() >= MAX_REFORCOS:
		_log("A reserva está cheia — %s não volta." % last["nome"])
		return
	# Volta como definição de carta, não como a instância gasta que morreu
	p["reinforcements"].append({
		"id": last.get("cardId", ""),
		"nome": last.get("nome", ""),
		"faccao_slug": last.get("faccao_slug", ""),
		"subgrupo": last.get("subgrupo", ""),
		"tipo": last.get("tipo", []),
		"papel": last.get("papel", ""),
		"alinhamento": last.get("alinhamento", ""),
		"raridade": last.get("raridade", ""),
		"custo": last.get("custo", 0),
		"imagem": last.get("imagem", ""),
		"habilidade_nome": last.get("habilidade_nome", ""),
		"habilidade_texto": last.get("habilidade_texto", ""),
		"lore": last.get("lore", ""),
		"ataque": last.get("baseAtaque", 0),
		"vida": last.get("baseVida", 1),
		"escudo": 0,
		"isApoio": false
	})
	p["lastDeadCard"] = null
	_log("%s volta à reserva." % last["nome"])

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
		# Ordem de entrada em campo — determina a ordem de ataque na Bible v1.0
		"entryOrder": 0,
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

# A casa serve para este papel, está dentro do tabuleiro e está livre.
# Deixou de haver limite por turno: o que trava é a reserva ter ou não cartas.
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
	return arr[slot_index] == null

# Põe em campo um reforço da reserva. Substitui o antigo play_unit.
func place_reinforcement(owner_id: String, index: int, slot_type: String, slot_index: int) -> Dictionary:
	if phase != "placement" or active_player != owner_id:
		return {"ok": false, "error": "não é a tua vez"}
	var p: Dictionary = players[owner_id]
	var reserva: Array = p["reinforcements"]
	if index < 0 or index >= reserva.size():
		return {"ok": false, "error": "reforço inválido"}

	var card_def: Dictionary = reserva[index]
	if not can_place_unit(owner_id, card_def, slot_type, slot_index):
		return {"ok": false, "error": "jogada inválida"}

	reserva.remove_at(index)
	var card := _instantiate(card_def, owner_id)
	card["slotType"] = slot_type
	card["slotIndex"] = slot_index
	# Regista a ordem de entrada em campo (Bible v1.0: ordem de ataque)
	_entry_order_counter += 1
	card["entryOrder"] = _entry_order_counter
	var arr: Array = p["front"] if slot_type == "frente" else p["back"]
	arr[slot_index] = card

	_log("%s chamaste %s ao corredor." % [_side_name(owner_id), card["nome"]])
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
# Mão — Apoios e Táticas pela mesma porta
# ---------------------------------------------------------------------------

# Uma carta da mão é ou Apoio ou Tática. Esta é a única porta de entrada;
# play_apoio e play_tatico_card ficam como invólucros para quem já os chamava.
func play_hand_card(owner_id: String, hand_index: int, target_spec: Dictionary = {}) -> Dictionary:
	if phase != "placement" or active_player != owner_id:
		return {"ok": false, "error": "não é a tua vez"}
	var p: Dictionary = players[owner_id]
	if hand_index < 0 or hand_index >= (p["hand"] as Array).size():
		return {"ok": false, "error": "carta inválida"}

	var card_def: Dictionary = p["hand"][hand_index]
	if card_def.get("isApoio", false):
		return _resolve_apoio(owner_id, hand_index, card_def, target_spec)
	return _resolve_tatico(owner_id, hand_index, card_def, target_spec)

func play_apoio(owner_id: String, hand_index: int, target_spec: Dictionary = {}) -> Dictionary:
	return play_hand_card(owner_id, hand_index, target_spec)

func _resolve_apoio(owner_id: String, hand_index: int, card_def: Dictionary, target_spec: Dictionary) -> Dictionary:
	var p: Dictionary = players[owner_id]
	if p["apoiosBlocked"]:
		return {"ok": false, "error": "apoios bloqueados este turno"}

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

	# O Apoio resolve-se e sai para a zona de Apoio, onde fica visível.
	p["lastApoio"] = card_def
	p["discard"].append(card_def)

	refill_hand(owner_id)
	_log("%s jogaste o Apoio %s." % [_side_name(owner_id), card_def.get("nome", "")])
	_check_auto_advance(owner_id)
	return {"ok": true, "card": card_def}

# ---------------------------------------------------------------------------
# Cartas táticas
# ---------------------------------------------------------------------------

func play_tatico_card(owner_id: String, hand_index: int, target_spec: Dictionary = {}) -> Dictionary:
	return play_hand_card(owner_id, hand_index, target_spec)

func _resolve_tatico(owner_id: String, hand_index: int, card_def: Dictionary, target_spec: Dictionary) -> Dictionary:
	var p: Dictionary = players[owner_id]
	var tipo := str(card_def.get("tipo_tatico", ""))

	if tipo == "Equipamento":
		var target_card = target_spec.get("targetCard")
		if target_card == null:
			return {"ok": false, "error": "escolhe uma unidade para equipar", "needsTarget": "card"}
		if target_card["ownerId"] != owner_id:
			return {"ok": false, "error": "só podes equipar unidades amigas"}

		p["hand"].remove_at(hand_index)
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
		refill_hand(owner_id)
		_check_auto_advance(owner_id)
		return {"ok": true, "card": card_def, "target": target_card}

	p["hand"].remove_at(hand_index)
	refill_hand(owner_id)

	# Magia, Consumível e Bênção aceitam alvo. Sem alvo, caem no primeiro da
	# lista — que era o único comportamento no web.
	var escolhido = target_spec.get("targetCard")

	match tipo:
		"Magia":
			var dano := int(card_def.get("dano", 0))
			if dano > 0:
				var alvo = escolhido
				if alvo == null:
					var foes := enemies(owner_id)
					alvo = foes[0] if not foes.is_empty() else null
				if alvo != null and alvo["ownerId"] != owner_id:
					deal_damage(alvo, dano, null)
					_log("%s lançaste %s em %s (%d de dano)." % [
						_side_name(owner_id), card_def.get("nome", ""), alvo["nome"], dano])
			p["discard"].append(card_def)
		"Consumível":
			var cura := int(card_def.get("cura", 0))
			if cura > 0:
				var alvo = escolhido
				if alvo == null:
					var friends := allies(owner_id)
					alvo = friends[0] if not friends.is_empty() else null
				if alvo != null and alvo["ownerId"] == owner_id:
					var old_hp := int(alvo["vidaAtual"])
					heal(alvo, cura)
					_log("%s usaste %s em %s (+%d de Vida)." % [
						_side_name(owner_id), card_def.get("nome", ""), alvo["nome"],
						int(alvo["vidaAtual"]) - old_hp])
			p["discard"].append(card_def)
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
			var alvo = escolhido
			if alvo == null:
				var friends_b := allies(owner_id)
				alvo = friends_b[0] if not friends_b.is_empty() else null
			if alvo != null and alvo["ownerId"] == owner_id:
				add_atk_mod(alvo, 2)
				_log("%s invocaste %s em %s (+2 de Ataque)." % [
					_side_name(owner_id), card_def.get("nome", ""), alvo["nome"]])
			p["discard"].append(card_def)
		_:
			_log("%s jogaste %s." % [_side_name(owner_id), card_def.get("nome", "")])

	_check_auto_advance(owner_id)
	return {"ok": true, "card": card_def}

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
	if not _has_playable_unit(acted_owner_id) and not _has_playable_hand_card(acted_owner_id):
		p["donePlacing"] = true
	if players["player"]["donePlacing"] and players["ai"]["donePlacing"]:
		_resolve_combat()
		return
	active_player = acted_owner_id if players[other]["donePlacing"] else other

func _check_auto_advance(owner_id: String) -> void:
	# Jogar uma carta da mão não passa prioridade, mas se o jogador ficou sem
	# jogadas possíveis, marca-o como pronto.
	var p: Dictionary = players[owner_id]
	if _has_playable_hand_card(owner_id) or _has_playable_unit(owner_id):
		return
	p["donePlacing"] = true
	if players["player"]["donePlacing"] and players["ai"]["donePlacing"]:
		_resolve_combat()
		return
	active_player = opponent_of(owner_id)

# Há alguma carta na mão que se possa jogar agora?
func _has_playable_hand_card(owner_id: String) -> bool:
	var p: Dictionary = players[owner_id]
	for c in p["hand"]:
		if c.get("isApoio", false):
			if not p["apoiosBlocked"]:
				return true
			continue
		# Equipamento sem unidade amiga em campo não tem onde ir
		if str(c.get("tipo_tatico", "")) == "Equipamento":
			if not allies(owner_id).is_empty():
				return true
			continue
		return true
	return false

# Mantido pelo nome antigo, mas agora olha para a reserva de reforços.
func _has_playable_apoio(owner_id: String) -> bool:
	return _has_playable_hand_card(owner_id)

# Há algum reforço na reserva com casa livre para entrar?
func _has_playable_unit(owner_id: String) -> bool:
	var p: Dictionary = players[owner_id]
	for c in p["reinforcements"]:
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

	# Bible v1.0: quando uma unidade morre, o dono ganha +1 reforço (até máx 5)
	gain_reinforcement(card["ownerId"], 1)

	var def := abilities.get_unit_ability(str(card.get("habilidade_texto", "")))
	if not def.is_empty() and str(def.get("trigger", "")) == "onDeath" and def.has("run"):
		var result = def["run"].call(self, card, null, null)
		# A habilidade "uma vez por partida volta com 1 de Vida" devolve false
		# na segunda morte. Comparar bool com String é erro em GDScript, por
		# isso confirma-se o tipo antes.
		if typeof(result) == TYPE_STRING and str(result) == "revive":
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
		p["donePlacing"] = false
	# Repor ações táticas no início de cada turno (Bible v1.0: 3/turno)
	tactical_actions["player"] = TACTICAL_ACTIONS_PER_TURN
	tactical_actions["ai"] = TACTICAL_ACTIONS_PER_TURN

func _resolve_combat() -> void:
	phase = "combat"
	combat_steps = []
	combat_counter += 1
	recompute_statics()

	# Bible v1.0: ordem de ataque determinada por entryOrder (ordem de entrada em campo)
	# Sacerdotes não atacam automaticamente (usam Ações Táticas).
	var todos := []
	for owner_id in ["player", "ai"]:
		for c in allies(owner_id):
			var papel := str(c.get("papel", ""))
			# Sacerdote/Suporte não participam no combate automático
			if papel == "SACERDOTE" or papel == "SUPORTE":
				continue
			if not _can_act(c):
				continue
			todos.append(c)

	# Ordenar por entryOrder (quem entrou primeiro, ataca primeiro)
	todos.sort_custom(func(a, b): return int(a.get("entryOrder", 0)) < int(b.get("entryOrder", 0)))

	for card in todos:
		if int(card["vidaAtual"]) <= 0:
			continue
		var papel := str(card.get("papel", ""))
		var kind: String
		match papel:
			"ASSASSINO": kind = "assassino"
			"ATIRADOR": kind = "atirador"
			"LANCEIRO": kind = "lanceiro"
			"MAGO": kind = "mago"
			_: kind = "frente"
		_resolve_attack(card, kind)

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
		# Assassino: ataca prioritariamente a Retaguarda na mesma coluna (Bible v1.0)
		var opp_back: Array = players[opponent_of(attacker["ownerId"])]["back"]
		var opp_front: Array = players[opponent_of(attacker["ownerId"])]["front"]
		var lane := int(attacker["slotIndex"])
		var target = null
		# Tenta a mesma coluna na retaguarda
		if BACK_LANES.has(lane) and opp_back[lane] != null:
			target = opp_back[lane]
		else:
			# Sem alvo na retaguarda da coluna, encontra qualquer unidade de retaguarda
			for i in BACK_LANES:
				if opp_back[i] != null:
					if target == null or int(opp_back[i]["vidaAtual"]) < int(target["vidaAtual"]):
						target = opp_back[i]
			# Se não houver retaguarda, ataca a frente na mesma coluna (fallback)
			if target == null:
				target = opp_front[lane]
		_strike(attacker, target, true)
		return

	if kind == "atirador":
		# Atirador: pode atacar qualquer unidade (usa Ação Tática no turno real)
		_strike(attacker, pick_lowest_vida_enemy_for_combat(attacker["ownerId"]), true)
		return

	if kind == "lanceiro":
		# Lanceiro: ataca a Retaguarda na mesma coluna (Bible v1.0)
		# Se não houver retaguarda e só houver Torre, o dano excedente atinge a Torre.
		var opp: Dictionary = players[opponent_of(attacker["ownerId"])]
		var lane := int(attacker["slotIndex"])
		var target = null
		if BACK_LANES.has(lane):
			target = opp["back"][lane]
		if target == null:
			# Não há retaguarda na coluna: dano excedente vai para a Torre
			_strike(attacker, null, true)
		else:
			_strike(attacker, target, true)
		return

	if kind == "mago":
		# Mago: ignora linha de visão, escolhe o alvo mais perigoso (maior ataque)
		_strike(attacker, pick_highest_ataque_enemy(attacker["ownerId"]), true)
		return

	# Frente (Guerreiro/Tanque): combate por coluna, progride para a retaguarda e depois a Torre
	var opp_f: Dictionary = players[opponent_of(attacker["ownerId"])]
	var flane: int = int(attacker["slotIndex"])
	var ftarget = opp_f["front"][flane]
	if ftarget == null and BACK_LANES.has(flane):
		ftarget = opp_f["back"][flane]
	_strike(attacker, ftarget, true)

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

	# Sem matriz de tipos: ataque efectivo + alinhamento + o que a habilidade
	# da própria carta acrescentar contra este defensor.
	var dmg := get_effective_ataque(attacker)
	dmg += get_alignment_atk_bonus(attacker)
	dmg += get_combat_mod_bonus(attacker, target)
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

	# O Baralho Militar larga o reforço do turno; se a reserva estiver cheia,
	# perde-se. E a mão volta a encher-se.
	for owner_id in ["player", "ai"]:
		var ganhos := gain_reinforcement(owner_id, REFORCO_POR_TURNO)
		if ganhos == 0 and reinforcements_full(owner_id):
			_log("A reserva de %s está cheia — o reforço do turno perdeu-se." % _side_name(owner_id))
		refill_hand(owner_id)

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

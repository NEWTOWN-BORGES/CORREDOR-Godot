extends RefCounted
class_name AIPlayer

# Adversário automático — tradução de js/ai-player.js.
#
# Heurística simples, a mesma do web:
#   - joga Apoios primeiro (não gastam a jogada de unidade)
#   - depois a melhor unidade da mão, avaliada por ataque×2 + vida + escudo
#   - prefere as colunas do centro para fora
#   - se não tiver nada a fazer, passa

var owner_id: String = "ai"

func _init(a_owner_id: String = "ai") -> void:
	owner_id = a_owner_id

# ---------------------------------------------------------------- avaliação

func score_unit(card_def: Dictionary) -> float:
	return float(card_def.get("ataque", 0)) * 2.0 \
		+ float(card_def.get("vida", 0)) \
		+ float(card_def.get("escudo", 0)) \
		- float(card_def.get("custo", 0)) * 0.2

# Do centro do tabuleiro para fora. A retaguarda só usa as colunas de
# combate (1-4); as pontas são de Apoio.
func slot_order(is_front: bool) -> Array:
	return [2, 3, 1, 4, 0, 5] if is_front else [2, 3, 1, 4]

func find_open_slot(engine: Game, card_def: Dictionary) -> Dictionary:
	var is_front: bool = Game.FRONT_ROLES.has(str(card_def.get("papel", "")))
	var slot_type := "frente" if is_front else "retaguarda"
	for i in slot_order(is_front):
		if engine.can_place_unit(owner_id, card_def, slot_type, i):
			return {"slotType": slot_type, "slotIndex": i}
	return {}

# ---------------------------------------------------------------- alvos

func pick_apoio_target(engine: Game, def: Dictionary, apoio_id: String) -> Dictionary:
	var allies: Array = engine.allies(owner_id)
	var foes: Array = engine.enemies(owner_id)

	var most_wounded = engine.pick_most_wounded_ally(owner_id)

	var strongest_ally = null
	for c in allies:
		if strongest_ally == null or engine.get_effective_ataque(c) > engine.get_effective_ataque(strongest_ally):
			strongest_ally = c

	var threat = null
	for c in foes:
		if threat == null or engine.get_effective_ataque(c) > engine.get_effective_ataque(threat):
			threat = c

	var killable = null
	for c in foes:
		if int(c["vidaAtual"]) <= 2:
			if killable == null or int(c["vidaAtual"]) < int(killable["vidaAtual"]):
				killable = c

	match apoio_id:
		"AP-10":
			# Remate: só serve se houver alguém a 2 de Vida ou menos
			return {"target": killable} if killable != null else {}
		"AP-15", "AP-19", "AP-20", "AP-22":
			return {"target": threat} if threat != null else {}
		"AP-17":
			# Transfusão: tira ao mais são e dá ao mais ferido
			if allies.size() < 2:
				return {}
			var ordenados := allies.duplicate()
			ordenados.sort_custom(func(a, b): return int(a["vidaAtual"]) > int(b["vidaAtual"]))
			return {"from": ordenados[0], "to": ordenados[ordenados.size() - 1]}
		"AP-21":
			# Sacrifício: só vale a pena com mais do que uma carta em campo
			if allies.size() <= 1:
				return {}
			var mais_fraco = allies[0]
			for c in allies:
				if int(c["vidaAtual"]) < int(mais_fraco["vidaAtual"]):
					mais_fraco = c
			return {"target": mais_fraco}
		"AP-14":
			return {"target": strongest_ally} if strongest_ally != null else {}
		_:
			var precisa = def.get("needsTarget")
			if precisa == "ally":
				return {"target": most_wounded} if most_wounded != null else {}
			if precisa == "enemy":
				return {"target": threat} if threat != null else {}
			return {}

# ---------------------------------------------------------------- decisões

# Uma única acção, para a UI poder animar jogada a jogada em vez de despejar
# o turno inteiro de uma vez.
func step(engine: Game) -> bool:
	if engine.phase != "placement" or engine.active_player != owner_id:
		return false
	if not _try_play_apoio(engine) and not _try_play_unit(engine):
		engine.pass_turn(owner_id)
	return true

# Turno inteiro de uma vez (útil para simulações e testes).
func act(engine: Game) -> void:
	var guard := 0
	while engine.phase == "placement" and engine.active_player == owner_id and guard < 30:
		guard += 1
		if not _try_play_apoio(engine) and not _try_play_unit(engine):
			engine.pass_turn(owner_id)

func _try_play_apoio(engine: Game) -> bool:
	var p: Dictionary = engine.players[owner_id]
	if p["apoiosBlocked"]:
		return false

	var idx := -1
	for i in range((p["hand"] as Array).size()):
		if p["hand"][i].get("isApoio", false):
			idx = i
			break
	if idx < 0:
		return false

	var card_def: Dictionary = p["hand"][idx]
	var def := engine.abilities.get_apoio_ability(str(card_def.get("id", "")))
	if def.is_empty():
		return false

	if def.get("needsTarget") == null:
		return engine.play_apoio(owner_id, idx, {}).get("ok", false)

	var spec := pick_apoio_target(engine, def, str(card_def.get("id", "")))
	if spec.is_empty():
		return false
	if def.get("needsTarget") != "allyPair" and spec.get("target") == null:
		return false
	if def.has("requireFn") and spec.get("target") != null:
		if not def["requireFn"].call(engine, owner_id, spec["target"]):
			return false

	return engine.play_apoio(owner_id, idx, spec).get("ok", false)

func _try_play_unit(engine: Game) -> bool:
	var p: Dictionary = engine.players[owner_id]
	if not p["freeNextUnit"] and int(p["unitPlaysThisRound"]) >= engine.get_unit_cap(owner_id):
		return false

	# Só as que têm casa livre, pela melhor pontuação
	var candidatos := []
	for i in range((p["hand"] as Array).size()):
		var c: Dictionary = p["hand"][i]
		if c.get("isApoio", false):
			continue
		if find_open_slot(engine, c).is_empty():
			continue
		candidatos.append({"index": i, "card": c, "score": score_unit(c)})

	if candidatos.is_empty():
		return false

	candidatos.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var melhor: Dictionary = candidatos[0]
	var slot := find_open_slot(engine, melhor["card"])
	if slot.is_empty():
		return false

	return engine.play_unit(owner_id, int(melhor["index"]), str(slot["slotType"]), int(slot["slotIndex"])).get("ok", false)

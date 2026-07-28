extends RefCounted
class_name AIPlayer

# Adversário automático — tradução de js/ai-player.js.
#
# Heurística simples, a mesma do web:
#   - joga Apoios primeiro (não gastam a jogada de unidade)
#   - depois a melhor unidade da mão, avaliada por ataque×2 + vida + escudo
#   - prefere as colunas do centro para fora
#   - se não tiver nada a fazer, passa
#
# Acrescento ao web: as cartas táticas. O ai-player.js nunca lhes toca,
# porque o sistema tático foi acrescentado depois. Aqui a IA usa-as, mas só
# quando valem alguma coisa — nunca as gasta a esmo.

const MAX_TATICAS_POR_TURNO := 2

var owner_id: String = "ai"

# Jogar uma tática repõe logo a mão, por isso sem um travão a IA podia
# esvaziar o baralho tático inteiro num só turno.
var _taticas_neste_turno: int = 0
var _turno_contado: int = -1

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
	_reset_turn_counter(engine)
	if not _try_play_hand_card(engine) and not _try_place_reinforcement(engine):
		engine.pass_turn(owner_id)
	return true

# Turno inteiro de uma vez (útil para simulações e testes).
func act(engine: Game) -> void:
	var guard := 0
	while engine.phase == "placement" and engine.active_player == owner_id and guard < 30:
		guard += 1
		_reset_turn_counter(engine)
		if not _try_play_hand_card(engine) and not _try_place_reinforcement(engine):
			engine.pass_turn(owner_id)

func _reset_turn_counter(engine: Game) -> void:
	if engine.current_round != _turno_contado:
		_turno_contado = engine.current_round
		_taticas_neste_turno = 0

# Esquece o que foi jogado neste turno. Em jogo isto acontece sozinho quando
# o turno muda; os testes montam cenários no mesmo turno e precisam de pedir.
func reset_turn_state() -> void:
	_taticas_neste_turno = 0
	_turno_contado = -1

# A mão é uma só, por isso há uma só varredura: percorre-a e joga a primeira
# carta que valha a pena, seja Apoio ou Tática.
func _try_play_hand_card(engine: Game) -> bool:
	var p: Dictionary = engine.players[owner_id]
	var mao: Array = p["hand"]

	for i in range(mao.size()):
		var carta: Dictionary = mao[i]

		if carta.get("isApoio", false):
			if p["apoiosBlocked"]:
				continue
			var spec := _plan_apoio(engine, carta)
			if spec.is_empty() and not _apoio_dispensa_alvo(engine, carta):
				continue
			if engine.play_hand_card(owner_id, i, spec).get("ok", false):
				return true
			continue

		# Táticas têm travão próprio: jogar uma repõe logo a mão, e sem
		# travão a IA esvaziava o baralho inteiro num turno.
		if _taticas_neste_turno >= MAX_TATICAS_POR_TURNO:
			continue
		var plano := plan_tatico(engine, carta)
		if plano.is_empty():
			continue
		var tspec := {}
		if plano.has("target"):
			tspec["targetCard"] = plano["target"]
		if engine.play_hand_card(owner_id, i, tspec).get("ok", false):
			_taticas_neste_turno += 1
			return true

	return false

func _apoio_dispensa_alvo(engine: Game, carta: Dictionary) -> bool:
	var def := engine.abilities.get_apoio_ability(str(carta.get("id", "")))
	return not def.is_empty() and def.get("needsTarget") == null

# Escolhe o alvo de um Apoio, ou devolve vazio se nenhum servir.
func _plan_apoio(engine: Game, carta: Dictionary) -> Dictionary:
	var apoio_id := str(carta.get("id", ""))
	var def := engine.abilities.get_apoio_ability(apoio_id)
	if def.is_empty():
		return {}
	if def.get("needsTarget") == null:
		return {}

	var spec := pick_apoio_target(engine, def, apoio_id)
	if spec.is_empty():
		return {}
	if def.get("needsTarget") != "allyPair" and spec.get("target") == null:
		return {}
	if def.has("requireFn") and spec.get("target") != null:
		if not def["requireFn"].call(engine, owner_id, spec["target"]):
			return {}
	return spec

# ---------------------------------------------------------------- táticas

# Decide se uma tática vale a pena agora e em quem. Dicionário vazio = não joga.
func plan_tatico(engine: Game, carta: Dictionary) -> Dictionary:
	match str(carta.get("tipo_tatico", "")):
		"Equipamento":
			return _plan_equipamento(engine, carta)
		"Magia":
			return _plan_magia(engine, carta)
		"Consumível":
			return _plan_consumivel(engine, carta)
		"Bênção":
			return _plan_bencao(engine, carta)
		_:
			# Construção e Clima ainda não têm efeito nenhum no motor — no web
			# também não tinham. Não vale a pena gastar jogadas com elas.
			return {}

# Equipamento vai para quem mais lucra: bónus de ataque no que bate mais
# forte, bónus de vida no que está mais perto de cair.
func _plan_equipamento(engine: Game, carta: Dictionary) -> Dictionary:
	var bonus_atk := int(carta.get("bonus_ataque", 0))
	var bonus_vida := int(carta.get("bonus_vida", 0))
	if bonus_atk <= 0 and bonus_vida <= 0:
		return {}

	var candidatos: Array = engine.allies(owner_id)
	if candidatos.is_empty():
		return {}

	var melhor = null
	var melhor_valor := -1.0
	for c in candidatos:
		var valor := 0.0
		if bonus_atk > 0:
			# Quem já bate forte tira mais partido de bater ainda mais
			valor += float(bonus_atk) * (1.0 + float(engine.get_effective_ataque(c)) * 0.25)
		if bonus_vida > 0:
			# E quem está ferido tira mais partido de aguentar mais
			var falta: int = max(0, int(c["vidaMaxima"]) - int(c["vidaAtual"]))
			valor += float(bonus_vida) * (1.0 + float(falta) * 0.5)
		if valor > melhor_valor:
			melhor_valor = valor
			melhor = c

	return {"target": melhor} if melhor != null else {}

# Magia procura primeiro um remate; se não houver, bate no mais perigoso.
func _plan_magia(engine: Game, carta: Dictionary) -> Dictionary:
	var dano := int(carta.get("dano", 0))
	if dano <= 0:
		return {}

	var foes: Array = engine.enemies(owner_id)
	if foes.is_empty():
		return {}

	var remate = null
	var remate_ataque := -1
	var perigo = null
	for c in foes:
		var aguenta := int(c["vidaAtual"]) + int(c["escudoAtual"])
		var ataque := engine.get_effective_ataque(c)
		if dano >= aguenta and ataque > remate_ataque:
			remate = c
			remate_ataque = ataque
		if perigo == null or ataque > engine.get_effective_ataque(perigo):
			perigo = c

	if remate != null:
		return {"target": remate}
	return {"target": perigo} if perigo != null else {}

# Consumível só sai se houver mesmo vida para repor — curar 2 numa carta a
# quem falta 1 é deitar a carta fora.
func _plan_consumivel(engine: Game, carta: Dictionary) -> Dictionary:
	var cura := int(carta.get("cura", 0))
	if cura <= 0:
		return {}

	var melhor = null
	var maior_falta := 0
	for c in engine.allies(owner_id):
		if c.get("cannotBeHealed", false):
			continue
		var falta: int = int(c["vidaMaxima"]) - int(c["vidaAtual"])
		if falta > maior_falta:
			maior_falta = falta
			melhor = c

	# Exige que se aproveite pelo menos metade da cura
	if melhor == null or maior_falta * 2 < cura:
		return {}
	return {"target": melhor}

# Bênção dá +2 de Ataque só até ao fim do turno, por isso só serve numa
# carta que vá mesmo atacar já.
func _plan_bencao(engine: Game, _carta: Dictionary) -> Dictionary:
	var melhor = null
	for c in engine.allies(owner_id):
		if not engine._can_act(c):
			continue
		if melhor == null or engine.get_effective_ataque(c) > engine.get_effective_ataque(melhor):
			melhor = c
	return {"target": melhor} if melhor != null else {}

# ---------------------------------------------------------------- reforços

# A decisão nova do sistema: gastar um reforço agora ou guardá-lo.
#
# Gasta se houver coluna da frente aberta — uma coluna vazia deixa a Torre
# levar cerco directo, e isso custa mais do que qualquer carta guardada.
# Gasta também se a reserva estiver cheia, senão o reforço do próximo turno
# perde-se. Fora disso guarda, para ter resposta quando algo morrer.
func should_spend_reinforcement(engine: Game) -> bool:
	if engine.reinforcements_full(owner_id):
		return true
	return _has_open_front_lane(engine)

func _has_open_front_lane(engine: Game) -> bool:
	var frente: Array = engine.players[owner_id]["front"]
	for lane in range(Game.FRONT_LANES):
		if frente[lane] == null:
			return true
	return false

func _try_place_reinforcement(engine: Game) -> bool:
	var p: Dictionary = engine.players[owner_id]
	var reserva: Array = p["reinforcements"]
	if reserva.is_empty():
		return false
	if not should_spend_reinforcement(engine):
		return false

	# Entre os que têm casa livre, o mais forte
	var candidatos := []
	for i in range(reserva.size()):
		var c: Dictionary = reserva[i]
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

	return engine.place_reinforcement(
		owner_id, int(melhor["index"]), str(slot["slotType"]), int(slot["slotIndex"])
	).get("ok", false)

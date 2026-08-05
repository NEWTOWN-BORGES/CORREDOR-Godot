extends RefCounted
class_name AbilityDispatcher

# Motor de habilidades — CORREDOR (tradução 1:1 de js/ability-engine.js)
#
# Mapeia os 86 textos distintos de habilidade de unidade e os 27 efeitos de
# Apoio para funções executáveis. A arte das cartas já tem o texto impresso,
# por isso as chaves têm de bater certo com o que está desenhado — incluindo
# textos antigos que mencionam "Energia" e "Nexus".
#
# Remapeamento de mecânicas descontinuadas:
#   "ganha(s) X de Energia"            -> compra X carta(s)
#   "custa(m) -N de Energia"           -> não conta para o limite de unidades
#   "cura X ao teu Nexus"              -> cura a Torre do dono
#   "causa X de dano ao Nexus inimigo" -> dano à Torre inimiga
#
# Convenção de assinaturas (fixa, sem parâmetros opcionais):
#   unidade  run(engine, card, extra, extra2)
#   apoio    run(engine, owner_id, target, extra)
#   requisito requireFn(engine, owner_id, target)

var UNIT_ABILITIES: Dictionary = {}
var APOIO_ABILITIES: Dictionary = {}

func _init() -> void:
	_setup_unit_abilities()
	_setup_apoio_abilities()

func _unit(text: String, def: Dictionary) -> void:
	UNIT_ABILITIES[text] = def

func _apoio(id: String, def: Dictionary) -> void:
	APOIO_ABILITIES[id] = def

# ---------------------------------------------------------------------------
# Unidades
# ---------------------------------------------------------------------------

func _setup_unit_abilities() -> void:

	_unit("Ganha +1 de Ataque por cada outro Guerreiro em jogo.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			var n := 0
			for c in engine.allies(card["ownerId"]):
				if c["papel"] == "GUERREIRO" and c["uid"] != card["uid"]:
					n += 1
			card["staticBonusAtk"] += n
	})

	_unit("Reduz 1 de dano a todas as tuas cartas neste corredor.", {
		"trigger": "damageReductionLane",
		"amount": 1
	})

	_unit("Ao entrar, cura 2 a todas as tuas cartas.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			for a in engine.allies(card["ownerId"]):
				engine.heal(a, 2)
	})

	_unit("Se não levou dano este turno, ganha +2 de Ataque.", {
		"trigger": "combatMod",
		"run": func(_engine, card, _defender, _y):
			return 0 if card["tookDamageThisRound"] else 2
	})

	_unit("No início de cada turno, dá −1 de Ataque a uma carta inimiga.", {
		"trigger": "turnStart",
		"run": func(engine, card, _x, _y):
			var t = engine.pick_highest_ataque_enemy(card["ownerId"])
			if t != null:
				engine.add_atk_mod(t, -1)
	})

	_unit("Sempre que uma carta tua morre, cura 2 ao teu Nexus.", {
		"trigger": "onAllyDeath",
		"run": func(engine, card, _dead, _y):
			engine.heal_tower(card["ownerId"], 2)
	})

	_unit("Ao matar uma carta inimiga, ganhas 1 de Energia.", {
		"trigger": "onKill",
		"run": func(engine, card, _x, _y):
			engine.draw_card(card["ownerId"], 1)
	})

	_unit("As tuas cartas custam −1 de Energia (mínimo 1). Ao entrar, ganhas 2 de Energia.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			engine.grant_extra_unit_cap(card["ownerId"], 1)
			engine.draw_card(card["ownerId"], 2)
	})

	_unit("Todos os teus Guerreiros ganham +1/+1. Quando o Muro morre, o bónus mantém-se até ao fim.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			for c in engine.allies(card["ownerId"]):
				if c["papel"] == "GUERREIRO":
					engine.perm_buff(c, 1, 1)
	})

	_unit("Ganha +1 de Vida por cada outro Guerreiro em jogo.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			var n := 0
			for c in engine.allies(card["ownerId"]):
				if c["papel"] == "GUERREIRO" and c["uid"] != card["uid"]:
					n += 1
			card["staticBonusVida"] += n
	})

	_unit("Ao entrar, dá +1 de Vida a todos os teus Guerreiros.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			for c in engine.allies(card["ownerId"]):
				if c["papel"] == "GUERREIRO":
					engine.perm_buff(c, 0, 1)
	})

	_unit("Os teus Guerreiros custam −1 de Energia (mínimo 1).", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			engine.grant_extra_unit_cap(card["ownerId"], 1)
	})

	_unit("Ao entrar, ganhas 1 de Energia.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			engine.draw_card(card["ownerId"], 1)
	})

	_unit("Ao entrar, cura 3 ao teu Nexus.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			engine.heal_tower(card["ownerId"], 3)
	})

	_unit("No início de cada turno, dá +1 de Ataque a uma carta tua.", {
		"trigger": "turnStart",
		"run": func(engine, card, _x, _y):
			var t = engine.pick_most_wounded_ally(card["ownerId"])
			if t == null:
				var list: Array = engine.allies(card["ownerId"])
				if not list.is_empty():
					t = list[0]
			if t != null:
				engine.add_atk_mod(t, 1)
	})

	_unit("Ao entrar, a próxima carta que jogares custa −2 de Energia.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			engine.grant_free_next_unit(card["ownerId"])
	})

	_unit("Cartas inimigas que entrem neste corredor perdem 1 de Ataque.", {
		"trigger": "onEnterLaneDebuff",
		"amount": 1
	})

	_unit("Cartas inimigas neste corredor perdem 1 de Ataque enquanto esta carta viver.", {
		"trigger": "staticLaneDebuff",
		"amount": 1
	})

	_unit("Ganha +1 de Ataque contra cartas de tipo Sombra.", {
		"trigger": "combatMod",
		"run": func(_engine, _card, defender, _y):
			if defender != null and (defender["tipo"] as Array).has("SOMBRA"):
				return 1
			return 0
	})

	_unit("Ao morrer, cura 1 ao teu Nexus.", {
		"trigger": "onDeath",
		"run": func(engine, card, _x, _y):
			engine.heal_tower(card["ownerId"], 1)
	})

	_unit("Ganha +1/+1 por cada outra carta de tipo Ancestral em jogo.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			var n := 0
			for c in engine.allies(card["ownerId"]):
				if (c["tipo"] as Array).has("ANCESTRAL") and c["uid"] != card["uid"]:
					n += 1
			card["staticBonusAtk"] += n
			card["staticBonusVida"] += n
	})

	_unit("No início de cada turno, cura 1 a todas as tuas cartas.", {
		"trigger": "turnStart",
		"run": func(engine, card, _x, _y):
			for a in engine.allies(card["ownerId"]):
				engine.heal(a, 1)
	})

	_unit("Reduz 2 de dano a todas as tuas cartas neste corredor.", {
		"trigger": "damageReductionLane",
		"amount": 2
	})

	_unit("Sempre que uma carta tua morre, dá −1 de Ataque a uma carta inimiga.", {
		"trigger": "onAllyDeath",
		"run": func(engine, card, _dead, _y):
			var t = engine.pick_highest_ataque_enemy(card["ownerId"])
			if t != null:
				engine.add_atk_mod(t, -1)
	})

	_unit("Sempre que uma carta tua morre, ganha +1/+1 permanente.", {
		"trigger": "onAllyDeath",
		"run": func(engine, card, _dead, _y):
			engine.perm_buff(card, 1, 1)
	})

	_unit("Ao morrer, cura 3 ao teu Nexus e todos os teus Anjos ganham +1 de Ataque.", {
		"trigger": "onDeath",
		"run": func(engine, card, _x, _y):
			engine.heal_tower(card["ownerId"], 3)
			for c in engine.allies(card["ownerId"]):
				if (c["tipo"] as Array).has("ANJO"):
					engine.perm_buff(c, 1, 0)
	})

	_unit("Cartas inimigas de tipo Demónio e Sombra não recebem bónus de Alinhamento. As tuas mortes curam 2 em vez de 1.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			var foe := "ai" if card["ownerId"] == "player" else "player"
			engine.set_flag(foe, "alignmentBlockedTipos", ["DEMÓNIO", "SOMBRA"])
			engine.set_flag(card["ownerId"], "deathHealBonus", true)
	})

	_unit("No fim de cada turno, cura 1 ao teu Nexus.", {
		"trigger": "turnEnd",
		"run": func(engine, card, _x, _y):
			engine.heal_tower(card["ownerId"], 1)
	})

	_unit("Quando uma carta tua morre, cura 2 à tua carta mais ferida.", {
		"trigger": "onAllyDeath",
		"run": func(engine, card, _dead, _y):
			var t = engine.pick_most_wounded_ally(card["ownerId"])
			if t != null:
				var amount := 3 if engine.get_flag(card["ownerId"], "deathHealBonus") else 2
				engine.heal(t, amount)
	})

	_unit("Cartas inimigas de tipo Demónio perdem 1 de Ataque.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			for e in engine.enemies(card["ownerId"]):
				if (e["tipo"] as Array).has("DEMÓNIO"):
					e["staticBonusAtk"] -= 1
	})

	_unit("Ganha +2 de Ataque contra cartas de tipo Sombra.", {
		"trigger": "combatMod",
		"run": func(_engine, _card, defender, _y):
			if defender != null and (defender["tipo"] as Array).has("SOMBRA"):
				return 2
			return 0
	})

	_unit("Reduz 1 de dano a todas as tuas cartas.", {
		"trigger": "damageReductionGlobal",
		"amount": 1
	})

	_unit("Ao morrer, dá +1/+1 a uma carta tua.", {
		"trigger": "onDeath",
		"run": func(engine, card, _x, _y):
			var t = engine.pick_most_wounded_ally(card["ownerId"])
			if t == null:
				var list: Array = engine.allies(card["ownerId"])
				if not list.is_empty():
					t = list[0]
			if t != null:
				engine.perm_buff(t, 1, 1)
	})

	_unit("Sempre que uma carta tua morre, cura 1 a todas as tuas cartas.", {
		"trigger": "onAllyDeath",
		"run": func(engine, card, _dead, _y):
			var bonus := 1 if engine.get_flag(card["ownerId"], "deathHealBonus") else 0
			for a in engine.allies(card["ownerId"]):
				engine.heal(a, 1 + bonus)
	})

	_unit("Ganha +1 de Ataque por cada carta tua que já morreu.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			card["staticBonusAtk"] += engine.get_graveyard_count(card["ownerId"])
	})

	_unit("Ganha +1/+1 sempre que uma carta tua morre.", {
		"trigger": "onAllyDeath",
		"run": func(engine, card, _dead, _y):
			engine.perm_buff(card, 1, 1)
	})

	_unit("Ao entrar, todas as tuas cartas de tipo Ancestral ganham +1/+1.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			for c in engine.allies(card["ownerId"]):
				if (c["tipo"] as Array).has("ANCESTRAL"):
					engine.perm_buff(c, 1, 1)
	})

	_unit("Ganha +1 de Vida no fim de cada turno.", {
		"trigger": "turnEnd",
		"run": func(engine, card, _x, _y):
			engine.perm_buff(card, 0, 1)
	})

	_unit("Ao entrar, dá −1 de Ataque a uma carta inimiga.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			var t = engine.pick_highest_ataque_enemy(card["ownerId"])
			if t != null:
				engine.add_atk_mod(t, -1)
	})

	_unit("Não pode ser alvo de efeitos no turno em que entra.", {
		"trigger": "onEnter",
		"run": func(_engine, card, _x, _y):
			card["cannotBeTargeted"] = true
			card["cannotBeTargetedUntilRound"] = int(card["enteredRound"]) + 1
	})

	_unit("Ganha +1 de Ataque por cada turno que sobreviveu.", {
		"trigger": "static",
		"run": func(_engine, card, _x, _y):
			card["staticBonusAtk"] += int(card["turnosEmCampo"])
	})

	_unit("Ao entrar, causa 2 de dano a uma carta inimiga.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			var t = engine.pick_lowest_vida_enemy(card["ownerId"])
			if t != null:
				engine.deal_damage(t, 2, card)
	})

	_unit("No início de cada turno, dá +1 de Vida a todas as tuas cartas.", {
		"trigger": "turnStart",
		"run": func(engine, card, _x, _y):
			for a in engine.allies(card["ownerId"]):
				engine.perm_buff(a, 0, 1)
	})

	_unit("Cartas inimigas de tipo Metal perdem 1 de Ataque.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			for e in engine.enemies(card["ownerId"]):
				if (e["tipo"] as Array).has("METAL"):
					e["staticBonusAtk"] -= 1
	})

	_unit("Ganha +1/+1 no fim de cada turno.", {
		"trigger": "turnEnd",
		"run": func(engine, card, _x, _y):
			engine.perm_buff(card, 1, 1)
	})

	_unit("No início de cada turno, todas as tuas cartas ganham +1 de Vida (máx. +3).", {
		"trigger": "turnStart",
		"run": func(engine, card, _x, _y):
			for a in engine.allies(card["ownerId"]):
				var stacks := int(a.get("_raizProfundaStacks", 0))
				if stacks < 3:
					engine.perm_buff(a, 0, 1)
					a["_raizProfundaStacks"] = stacks + 1
	})

	# Esta carta tem gatilho principal turnStart e handler secundário onDeath.
	var transferidor := {
		"trigger": "turnStart",
		"run": func(engine, card, _x, _y):
			for c in engine.allies(card["ownerId"]):
				if c["uid"] != card["uid"]:
					engine.perm_buff(c, 1, 1)
					break
	}
	transferidor["onDeath"] = func(engine, card, _x, _y):
		var near = engine.pick_nearest_ally(card)
		if near != null:
			var vida := int(card["vidaAtual"])
			engine.perm_buff(near, engine.get_effective_ataque(card), max(0, vida))
	_unit("No início de cada turno, dá +1/+1 permanente a outra carta tua. Ao morrer, transfere todo o seu Ataque e Vida à carta aliada mais próxima.", transferidor)

	_unit("No fim de cada turno, dá +1 de Vida a uma carta tua.", {
		"trigger": "turnEnd",
		"run": func(engine, card, _x, _y):
			var t = engine.pick_most_wounded_ally(card["ownerId"])
			if t != null:
				engine.perm_buff(t, 0, 1)
	})

	_unit("Reduz 1 de dano recebido por esta carta.", {
		"trigger": "damageReductionSelf",
		"amount": 1
	})

	_unit("Ganha +2 de Ataque no turno em que entra.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			engine.add_atk_mod(card, 2)
	})

	_unit("Ganha +1 de Vida por cada turno que sobreviveu.", {
		"trigger": "static",
		"run": func(_engine, card, _x, _y):
			card["staticBonusVida"] += int(card["turnosEmCampo"])
	})

	_unit("No início de cada turno, causa 1 de dano a uma carta inimiga.", {
		"trigger": "turnStart",
		"run": func(engine, card, _x, _y):
			var t = engine.pick_lowest_vida_enemy(card["ownerId"])
			if t != null:
				engine.deal_damage(t, 1, card)
	})

	_unit("Não pode ser alvo de efeitos inimigos.", {
		"trigger": "static",
		"run": func(_engine, card, _x, _y):
			card["cannotBeTargetedByEnemies"] = true
	})

	_unit("Ao entrar, causa 1 de dano a uma carta inimiga.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			var t = engine.pick_lowest_vida_enemy(card["ownerId"])
			if t != null:
				engine.deal_damage(t, 1, card)
	})

	_unit("Ao ser atacada, causa 1 de dano ao atacante.", {
		"trigger": "onAttacked",
		"run": func(engine, card, attacker, _y):
			if attacker != null:
				engine.deal_damage(attacker, 1, card)
	})

	_unit("As tuas cartas de tipo Plantas ganham +1/+1.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			for a in engine.allies(card["ownerId"]):
				if (a["tipo"] as Array).has("PLANTAS"):
					a["staticBonusAtk"] += 1
					a["staticBonusVida"] += 1
	})

	_unit("Sem habilidade. Não pede nada e não recusa nada.", {"trigger": "none"})

	_unit("Se atacou no turno anterior, ganha +1 de Ataque.", {
		"trigger": "combatMod",
		"run": func(_engine, card, _defender, _y):
			return 1 if card["attackedLastRound"] else 0
	})

	_unit("Ao morrer, dá +1 de Ataque a um Monstro teu.", {
		"trigger": "onDeath",
		"run": func(engine, card, _x, _y):
			for c in engine.allies(card["ownerId"]):
				if (c["tipo"] as Array).has("MONSTRO"):
					engine.perm_buff(c, 1, 0)
					break
	})

	_unit("Ganha +1 de Ataque por cada outro Monstro em jogo.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			var n := 0
			for c in engine.all_in_play():
				if (c["tipo"] as Array).has("MONSTRO") and c["uid"] != card["uid"]:
					n += 1
			card["staticBonusAtk"] += n
	})

	_unit("Ao entrar, retira 1 de Vida máxima a uma carta inimiga.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			var t = engine.pick_lowest_vida_enemy(card["ownerId"])
			if t != null:
				engine.reduce_vida_maxima(t, 1)
	})

	_unit("Ao morrer, causa 2 de dano a todas as cartas inimigas neste corredor.", {
		"trigger": "onDeath",
		"run": func(engine, card, _x, _y):
			for e in engine.lane_enemies_of(card):
				engine.deal_damage(e, 2, card)
	})

	_unit("Ao matar uma carta inimiga, rouba 1 de Vida.", {
		"trigger": "onKill",
		"run": func(engine, card, _x, _y):
			engine.perm_buff(card, 0, 1)
	})

	_unit("Enquanto estiver em jogo, cartas inimigas de tipo Anjo perdem 1 de Ataque.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			for e in engine.enemies(card["ownerId"]):
				if (e["tipo"] as Array).has("ANJO"):
					e["staticBonusAtk"] -= 1
	})

	# Gatilho principal static + handler secundário onKill.
	var senhor_monstros := {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			if not (card["tipo"] as Array).has("MONSTRO"):
				return
			var n := 0
			for c in engine.all_in_play():
				if (c["tipo"] as Array).has("MONSTRO"):
					n += 1
			card["staticBonusAtk"] += n - 1
	}
	senhor_monstros["onKill"] = func(engine, card, _x, _y):
		engine.perm_buff(card, 0, 1)
	_unit("Cada Monstro em jogo dá +1 de Ataque a todos os Monstros. Ao matar, rouba 1 de Vida.", senhor_monstros)

	# Gatilho principal static + handler secundário onAllyDeath.
	var cultista := {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			if not (card["tipo"] as Array).has("MONSTRO"):
				return
			var n := 0
			for c in engine.all_in_play():
				if str(c.get("subgrupo", "")) == "CULTISTAS" or (c["tipo"] as Array).has("DEMÓNIO"):
					n += 1
			card["staticBonusAtk"] += n
	}
	cultista["onAllyDeath"] = func(engine, card, dead_card, _y):
		if dead_card != null and (dead_card["tipo"] as Array).has("MONSTRO"):
			engine.damage_tower(engine.opponent_of(card["ownerId"]), 1)
	_unit("Cada Cultista ou Demónio em jogo dá +1 de Ataque a todos os Monstros. Quando um Monstro teu morre, causa 1 de dano ao Nexus inimigo.", cultista)

	_unit("Ganha +1 de Ataque por cada outro Monstro teu em jogo.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			var n := 0
			for c in engine.allies(card["ownerId"]):
				if (c["tipo"] as Array).has("MONSTRO") and c["uid"] != card["uid"]:
					n += 1
			card["staticBonusAtk"] += n
	})

	_unit("Ganha +2 de Ataque contra cartas com 3 ou menos de Vida.", {
		"trigger": "combatMod",
		"run": func(_engine, _card, defender, _y):
			if defender != null and int(defender["vidaAtual"]) <= 3:
				return 2
			return 0
	})

	_unit("Todas as tuas cartas de tipo Besta ganham +1 de Ataque.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			for a in engine.allies(card["ownerId"]):
				if (a["tipo"] as Array).has("BESTA"):
					a["staticBonusAtk"] += 1
	})

	_unit("Podes destruir outra carta tua para dar +2/+2 a uma carta tua.", {
		"trigger": "activated",
		"run": func(engine, card, sacrifice_uid, target_uid):
			var sac = engine.get_card(sacrifice_uid)
			var target = engine.get_card(target_uid)
			if sac == null or target == null or sac["uid"] == card["uid"]:
				return
			engine.destroy_card(sac, card)
			engine.perm_buff(target, 2, 2)
	})

	_unit("Cartas inimigas perdem 1 de Vida máxima ao entrar em jogo.", {
		"trigger": "onEnterLaneDebuff_special",
		"amount": 1
	})

	_unit("Ganha +3 de Ataque contra cartas com 2 ou menos de Vida.", {
		"trigger": "combatMod",
		"run": func(_engine, _card, defender, _y):
			if defender != null and int(defender["vidaAtual"]) <= 2:
				return 3
			return 0
	})

	_unit("Ao matar uma carta inimiga, todos os teus Monstros ganham +1 de Ataque.", {
		"trigger": "onKill",
		"run": func(engine, card, _x, _y):
			for c in engine.allies(card["ownerId"]):
				if (c["tipo"] as Array).has("MONSTRO"):
					engine.perm_buff(c, 1, 0)
	})

	_unit("Não ataca no turno em que entra. A partir daí, causa 2 de dano extra.", {
		"trigger": "combatMod",
		"run": func(_engine, card, _defender, _y):
			return 2 if int(card["turnosEmCampo"]) > 0 else 0
	})

	_unit("Não ataca durante 2 turnos. No terceiro, dispara 6 de dano ao corredor inimigo.", {
		"trigger": "special_countdown",
		"run": func(engine, card, _x, _y):
			if int(card["turnosEmCampo"]) < 2:
				return false
			var lane_foes: Array = engine.lane_enemies_of(card)
			for e in lane_foes:
				engine.deal_damage(e, 6, card)
			if lane_foes.is_empty():
				engine.damage_tower(engine.opponent_of(card["ownerId"]), 6)
			return true
	})

	_unit("Não recebe bónus de Alinhamento. Enquanto estiver em jogo, o teu baralho não perde bónus por misturar Fiéis e Convertidos.", {
		"trigger": "static",
		"run": func(engine, card, _x, _y):
			card["noAlignmentBonus"] = true
			engine.set_flag(card["ownerId"], "deckCohesionIgnored", true)
	})

	_unit("Ao entrar, dá +1 de Vida a todas as tuas cartas de tipo Metal.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			for c in engine.allies(card["ownerId"]):
				if (c["tipo"] as Array).has("METAL"):
					engine.perm_buff(c, 0, 1)
	})

	_unit("Ganha +1 de Ataque contra cartas de tipo Plantas.", {
		"trigger": "combatMod",
		"run": func(_engine, _card, defender, _y):
			if defender != null and (defender["tipo"] as Array).has("PLANTAS"):
				return 1
			return 0
	})

	_unit("Cartas inimigas neste corredor perdem 1 de Ataque.", {
		"trigger": "staticLaneDebuff",
		"amount": 1
	})

	_unit("Ganha +1 de Ataque no fim de cada turno e perde 1 de Vida.", {
		"trigger": "turnEnd",
		"run": func(engine, card, _x, _y):
			engine.perm_buff(card, 1, 0)
			engine.deal_damage(card, 1, card, {"trueDamage": true})
	})

	_unit("Ao entrar, causa 1 de dano a todas as cartas inimigas neste corredor.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			for e in engine.lane_enemies_of(card):
				engine.deal_damage(e, 1, card)
	})

	_unit("Ao entrar, cura 3 a uma carta tua.", {
		"trigger": "onEnter",
		"run": func(engine, card, _x, _y):
			var t = engine.pick_most_wounded_ally(card["ownerId"])
			if t == null:
				t = card
			engine.heal(t, 3)
	})

	_unit("Ganha +1/+1 sempre que outra carta tua ganha Vida.", {
		"trigger": "onAllyHealed",
		"run": func(engine, card, healed_card, _y):
			if healed_card != null and healed_card["uid"] != card["uid"]:
				engine.perm_buff(card, 1, 1)
	})

	_unit("No fim de cada turno, cura 1 a uma carta tua.", {
		"trigger": "turnEnd",
		"run": func(engine, card, _x, _y):
			var t = engine.pick_most_wounded_ally(card["ownerId"])
			if t == null:
				t = card
			engine.heal(t, 1)
	})

	_unit("Não pode ser curado. Ganha +1 de Ataque no fim de cada turno.", {
		"trigger": "turnEnd",
		"run": func(engine, card, _x, _y):
			card["cannotBeHealed"] = true
			engine.perm_buff(card, 1, 0)
	})

	_unit("Uma vez por partida, ao morrer volta ao corredor com 1 de Vida.", {
		"trigger": "onDeath",
		"run": func(_engine, card, _x, _y):
			if card["usedSecondLife"]:
				return false
			card["usedSecondLife"] = true
			return "revive"
	})

# ---------------------------------------------------------------------------
# Apoios — custo 0, sem limite por turno, repõem (compram 1 carta).
# ---------------------------------------------------------------------------

func _setup_apoio_abilities() -> void:

	_apoio("AP-01", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, _extra):
			engine.add_shield(target, 3 * engine.apoio_mult())
	})

	_apoio("AP-02", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, _extra):
			engine.heal(target, 3 * engine.apoio_mult())
	})

	_apoio("AP-03", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for a in engine.allies(owner_id):
				a["tempDamageReduction"] = int(a["tempDamageReduction"]) + 2 * engine.apoio_mult()
	})

	_apoio("AP-04", {
		"needsTarget": "ally",
		"run": func(_engine, _owner_id, target, _extra):
			if target != null:
				target["readyToAttack"] = true
	})

	_apoio("AP-05", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for a in engine.allies(owner_id):
				engine.add_pressure_mark(a, 1)
	})

	_apoio("AP-06", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			engine.set_apoio_double(owner_id)
	})

	_apoio("AP-07", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, _extra):
			engine.heal(target, 4 * engine.apoio_mult())
	})

	_apoio("AP-08", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, _extra):
			engine.heal(target, 2 * engine.apoio_mult())
			if target != null:
				engine.clear_negative_effects(target)
	})

	_apoio("AP-09", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for a in engine.allies(owner_id):
				engine.heal(a, 2 * engine.apoio_mult())
	})

	# Gatilho com pré-requisito: só remata cartas com 2 ou menos de Vida.
	var remate := {
		"needsTarget": "enemy",
		"run": func(engine, _owner_id, target, _extra):
			engine.destroy_card(target, null)
	}
	remate["requireFn"] = func(_engine, _owner_id, target):
		return target != null and int(target["vidaAtual"]) <= 2
	_apoio("AP-10", remate)

	_apoio("AP-11", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for a in engine.allies(owner_id):
				a["cannotDieThisRound"] = true
	})

	_apoio("AP-12", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			var t = engine.pick_most_wounded_ally(owner_id)
			if t != null:
				engine.heal(t, 4 * engine.apoio_mult())
				engine.add_shield(t, 2 * engine.apoio_mult())
	})

	_apoio("AP-13", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, _extra):
			if target != null:
				engine.perm_buff(target, 1, 1)
	})

	_apoio("AP-14", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, extra):
			if target == null:
				return
			if extra != null and extra.has("slotType") and extra.has("slotIndex"):
				engine.move_card(target, str(extra["slotType"]), int(extra["slotIndex"]))
			engine.add_shield(target, 2)
	})

	_apoio("AP-15", {
		"needsTarget": "enemy",
		"run": func(_engine, _owner_id, target, _extra):
			if target != null:
				target["pressureLocked"] = 2
	})

	_apoio("AP-16", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for a in engine.allies(owner_id):
				engine.heal(a, 2 * engine.apoio_mult())
				engine.perm_buff(a, 1, 0)
	})

	_apoio("AP-17", {
		"needsTarget": "allyPair",
		"run": func(engine, _owner_id, from_card, to_card):
			if from_card == null or to_card == null:
				return
			var amt := int(float(from_card["vidaAtual"]) / 2.0)
			engine.deal_damage(from_card, amt, null, {"trueDamage": true})
			engine.heal(to_card, amt)
			engine.perm_buff(to_card, 2, 0)
	})

	_apoio("AP-18", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, _extra):
			if target != null:
				engine.add_atk_mod(target, 2 * engine.apoio_mult())
	})

	_apoio("AP-19", {
		"needsTarget": "enemy",
		"run": func(engine, _owner_id, target, _extra):
			if target != null:
				engine.add_pressure_mark(target, -1)
	})

	_apoio("AP-20", {
		"needsTarget": "enemy",
		"run": func(engine, _owner_id, target, _extra):
			if target != null:
				engine.reduce_vida_maxima(target, 1)
	})

	_apoio("AP-21", {
		"needsTarget": "ally",
		"run": func(engine, owner_id, target, _extra):
			engine.destroy_card(target, null)
			for a in engine.allies(owner_id):
				engine.perm_buff(a, 2, 2)
	})

	_apoio("AP-22", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			var t = engine.pick_highest_ataque_enemy(owner_id)
			if t != null:
				engine.deal_damage(t, 3, null, {"trueDamage": true})
	})

	_apoio("AP-23", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			engine.block_apoios("ai" if owner_id == "player" else "player")
	})

	_apoio("AP-24", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for a in engine.allies(owner_id):
				engine.add_shield(a, 2 * engine.apoio_mult())
	})

	_apoio("AP-25", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, _extra):
			if target == null:
				return
			engine.add_atk_mod(target, 3)
			engine.deal_damage(target, 1, null, {"trueDamage": true})
	})

	_apoio("AP-26", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			engine.return_last_dead_to_hand(owner_id)
	})

	_apoio("AP-27", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, _extra):
			if target != null:
				engine.force_rupture(target)
	})

	_apoio("AP-28", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, _extra):
			if target != null:
				engine.add_shield(target, 3 * engine.apoio_mult())
				engine.add_atk_mod(target, 1 * engine.apoio_mult())
	})

	_apoio("AP-29", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for a in engine.allies(owner_id):
				engine.heal(a, 3 * engine.apoio_mult())
				engine.add_shield(a, 1 * engine.apoio_mult())
	})

	_apoio("AP-30", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			engine.heal_tower(owner_id, 4 * engine.apoio_mult())
	})

	_apoio("AP-31", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			engine.grant_extra_unit_cap(owner_id, 2)
	})

	_apoio("AP-32", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for e in engine.enemies(owner_id):
				engine.add_atk_mod(e, -1 * engine.apoio_mult())
	})

	_apoio("AP-33", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for a in engine.allies(owner_id):
				engine.clear_negative_effects(a)
				engine.add_shield(a, 3 * engine.apoio_mult())
	})

	_apoio("AP-34", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, _extra):
			if target != null:
				engine.force_rupture(target)
				engine.add_atk_mod(target, 2 * engine.apoio_mult())
	})

	_apoio("AP-35", {
		"needsTarget": "ally",
		"run": func(engine, owner_id, target, _extra):
			engine.set_apoio_double(owner_id)
			if target != null:
				engine.add_shield(target, 2)
	})

	_apoio("AP-36", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			var t = engine.pick_highest_vida_enemy(owner_id)
			if t != null:
				engine.deal_damage(t, 4 * engine.apoio_mult(), null, {"trueDamage": true})
	})

	_apoio("AP-37", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for a in engine.allies(owner_id):
				engine.add_shield(a, 3 * engine.apoio_mult())
	})

	_apoio("AP-38", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, _extra):
			if target != null:
				target["readyToAttack"] = true
				engine.add_atk_mod(target, 2 * engine.apoio_mult())
	})

	_apoio("AP-39", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			var t = engine.pick_lowest_vida_enemy(owner_id)
			if t != null:
				engine.destroy_card(t, null)
	})

	_apoio("AP-40", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for a in engine.allies(owner_id):
				engine.perm_buff(a, 1, 1)
	})

	_apoio("AP-41", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for e in engine.enemies(owner_id):
				e["pressureLocked"] = 1
	})

	_apoio("AP-42", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			engine.heal_tower(owner_id, 5 * engine.apoio_mult())
			var t = engine.pick_most_wounded_ally(owner_id)
			if t != null:
				engine.add_shield(t, 2 * engine.apoio_mult())
	})

	_apoio("AP-43", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			engine.return_last_dead_to_hand(owner_id)
	})

	_apoio("AP-44", {
		"needsTarget": "ally",
		"run": func(engine, _owner_id, target, _extra):
			if target != null:
				engine.add_atk_mod(target, 3 * engine.apoio_mult())
				engine.add_shield(target, 3 * engine.apoio_mult())
	})

	_apoio("AP-45", {
		"needsTarget": null,
		"run": func(engine, owner_id, _target, _extra):
			for a in engine.allies(owner_id):
				engine.heal(a, 4 * engine.apoio_mult())
				engine.perm_buff(a, 2, 2)
	})

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func get_unit_ability(ability_text: String) -> Dictionary:
	if UNIT_ABILITIES.has(ability_text):
		return UNIT_ABILITIES[ability_text]
	if ability_text == "" or ability_text == null:
		return {}
	
	# Dynamic fallback matching for text patterns
	if ability_text.contains("Ao entrar, ganha +1 de Ataque."):
		return {
			"trigger": "onEnter",
			"run": func(engine, card, _x, _y):
				engine.add_atk_mod(card, 1)
		}
	elif ability_text.contains("Ao entrar, ganha Escudo 2."):
		return {
			"trigger": "onEnter",
			"run": func(engine, card, _x, _y):
				engine.add_shield(card, 2)
		}
	elif ability_text.contains("No início de cada turno, cura 1"):
		return {
			"trigger": "turnStart",
			"run": func(engine, card, _x, _y):
				engine.heal(card, 1)
		}
	elif ability_text.contains("Ao entrar, dá +1/+1 a todas as tuas cartas."):
		return {
			"trigger": "onEnter",
			"run": func(engine, card, _x, _y):
				for a in engine.allies(card["ownerId"]):
					engine.perm_buff(a, 1, 1)
		}
	elif ability_text.contains("Ao morrer, causa 2 de dano à carta inimiga no mesmo corredor."):
		return {
			"trigger": "onDeath",
			"run": func(engine, card, _x, _y):
				for e in engine.lane_enemies_of(card):
					engine.deal_damage(e, 2, card)
		}
	elif ability_text.contains("Ao morrer, cura 2 ao teu Nexus."):
		return {
			"trigger": "onDeath",
			"run": func(engine, card, _x, _y):
				engine.heal_tower(card["ownerId"], 2)
		}
	
	return {}

func get_apoio_ability(apoio_id: String) -> Dictionary:
	return APOIO_ABILITIES.get(apoio_id, {})

# Corre o `run` de uma unidade se o gatilho corresponder.
# `extra` transporta o segundo argumento (defensor, carta morta, atacante...).
func run_trigger(engine, card, trigger: String, extra = null, extra2 = null):
	var ability := get_unit_ability(str(card.get("habilidade_texto", "")))
	if ability.is_empty():
		return null
	if str(ability.get("trigger", "")) != trigger or not ability.has("run"):
		return null
	return ability["run"].call(engine, card, extra, extra2)

# Handler secundário (onDeath/onKill/onAllyDeath) além do gatilho principal.
func run_secondary(engine, card, key: String, extra = null, extra2 = null):
	var ability := get_unit_ability(str(card.get("habilidade_texto", "")))
	if ability.is_empty() or not ability.has(key):
		return null
	return ability[key].call(engine, card, extra, extra2)

func run_apoio(engine, apoio_id: String, owner_id: String, target = null, extra = null) -> bool:
	var ability := get_apoio_ability(apoio_id)
	if ability.is_empty() or not ability.has("run"):
		return false
	if ability.has("requireFn") and not ability["requireFn"].call(engine, owner_id, target):
		return false
	ability["run"].call(engine, owner_id, target, extra)
	return true

extends SceneTree

# Testes do motor. Correr com:
#   godot --headless --script res://scripts/test_game.gd
#
# Não usa assert() (que é removido em builds release) — conta falhas e sai
# com código != 0 se alguma falhar.

var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("\n=== CORREDOR — testes do motor ===\n")
	test_init()
	test_place_reinforcement()
	test_shield_absorbs_before_life()
	test_lethal_damage_kills()
	test_ability_static_guerreiro()
	test_ability_on_enter_heal()
	test_ability_on_death_heals_tower()
	test_matchup_multiplier()
	test_siege_damages_tower()
	test_apoio_shield()
	test_equipment_bonus_and_removal()
	test_full_round_advances()

	print("\n--- %d passaram, %d falharam ---\n" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# ---------------------------------------------------------------- utilitários

func check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  ok   %s" % label)
	else:
		_failed += 1
		print("  FALHA %s" % label)

func check_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("  ok   %s" % label)
	else:
		_failed += 1
		print("  FALHA %s  (esperado %s, obtido %s)" % [label, str(expected), str(actual)])

func make_unit(id: String, nome: String, papel: String, atk: int, vida: int, escudo: int = 0, habilidade: String = "", tipo: Array = [], alinhamento: String = "NEUTRO", custo: int = 1) -> Dictionary:
	return {
		"id": id, "nome": nome, "papel": papel, "faccao_slug": "teste",
		"tipo": tipo, "alinhamento": alinhamento, "ataque": atk, "vida": vida,
		"escudo": escudo, "custo": custo, "isApoio": false,
		"habilidade_texto": habilidade
	}

func make_apoio(id: String, nome: String) -> Dictionary:
	return {"id": id, "nome": nome, "faccao_slug": "teste", "isApoio": true}

# Reparte um array de cartas pelos dois montes que o motor espera: unidades
# para o Baralho Militar, Apoios e Táticas para a mão.
func split_deck(cards: Array) -> Dictionary:
	var militar := []
	var mao := []
	for c in cards:
		if c.get("isApoio", false) or str(c.get("tipo_tatico", "")) != "":
			mao.append(c)
		else:
			militar.append(c)
	return {"militar": militar, "mao": mao}

func new_game(player_deck: Array, ai_deck: Array) -> Game:
	var g := Game.new()
	g.init_game(split_deck(player_deck), split_deck(ai_deck), func(_msg): pass)
	return g

# Coloca uma carta directamente no tabuleiro, sem passar pelas regras de turno.
func place(g: Game, owner_id: String, card_def: Dictionary, slot_type: String, lane: int) -> Dictionary:
	var card: Dictionary = g._instantiate(card_def, owner_id)
	card["slotType"] = slot_type
	card["slotIndex"] = lane
	var arr: Array = g.players[owner_id]["front"] if slot_type == "frente" else g.players[owner_id]["back"]
	arr[lane] = card
	return card

# ---------------------------------------------------------------- testes

func test_init() -> void:
	print("Init")
	var deck := [
		make_unit("t1", "Guerreiro", "GUERREIRO", 2, 3),
		make_unit("t2", "Tanque", "TANQUE", 1, 5, 2),
		make_unit("t3", "Atirador", "ATIRADOR", 2, 2),
		make_apoio("AP-01", "Escudo")
	]
	var g := new_game(deck.duplicate(true), deck.duplicate(true))
	check_eq(g.towers["player"], 30, "torre do jogador começa a 30")
	check_eq(g.towers["ai"], 30, "torre da IA começa a 30")
	check_eq(g.current_round, 1, "começa no turno 1")
	check_eq(g.phase, "placement", "começa em colocação")
	check_eq(g.active_player, "player", "jogador começa")
	# O baralho de teste tem 3 unidades e a reserva arranca cheia
	check_eq(g.reinforcement_count("player"), Game.REFORCOS_INICIAIS, "reserva arranca cheia")
	check(not (g.players["player"]["hand"] as Array).is_empty(), "jogador tem cartas na mão")

func test_place_reinforcement() -> void:
	print("Colocar reforço")
	var deck := [make_unit("t1", "Guerreiro", "GUERREIRO", 2, 3)]
	var g := new_game(deck.duplicate(true), deck.duplicate(true))
	var reserva_antes: int = g.reinforcement_count("player")

	var result := g.place_reinforcement("player", 0, "frente", 0)
	check(result.get("ok", false), "jogada aceite")
	check_eq(g.reinforcement_count("player"), reserva_antes - 1, "reforço sai da reserva")
	check(g.players["player"]["front"][0] != null, "carta está no tabuleiro")

	var card: Dictionary = g.players["player"]["front"][0]
	check_eq(card["nome"], "Guerreiro", "nome correcto")
	check_eq(card["vidaAtual"], 3, "entra com a vida cheia")
	check_eq(card["turnosEmCampo"], 0, "invocação lenta: 0 turnos em campo")
	check(not g._can_act(card), "não ataca no turno em que entra")

func test_shield_absorbs_before_life() -> void:
	print("Escudo absorve antes da vida")
	var deck := [make_unit("t1", "Tanque", "TANQUE", 1, 5, 2)]
	var g := new_game(deck.duplicate(true), deck.duplicate(true))
	var card := place(g, "player", deck[0], "frente", 0)

	g.deal_damage(card, 3, null)
	check_eq(card["escudoAtual"], 0, "escudo consumido")
	check_eq(card["vidaAtual"], 4, "só 1 de dano passa à vida")
	check(card["tookDamageThisRound"], "marca que levou dano")

func test_lethal_damage_kills() -> void:
	print("Dano letal mata")
	var deck := [make_unit("t1", "Frágil", "GUERREIRO", 1, 2)]
	var g := new_game(deck.duplicate(true), deck.duplicate(true))
	var card := place(g, "player", deck[0], "frente", 0)

	g.deal_damage(card, 5, null)
	check(g.players["player"]["front"][0] == null, "casa fica vazia")
	check_eq((g.players["player"]["graveyard"] as Array).size(), 1, "vai para o cemitério")

func test_ability_static_guerreiro() -> void:
	print("Habilidade static: +1 ATQ por Guerreiro")
	var texto := "Ganha +1 de Ataque por cada outro Guerreiro em jogo."
	var lider := make_unit("t1", "Líder", "GUERREIRO", 2, 4, 0, texto)
	var g := new_game([lider], [make_unit("x", "Vazio", "GUERREIRO", 1, 1)])

	var c1 := place(g, "player", lider, "frente", 0)
	g.recompute_statics()
	check_eq(g.get_effective_ataque(c1), 2, "sozinho: 2 de ataque")

	place(g, "player", make_unit("t2", "Aliado", "GUERREIRO", 1, 2), "frente", 1)
	place(g, "player", make_unit("t3", "Aliado2", "GUERREIRO", 1, 2), "frente", 2)
	g.recompute_statics()
	check_eq(g.get_effective_ataque(c1), 4, "com 2 aliados: 4 de ataque")

func test_ability_on_enter_heal() -> void:
	print("Habilidade onEnter: cura 2 a todos")
	var texto := "Ao entrar, cura 2 a todas as tuas cartas."
	var curador := make_unit("t1", "Curador", "CURADOR", 1, 3, 0, texto)
	var g := new_game([curador], [make_unit("x", "Vazio", "GUERREIRO", 1, 1)])

	var ferido := place(g, "player", make_unit("t2", "Ferido", "GUERREIRO", 1, 5), "frente", 0)
	ferido["vidaAtual"] = 1

	var entrante := place(g, "player", curador, "retaguarda", 1)
	g._run_trigger(entrante, "onEnter")
	check_eq(ferido["vidaAtual"], 3, "aliado ferido curado de 1 para 3")

func test_ability_on_death_heals_tower() -> void:
	print("Habilidade onDeath: cura 1 à Torre")
	var texto := "Ao morrer, cura 1 ao teu Nexus."
	var martir := make_unit("t1", "Mártir", "GUERREIRO", 1, 2, 0, texto)
	var g := new_game([martir], [make_unit("x", "Vazio", "GUERREIRO", 1, 1)])

	g.towers["player"] = 20
	var card := place(g, "player", martir, "frente", 0)
	g.deal_damage(card, 10, null)
	check_eq(g.towers["player"], 21, "torre curada em 1 ao morrer")

func test_matchup_multiplier() -> void:
	print("Tipagem: +40% / -40%")
	var g := new_game([make_unit("a", "A", "GUERREIRO", 1, 1)], [make_unit("b", "B", "GUERREIRO", 1, 1)])

	var fogo := place(g, "player", make_unit("f", "Fogo", "GUERREIRO", 5, 3, 0, "", ["FOGO"]), "frente", 0)
	var planta := place(g, "ai", make_unit("p", "Planta", "GUERREIRO", 1, 9, 0, "", ["PLANTAS"]), "frente", 0)
	var agua := place(g, "ai", make_unit("w", "Água", "GUERREIRO", 1, 9, 0, "", ["ÁGUA"]), "frente", 1)

	# comparação aproximada — 1.0-0.4 não dá exactamente 0.6 em vírgula flutuante
	check(is_equal_approx(g.get_matchup_multiplier(fogo, planta), 1.4), "Fogo bate forte em Plantas (x1.4)")
	check(is_equal_approx(g.get_matchup_multiplier(fogo, agua), 0.6), "Fogo é resistido por Água (x0.6)")

func test_siege_damages_tower() -> void:
	print("Cerco: coluna vazia atinge a Torre")
	var g := new_game([make_unit("a", "A", "GUERREIRO", 1, 1)], [make_unit("b", "B", "GUERREIRO", 1, 1)])
	var atacante := place(g, "player", make_unit("s", "Sitiante", "GUERREIRO", 4, 3), "frente", 0)
	atacante["turnosEmCampo"] = 1

	g._resolve_attack(atacante, "frente")
	check_eq(g.towers["ai"], 26, "torre inimiga leva 4")
	check(g.combat_steps.size() > 0, "passo de combate registado")
	check_eq(g.combat_steps[0]["type"], "siege", "passo é do tipo cerco")

func test_apoio_shield() -> void:
	print("Apoio AP-01: +3 de Escudo")
	var apoio := make_apoio("AP-01", "Muralha")
	var g := new_game([apoio, make_unit("u", "Unidade", "GUERREIRO", 1, 3)], [make_unit("b", "B", "GUERREIRO", 1, 1)])

	var alvo := place(g, "player", make_unit("u", "Unidade", "GUERREIRO", 1, 3), "frente", 0)
	var escudo_antes := int(alvo["escudoAtual"])

	# encontra o apoio na mão
	var hand: Array = g.players["player"]["hand"]
	var apoio_idx := -1
	for i in range(hand.size()):
		if hand[i].get("isApoio", false):
			apoio_idx = i
			break

	if apoio_idx < 0:
		check(false, "apoio presente na mão inicial")
		return

	var result := g.play_hand_card("player", apoio_idx, {"target": alvo})
	check(result.get("ok", false), "apoio jogado")
	check_eq(int(alvo["escudoAtual"]), escudo_antes + 3, "alvo ganha 3 de escudo")

func test_equipment_bonus_and_removal() -> void:
	print("Equipamento: aplica e remove bónus")
	var equipamento := {
		"id": "TAC-01", "nome": "Espada de Ferro", "faccao_slug": "teste",
		"tipo_tatico": "Equipamento", "bonus_ataque": 2, "bonus_vida": 1
	}
	var g := new_game([make_unit("u", "Unidade", "GUERREIRO", 2, 3), equipamento], [make_unit("b", "B", "GUERREIRO", 1, 1)])

	var alvo := place(g, "player", make_unit("u", "Unidade", "GUERREIRO", 2, 3), "frente", 0)
	var atk_antes := g.get_effective_ataque(alvo)
	var vida_antes := int(alvo["vidaAtual"])

	var result := g.play_hand_card("player", 0, {"targetCard": alvo})
	check(result.get("ok", false), "equipamento aplicado")
	check_eq(g.get_effective_ataque(alvo), atk_antes + 2, "+2 de ataque")
	check_eq(int(alvo["vidaAtual"]), vida_antes + 1, "+1 de vida")
	check_eq((alvo["equipamentos"] as Array).size(), 1, "equipamento visível na carta")

	g.remove_equipamento(alvo["uid"], 0)
	check_eq(g.get_effective_ataque(alvo), atk_antes, "ataque volta ao original")
	check_eq((alvo["equipamentos"] as Array).size(), 0, "equipamento retirado")

func test_full_round_advances() -> void:
	print("Turno completo avança")
	var deck := [
		make_unit("t1", "A", "GUERREIRO", 1, 3),
		make_unit("t2", "B", "GUERREIRO", 1, 3),
		make_unit("t3", "C", "TANQUE", 1, 4, 2)
	]
	var g := new_game(deck.duplicate(true), deck.duplicate(true))

	g.pass_turn("player")
	g.pass_turn("ai")

	check_eq(g.current_round, 2, "avançou para o turno 2")
	check_eq(g.phase, "placement", "voltou à fase de colocação")
	# A reserva já estava cheia, por isso o reforço do turno perdeu-se
	check_eq(g.reinforcement_count("player"), Game.MAX_REFORCOS, "reserva continua cheia")
	check(not g.players["player"]["donePlacing"], "flag de passar reposta")

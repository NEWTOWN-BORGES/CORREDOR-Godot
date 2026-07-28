extends Node

# Testes do sistema de reforços — uma só mão.
#
#   godot --headless --path . res://scenes/TestReinforcements.tscn
#
# O Baralho Militar está oculto e larga 1 reforço por turno, até 3 guardados.
# A mão é uma só: Apoios + Táticas.

var _passed := 0
var _failed := 0
var game: Control = null
var engine: Game = null
var board: BoardRenderer = null

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("\n=== CORREDOR — testes de reforços ===\n")
	var tree := get_tree()

	Session.set_match("reinos", "coro")
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	game.set_animation_speed(0.0)
	game.ai = null
	engine = game.engine
	board = game.get_node("VBoxContainer/Middle/BoardArea/Board")
	await tree.process_frame

	test_start_state()
	test_decks_are_split()
	test_pool_caps_at_three()
	await test_one_per_turn()
	test_place_into_any_empty_slot()
	test_place_rejects_wrong_slot()
	test_energy_abilities_give_reinforcements()
	test_apoio_returns_dead_to_pool()
	test_single_hand_has_both_kinds()
	test_hand_refills_to_five()
	await test_ui_shows_pool()
	await test_ui_places_from_pool()
	test_ai_spends_or_saves()
	test_full_games()

	print("\n--- %d passaram, %d falharam ---\n" % [_passed, _failed])
	tree.quit(1 if _failed > 0 else 0)

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

func unit(nome: String, papel: String, atk: int = 2, vida: int = 3) -> Dictionary:
	return {
		"id": "t-" + nome, "nome": nome, "papel": papel, "faccao_slug": "reinos",
		"tipo": [], "alinhamento": "NEUTRO", "ataque": atk, "vida": vida,
		"escudo": 0, "custo": 1, "isApoio": false, "habilidade_texto": "",
		"imagem": "assets/cartas-3d/reinos-01-recruta-de-fronteira.png"
	}

func apoio(id: String, nome: String) -> Dictionary:
	return {
		"id": id, "nome": nome, "faccao_slug": "reinos", "isApoio": true,
		"imagem": "assets/apoios-3d/ap-01-pocao-de-vigor.png"
	}

func reset() -> void:
	for owner_id in ["player", "ai"]:
		var p: Dictionary = engine.players[owner_id]
		p["front"] = [null, null, null, null, null, null]
		p["back"] = [null, null, null, null, null, null]
		p["reinforcements"] = []
		p["hand"] = []
		p["graveyard"] = []
		p["discard"] = []
		p["donePlacing"] = false
		p["apoiosBlocked"] = false
		p["apoioDoubleNext"] = false
		p["lastApoio"] = null
		p["lastDeadCard"] = null
	engine.towers = {"player": 30, "ai": 30}
	engine.phase = "placement"
	engine.active_player = "player"
	engine.winner = ""
	engine.current_round = 1
	game._clear_targeting()
	game._render_game()

func fill_military(owner_id: String, n: int) -> void:
	var monte := []
	for i in range(n):
		monte.append(unit("Mil%d" % i, "GUERREIRO", 2, 3))
	engine.players[owner_id]["militaryDeck"] = monte

# ---------------------------------------------------------------- testes

func test_start_state() -> void:
	print("Arranque")
	# Estado tal como o init_game o deixou, sem reset
	var g := Game.new()
	g.init_game(
		DeckManager.build_faction_deck(Cards.as_dictionary(), "reinos"),
		DeckManager.build_faction_deck(Cards.as_dictionary(), "coro"),
		func(_m): pass
	)
	check_eq(g.reinforcement_count("player"), Game.REFORCOS_INICIAIS, "3 reforços na reserva")
	check_eq((g.players["player"]["hand"] as Array).size(), Game.MAO_MAX, "5 cartas na mão")
	check(g.reinforcements_full("player"), "a reserva começa cheia")
	check((g.players["player"]["front"] as Array).all(func(c): return c == null), "tabuleiro vazio")

func test_decks_are_split() -> void:
	print("Baralhos separados")
	var baralho := DeckManager.build_faction_deck(Cards.as_dictionary(), "reinos")
	check(baralho.has("militar") and baralho.has("mao"), "DeckManager devolve os dois montes")

	var so_unidades := true
	for c in baralho["militar"]:
		if c.get("isApoio", false) or str(c.get("tipo_tatico", "")) != "":
			so_unidades = false
	check(so_unidades, "militar só tem unidades (%d)" % (baralho["militar"] as Array).size())

	var apoios := 0
	var taticas := 0
	for c in baralho["mao"]:
		if c.get("isApoio", false):
			apoios += 1
		elif str(c.get("tipo_tatico", "")) != "":
			taticas += 1
	check(apoios > 0, "mão tem Apoios (%d)" % apoios)
	check(taticas > 0, "mão tem Táticas (%d)" % taticas)
	check_eq(apoios + taticas, (baralho["mao"] as Array).size(), "e mais nada")

func test_pool_caps_at_three() -> void:
	print("Reserva trava nos 3")
	reset()
	fill_military("player", 10)

	check_eq(engine.gain_reinforcement("player", 1), 1, "primeiro entra")
	check_eq(engine.gain_reinforcement("player", 1), 1, "segundo entra")
	check_eq(engine.gain_reinforcement("player", 1), 1, "terceiro entra")
	check_eq(engine.reinforcement_count("player"), 3, "reserva com 3")

	check_eq(engine.gain_reinforcement("player", 1), 0, "o quarto não entra")
	check_eq(engine.reinforcement_count("player"), 3, "continua com 3")
	check(engine.reinforcements_full("player"), "reserva dá-se por cheia")

	# Pedir muitos de uma vez também trava
	reset()
	fill_military("player", 10)
	check_eq(engine.gain_reinforcement("player", 9), 3, "pedir 9 traz só 3")

	# Baralho vazio não inventa cartas
	reset()
	engine.players["player"]["militaryDeck"] = []
	check_eq(engine.gain_reinforcement("player", 3), 0, "baralho vazio não dá reforços")

func test_one_per_turn() -> void:
	print("Um reforço por turno")
	reset()
	fill_military("player", 10)
	fill_military("ai", 10)
	engine.players["ai"]["donePlacing"] = true

	check_eq(engine.reinforcement_count("player"), 0, "começa a zero")
	await game._run_action(func(): return engine.pass_turn("player"))
	check_eq(engine.reinforcement_count("player"), 1, "1 ao fim do primeiro turno")
	check_eq(engine.reinforcement_count("ai"), 1, "e o adversário também")

	engine.players["ai"]["donePlacing"] = true
	await game._run_action(func(): return engine.pass_turn("player"))
	check_eq(engine.reinforcement_count("player"), 2, "2 ao fim do segundo")

func test_place_into_any_empty_slot() -> void:
	print("Reforço entra em qualquer casa livre")
	reset()
	engine.players["player"]["reinforcements"] = [
		unit("Guerreiro", "GUERREIRO"),
		unit("Arqueiro", "ATIRADOR")
	]

	var r := engine.place_reinforcement("player", 0, "frente", 4)
	check(r.get("ok", false), "guerreiro entra na frente 4")
	check(engine.players["player"]["front"][4] != null, "está no tabuleiro")
	check_eq(engine.reinforcement_count("player"), 1, "saiu da reserva")

	# Colocar passa a prioridade ao adversário — para continuar a testar
	# colocações seguidas, devolvemos a vez à mão.
	engine.active_player = "player"
	r = engine.place_reinforcement("player", 0, "retaguarda", 2)
	check(r.get("ok", false), "atirador entra na retaguarda 2")
	check_eq(engine.reinforcement_count("player"), 0, "reserva esvaziou")

	# Sem reserva não há colocação
	engine.active_player = "player"
	r = engine.place_reinforcement("player", 0, "frente", 1)
	check(not r.get("ok", false), "reserva vazia recusa: %s" % r.get("error", ""))

func test_place_rejects_wrong_slot() -> void:
	print("Casas erradas são recusadas")
	reset()
	engine.players["player"]["reinforcements"] = [unit("Arqueiro", "ATIRADOR")]

	check(not engine.place_reinforcement("player", 0, "frente", 0).get("ok", false),
		"atirador não vai para a frente")
	check(not engine.place_reinforcement("player", 0, "retaguarda", 0).get("ok", false),
		"nem para a ponta de Apoio 0")
	check(not engine.place_reinforcement("player", 0, "retaguarda", 5).get("ok", false),
		"nem para a ponta de Apoio 5")

	# Casa ocupada
	engine.players["player"]["reinforcements"].append(unit("Outro", "ATIRADOR"))
	check(engine.place_reinforcement("player", 0, "retaguarda", 3).get("ok", false), "primeiro entra")
	engine.active_player = "player"
	check(not engine.place_reinforcement("player", 0, "retaguarda", 3).get("ok", false),
		"casa ocupada recusa o segundo")

func test_energy_abilities_give_reinforcements() -> void:
	print("Habilidades de Energia dão reforços")
	reset()
	fill_military("player", 10)

	# "Ao entrar, ganhas 1 de Energia"
	engine.draw_card("player", 1)
	check_eq(engine.reinforcement_count("player"), 1, "draw_card dá 1 reforço")

	# "As tuas cartas custam −1 de Energia" — dava mais margem de unidades
	engine.grant_extra_unit_cap("player", 1)
	check_eq(engine.reinforcement_count("player"), 2, "grant_extra_unit_cap dá 1 reforço")

	# "A próxima carta custa −2 de Energia"
	engine.grant_free_next_unit("player")
	check_eq(engine.reinforcement_count("player"), 3, "grant_free_next_unit dá 1 reforço")

	# E respeitam o tecto
	engine.draw_card("player", 5)
	check_eq(engine.reinforcement_count("player"), 3, "não passam do máximo")

	check_eq(engine.get_unit_cap("player"), 3, "get_unit_cap devolve o tamanho da reserva")

func test_apoio_returns_dead_to_pool() -> void:
	print("AP-26 devolve o morto à reserva")
	reset()
	var carta: Dictionary = engine._instantiate(unit("Caído", "GUERREIRO", 3, 4), "player")
	carta["slotType"] = "frente"
	carta["slotIndex"] = 1
	engine.players["player"]["front"][1] = carta
	engine.deal_damage(carta, 99, null)

	check_eq(engine.reinforcement_count("player"), 0, "reserva vazia antes")
	engine.return_last_dead_to_hand("player")
	check_eq(engine.reinforcement_count("player"), 1, "voltou para a reserva")

	var voltou: Dictionary = engine.players["player"]["reinforcements"][0]
	check_eq(str(voltou.get("nome", "")), "Caído", "é a carta certa")
	check_eq(int(voltou.get("vida", 0)), 4, "volta com a vida de base, não a que tinha ao morrer")

	# Com a reserva cheia não volta
	reset()
	engine.players["player"]["reinforcements"] = [unit("A", "GUERREIRO"), unit("B", "GUERREIRO"), unit("C", "GUERREIRO")]
	engine.players["player"]["lastDeadCard"] = engine._instantiate(unit("Outro", "GUERREIRO"), "player")
	engine.return_last_dead_to_hand("player")
	check_eq(engine.reinforcement_count("player"), 3, "reserva cheia não recebe")

func test_single_hand_has_both_kinds() -> void:
	print("A mão tem Apoios e Táticas")
	reset()
	engine.players["player"]["hand"] = [
		apoio("AP-01", "Muralha"),
		{"id": "TAC-1", "nome": "Espada", "tipo_tatico": "Equipamento",
		 "bonus_ataque": 2, "isApoio": false, "imagem": "tatico-001.png"}
	]

	# Apoio com alvo, pela porta única
	var alvo: Dictionary = engine._instantiate(unit("Alvo", "GUERREIRO", 2, 6), "player")
	alvo["slotType"] = "frente"
	alvo["slotIndex"] = 1
	engine.players["player"]["front"][1] = alvo

	var r := engine.play_hand_card("player", 0, {"target": alvo})
	check(r.get("ok", false), "Apoio jogado da mão única")
	check_eq(int(alvo["escudoAtual"]), 3, "AP-01 deu 3 de escudo")
	check(engine.players["player"]["lastApoio"] != null, "foi para a zona de Apoio")

	# Equipamento, pela mesma porta
	r = engine.play_hand_card("player", 0, {"targetCard": alvo})
	check(r.get("ok", false), "Equipamento jogado da mão única")
	check_eq((alvo["equipamentos"] as Array).size(), 1, "ficou pendurado na carta")

func test_hand_refills_to_five() -> void:
	print("A mão volta a encher")
	reset()
	engine.players["player"]["hand"] = [apoio("AP-06", "Selo")]
	var monte := []
	for i in range(10):
		monte.append({"id": "TAC-%d" % i, "nome": "Bênção%d" % i, "tipo_tatico": "Bênção",
			"isApoio": false, "imagem": "tatico-001.png"})
	engine.players["player"]["deck"] = monte

	engine.refill_hand("player")
	check_eq((engine.players["player"]["hand"] as Array).size(), Game.MAO_MAX, "encheu até 5")

	# Jogar uma repõe
	engine.play_hand_card("player", 0, {})
	check_eq((engine.players["player"]["hand"] as Array).size(), Game.MAO_MAX, "continua com 5")

	# Baralho vazio: a mão vai encolhendo, sem rebentar
	engine.players["player"]["deck"] = []
	engine.play_hand_card("player", 0, {})
	check_eq((engine.players["player"]["hand"] as Array).size(), Game.MAO_MAX - 1, "sem baralho, encolhe")

func test_ui_shows_pool() -> void:
	print("A reserva aparece no ecrã")
	reset()
	engine.players["player"]["reinforcements"] = [unit("Um", "GUERREIRO"), unit("Dois", "TANQUE")]
	game._render_game()
	await get_tree().process_frame

	var casas: int = game.reinforcement_slots.get_child_count()
	check_eq(casas, Game.MAX_REFORCOS, "%d casas na coluna" % Game.MAX_REFORCOS)

	var com_carta := 0
	for child in game.reinforcement_slots.get_children():
		if child is CardView:
			com_carta += 1
	check_eq(com_carta, 2, "duas com carta, uma vazia")
	check_eq(game.reinforcement_count.text, "2 / 3", "contador diz 2 / 3")

	# Cheia avisa a cor
	engine.players["player"]["reinforcements"].append(unit("Três", "GUERREIRO"))
	game._render_game()
	await get_tree().process_frame
	check_eq(game.reinforcement_count.text, "3 / 3", "contador diz 3 / 3")
	var cor: Color = game.reinforcement_count.get_theme_color("font_color")
	check(cor.is_equal_approx(Palette.EMBER_400), "e fica em destaque")

func test_ui_places_from_pool() -> void:
	print("Colocar pelo ecrã")
	reset()
	engine.players["player"]["reinforcements"] = [unit("Recruta", "GUERREIRO")]
	game._render_game()
	await get_tree().process_frame

	game._commit_reinforcement_selection(0, engine.players["player"]["reinforcements"][0])
	check_eq(game._selected_reinforcement, 0, "reforço escolhido")

	await game._on_slot_clicked("player", "frente", 2)
	var colocada = engine.players["player"]["front"][2]
	check(colocada != null, "entrou na casa 2")
	if colocada != null:
		check_eq(str(colocada.get("nome", "")), "Recruta", "é a carta que estava escolhida")

	# A reserva pode não estar vazia: colocar passa a prioridade, o turno
	# resolve-se e o Baralho Militar larga já o reforço seguinte. O que tem de
	# ser verdade é que aquela carta saiu de lá.
	var ainda_na_reserva := false
	for c in engine.players["player"]["reinforcements"]:
		if str(c.get("nome", "")) == "Recruta":
			ainda_na_reserva = true
	check(not ainda_na_reserva, "a carta colocada saiu da reserva")
	check_eq(game._selected_reinforcement, -1, "escolha limpa")

func test_ai_spends_or_saves() -> void:
	print("A IA decide gastar ou guardar")
	reset()
	var ai := AIPlayer.new("ai")

	# Coluna da frente aberta: gasta
	engine.players["ai"]["reinforcements"] = [unit("Reforço", "GUERREIRO")]
	check(ai.should_spend_reinforcement(engine), "com coluna aberta, gasta")

	# Frente cheia e reserva com folga: guarda
	for lane in range(6):
		var c: Dictionary = engine._instantiate(unit("Muro", "GUERREIRO"), "ai")
		c["slotType"] = "frente"
		c["slotIndex"] = lane
		engine.players["ai"]["front"][lane] = c
	check(not ai.should_spend_reinforcement(engine), "frente cheia e reserva com folga, guarda")

	# Reserva cheia: gasta na mesma, senão o do próximo turno perde-se
	engine.players["ai"]["reinforcements"] = [
		unit("A", "ATIRADOR"), unit("B", "ATIRADOR"), unit("C", "ATIRADOR")
	]
	check(ai.should_spend_reinforcement(engine), "reserva cheia, gasta para não desperdiçar")

func test_full_games() -> void:
	print("Partidas inteiras com o sistema novo")
	var cartas := Cards.as_dictionary()
	var faccoes := DeckManager.list_factions(cartas)
	var presas := 0
	var turnos := 0
	var vitorias := {}

	for i in range(20):
		var g := Game.new()
		g.init_game(
			DeckManager.build_faction_deck(cartas, str(faccoes[i % faccoes.size()])),
			DeckManager.build_faction_deck(cartas, str(faccoes[(i + 1) % faccoes.size()])),
			func(_m): pass
		)
		var a := AIPlayer.new("player")
		var b := AIPlayer.new("ai")

		var guard := 0
		while g.phase != "gameover" and guard < 3000:
			guard += 1
			if g.active_player == "player":
				a.step(g)
			else:
				b.step(g)

		if g.phase != "gameover":
			presas += 1
			continue
		turnos += g.current_round
		vitorias[g.winner] = int(vitorias.get(g.winner, 0)) + 1

	check_eq(presas, 0, "20 partidas, nenhuma ficou presa")
	check(not vitorias.is_empty(), "chegaram ao fim")
	print("        média de %.1f turnos" % (float(turnos) / 20.0))
	print("        vitórias: %s" % str(vitorias))

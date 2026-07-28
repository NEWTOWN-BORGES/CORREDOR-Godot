extends Node

# Testes do adversário automático (Fase 8).
#
#   godot --headless --path . res://scenes/TestAI.tscn
#
# Verifica a heurística (pontuação, ordem das colunas, escolha de alvos) e
# depois põe a IA a jogar partidas inteiras contra si própria, para garantir
# que nunca fica presa nem faz jogadas ilegais.

const PARTIDAS := 40

var _passed := 0
var _failed := 0
var game: Control = null
var engine: Game = null
var ai: AIPlayer = null

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("\n=== CORREDOR — testes da IA ===\n")
	var tree := get_tree()

	Session.set_match("reinos", "coro")
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	game.set_animation_speed(0.0)
	engine = game.engine
	ai = AIPlayer.new("ai")
	await tree.process_frame

	test_score_prefers_stronger()
	test_slot_order_centre_first()
	test_never_uses_apoio_edges()
	test_plays_best_unit_first()
	test_apoio_before_unit()
	test_apoio_target_choices()
	test_requires_valid_target()
	test_passes_when_nothing_to_do()
	test_pool_limits_placement()
	test_tatico_equipment_target()
	test_tatico_magic_finishes_off()
	test_tatico_consumable_only_when_worth_it()
	test_tatico_blessing_needs_attacker()
	test_tatico_skips_inert_types()
	test_tatico_turn_limit()
	test_tatico_order_before_units()
	await test_ui_lets_ai_play()
	test_full_games_never_stall()

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

func unit(nome: String, papel: String, atk: int, vida: int, escudo: int = 0, custo: int = 1) -> Dictionary:
	return {
		"id": "t-" + nome, "nome": nome, "papel": papel, "faccao_slug": "coro",
		"tipo": [], "alinhamento": "NEUTRO", "ataque": atk, "vida": vida,
		"escudo": escudo, "custo": custo, "isApoio": false, "habilidade_texto": "",
		"imagem": "assets/cartas-3d/reinos-01-recruta-de-fronteira.png"
	}

func apoio(id: String, nome: String) -> Dictionary:
	return {
		"id": id, "nome": nome, "faccao_slug": "coro", "isApoio": true,
		"imagem": "assets/apoios-3d/ap-01-pocao-de-vigor.png"
	}

func place(owner_id: String, card_def: Dictionary, slot_type: String, lane: int) -> Dictionary:
	var card: Dictionary = engine._instantiate(card_def, owner_id)
	card["slotType"] = slot_type
	card["slotIndex"] = lane
	var arr: Array = engine.players[owner_id]["front"] if slot_type == "frente" else engine.players[owner_id]["back"]
	arr[lane] = card
	return card

func reset() -> void:
	for owner_id in ["player", "ai"]:
		var p: Dictionary = engine.players[owner_id]
		p["front"] = [null, null, null, null, null, null]
		p["back"] = [null, null, null, null, null, null]
		p["graveyard"] = []
		p["donePlacing"] = false
		p["apoiosBlocked"] = false
		p["apoioDoubleNext"] = false
		p["lastApoio"] = null
		# A mão e a reserva vêm cheias do arranque; cada teste põe o que quiser
		p["hand"] = []
		p["deck"] = []
		p["reinforcements"] = []
		p["militaryDeck"] = []
	engine.towers = {"player": 30, "ai": 30}
	engine.phase = "placement"
	engine.active_player = "ai"
	engine.winner = ""
	engine.current_round = 2   # turno 2+ para o limite ser 3 e não 6
	# Os testes montam vários cenários no mesmo turno, por isso o travão de
	# táticas por turno tem de ser posto a zero à mão entre eles.
	ai.reset_turn_state()

# ---------------------------------------------------------------- heurística

func test_score_prefers_stronger() -> void:
	print("Pontuação prefere a carta mais forte")
	# ataque×2 + vida + escudo - custo×0.2
	var fraca := unit("Fraca", "GUERREIRO", 1, 1)
	var forte := unit("Forte", "GUERREIRO", 4, 5)
	check(ai.score_unit(forte) > ai.score_unit(fraca), "4/5 vale mais que 1/1")

	check_eq(ai.score_unit(unit("X", "GUERREIRO", 2, 3, 0, 0)), 7.0, "2 ataque + 3 vida = 7")
	check_eq(ai.score_unit(unit("Y", "TANQUE", 1, 4, 2, 0)), 8.0, "escudo conta na pontuação")

	# O ataque pesa a dobrar
	var atacante := unit("Atacante", "GUERREIRO", 3, 1, 0, 0)
	var resistente := unit("Resistente", "GUERREIRO", 1, 4, 0, 0)
	check(ai.score_unit(atacante) > ai.score_unit(resistente), "ataque pesa a dobrar (7 contra 6)")

	# Custo mais alto desempata para baixo
	var barata := unit("Barata", "GUERREIRO", 2, 2, 0, 1)
	var cara := unit("Cara", "GUERREIRO", 2, 2, 0, 5)
	check(ai.score_unit(barata) > ai.score_unit(cara), "entre iguais, prefere a mais barata")

func test_slot_order_centre_first() -> void:
	print("Prefere as colunas do centro")
	check_eq(ai.slot_order(true), [2, 3, 1, 4, 0, 5], "frente: do centro para fora")
	check_eq(ai.slot_order(false), [2, 3, 1, 4], "retaguarda: só as colunas de combate")

	reset()
	var slot := ai.find_open_slot(engine, unit("A", "GUERREIRO", 1, 1))
	check_eq(int(slot["slotIndex"]), 2, "tabuleiro vazio: escolhe a coluna 2")

	place("ai", unit("Ocupa", "GUERREIRO", 1, 1), "frente", 2)
	slot = ai.find_open_slot(engine, unit("B", "GUERREIRO", 1, 1))
	check_eq(int(slot["slotIndex"]), 3, "com a 2 ocupada: escolhe a 3")

func test_never_uses_apoio_edges() -> void:
	print("Nunca usa as pontas de Apoio")
	reset()
	# Encher as colunas de combate da retaguarda
	for lane in [1, 2, 3, 4]:
		place("ai", unit("Ocupa", "CURADOR", 1, 1), "retaguarda", lane)

	var slot := ai.find_open_slot(engine, unit("Atirador", "ATIRADOR", 1, 1))
	check(slot.is_empty(), "sem colunas de combate livres, não inventa casa")
	check(not ai.slot_order(false).has(0), "0 fora da ordem de retaguarda")
	check(not ai.slot_order(false).has(5), "5 fora da ordem de retaguarda")

func test_plays_best_unit_first() -> void:
	print("Joga primeiro a melhor unidade")
	reset()
	engine.players["ai"]["reinforcements"] = [
		unit("Fraca", "GUERREIRO", 1, 1),
		unit("Forte", "GUERREIRO", 5, 5),
		unit("Média", "GUERREIRO", 2, 3)
	]

	ai.step(engine)
	var colocada = engine.players["ai"]["front"][2]
	check(colocada != null, "colocou alguma coisa na coluna 2")
	if colocada != null:
		check_eq(str(colocada.get("nome", "")), "Forte", "escolheu a mais forte")

func test_apoio_before_unit() -> void:
	print("Joga Apoios antes de unidades")
	reset()
	# AP-06 não pede alvo
	engine.players["ai"]["hand"] = [apoio("AP-06", "Selo do Ecónomo")]
	engine.players["ai"]["reinforcements"] = [unit("Unidade", "GUERREIRO", 3, 3)]

	ai.step(engine)
	check(engine.players["ai"]["apoioDoubleNext"], "o Apoio saiu primeiro")
	check_eq(engine.players["ai"]["front"][2], null, "o reforço ainda não entrou")
	check_eq(engine.reinforcement_count("ai"), 1, "continua na reserva")

func test_apoio_target_choices() -> void:
	print("Escolhe alvos com sentido")
	reset()
	var forte := place("ai", unit("Forte", "GUERREIRO", 6, 8), "frente", 1)
	var ferido := place("ai", unit("Ferido", "GUERREIRO", 1, 8), "frente", 2)
	ferido["vidaAtual"] = 2
	var ameaca := place("player", unit("Ameaça", "GUERREIRO", 7, 9), "frente", 1)
	var moribundo := place("player", unit("Moribundo", "GUERREIRO", 1, 9), "frente", 2)
	moribundo["vidaAtual"] = 1

	var def_ally := engine.abilities.get_apoio_ability("AP-02")
	var alvo := ai.pick_apoio_target(engine, def_ally, "AP-02")
	check_eq(str(alvo["target"]["nome"]), "Ferido", "cura escolhe o mais ferido")

	var def_enemy := engine.abilities.get_apoio_ability("AP-22")
	alvo = ai.pick_apoio_target(engine, def_enemy, "AP-22")
	check_eq(str(alvo["target"]["nome"]), "Ameaça", "dano escolhe o inimigo mais forte")

	var def_remate := engine.abilities.get_apoio_ability("AP-10")
	alvo = ai.pick_apoio_target(engine, def_remate, "AP-10")
	check_eq(str(alvo["target"]["nome"]), "Moribundo", "remate escolhe quem já está a cair")

	var def_par := engine.abilities.get_apoio_ability("AP-17")
	alvo = ai.pick_apoio_target(engine, def_par, "AP-17")
	check_eq(str(alvo["from"]["nome"]), "Forte", "transfusão tira ao mais são")
	check_eq(str(alvo["to"]["nome"]), "Ferido", "e dá ao mais ferido")

	var def_arma := engine.abilities.get_apoio_ability("AP-14")
	alvo = ai.pick_apoio_target(engine, def_arma, "AP-14")
	check_eq(str(alvo["target"]["nome"]), "Forte", "reposicionar escolhe o mais forte")

func test_requires_valid_target() -> void:
	print("Não joga Apoio sem alvo que sirva")
	reset()
	# AP-10 só remata cartas com 2 ou menos de Vida
	engine.players["ai"]["hand"] = [apoio("AP-10", "Juízo")]
	place("player", unit("Saudável", "GUERREIRO", 2, 9), "frente", 1)

	var mao_antes: int = (engine.players["ai"]["hand"] as Array).size()
	ai.step(engine)
	check_eq((engine.players["ai"]["hand"] as Array).size(), mao_antes, "guardou o Apoio")
	check(engine.players["ai"]["donePlacing"], "passou, por não ter mais nada a fazer")

	# Com um alvo válido já o usa
	reset()
	engine.players["ai"]["hand"] = [apoio("AP-10", "Juízo")]
	var fraco := place("player", unit("Fraco", "GUERREIRO", 2, 9), "frente", 1)
	fraco["vidaAtual"] = 1

	ai.step(engine)
	check(engine.players["player"]["front"][1] == null, "rematou o alvo")

func test_passes_when_nothing_to_do() -> void:
	print("Passa quando não tem nada a fazer")
	reset()
	engine.players["ai"]["hand"] = []
	engine.players["ai"]["reinforcements"] = []

	ai.step(engine)
	check(engine.players["ai"]["donePlacing"], "passou de mão e reserva vazias")

	# Reserva só com cartas sem casa livre
	reset()
	for lane in range(6):
		place("ai", unit("Ocupa", "GUERREIRO", 1, 1), "frente", lane)
	for lane in [1, 2, 3, 4]:
		place("ai", unit("OcupaR", "CURADOR", 1, 1), "retaguarda", lane)
	engine.players["ai"]["reinforcements"] = [unit("SemCasa", "GUERREIRO", 9, 9)]

	ai.step(engine)
	check(engine.players["ai"]["donePlacing"], "passou por não ter casa livre")
	check_eq(engine.reinforcement_count("ai"), 1, "o reforço ficou na reserva")

func test_pool_limits_placement() -> void:
	print("A reserva é que limita as colocações")
	reset()
	var reserva := []
	for i in range(3):
		reserva.append(unit("U%d" % i, "GUERREIRO", 2, 2))
	engine.players["ai"]["reinforcements"] = reserva.duplicate()

	# Com o jogador ainda a decidir, a prioridade volta-lhe a cada jogada e a
	# IA só age uma vez — é o sistema alternado, não um defeito.
	ai.step(engine)
	check_eq(engine.allies("ai").size(), 1, "com a prioridade a alternar, coloca uma de cada vez")
	check_eq(engine.active_player, "player", "e devolve a vez ao jogador")

	# Com o jogador já passado, a IA esvazia a reserva e pára
	reset()
	engine.players["ai"]["reinforcements"] = reserva.duplicate()
	engine.players["player"]["donePlacing"] = true

	var turno := engine.current_round
	var guard := 0
	while engine.phase == "placement" and engine.active_player == "ai" 		and engine.current_round == turno and guard < 30:
		guard += 1
		ai.step(engine)

	check_eq(engine.allies("ai").size(), 3, "colocou as três da reserva")
	check_eq(engine.reinforcement_count("ai"), 0, "reserva esvaziada")
	# Sem reserva e sem mão fica pronta; como o jogador já tinha passado, o
	# turno resolve-se logo. É essa a prova de que parou.
	check_eq(engine.current_round, turno + 1, "esgotou a reserva e o turno avançou")

# ---------------------------------------------------------------- táticas

func tatico(tipo: String, nome: String, campos: Dictionary = {}) -> Dictionary:
	var c := {
		"id": "TAC-" + nome, "nome": nome, "faccao_slug": "coro",
		"tipo_tatico": tipo, "imagem": "tatico-001.png"
	}
	c.merge(campos)
	return c

# A mão é uma só; isto põe lá as cartas que o teste quer.
func set_taticos(cards: Array) -> void:
	engine.players["ai"]["hand"] = cards.duplicate()
	engine.players["ai"]["deck"] = []

func test_tatico_equipment_target() -> void:
	print("Equipamento vai para quem mais lucra")
	reset()
	var fraco := place("ai", unit("Fraco", "GUERREIRO", 1, 6), "frente", 1)
	var forte := place("ai", unit("Forte", "GUERREIRO", 5, 6), "frente", 2)

	# Bónus de ataque: prefere quem já bate forte
	var espada := tatico("Equipamento", "Espada", {"bonus_ataque": 2, "bonus_vida": 0})
	var plano := ai.plan_tatico(engine, espada)
	check_eq(str(plano["target"]["nome"]), "Forte", "bónus de ataque no que bate mais")

	# Bónus de vida: prefere quem está mais ferido
	fraco["vidaAtual"] = 1
	var elmo := tatico("Equipamento", "Elmo", {"bonus_ataque": 0, "bonus_vida": 3})
	plano = ai.plan_tatico(engine, elmo)
	check_eq(str(plano["target"]["nome"]), "Fraco", "bónus de vida no mais ferido")

	# E joga mesmo, aplicando o bónus
	set_taticos([espada])
	var atk_antes := engine.get_effective_ataque(forte)
	ai.step(engine)
	check_eq(engine.get_effective_ataque(forte), atk_antes + 2, "ataque subiu 2")
	check_eq((forte["equipamentos"] as Array).size(), 1, "equipamento pendurado")

	# Sem unidades em campo não há onde equipar
	reset()
	check(ai.plan_tatico(engine, espada).is_empty(), "sem aliados, guarda o equipamento")

func test_tatico_magic_finishes_off() -> void:
	print("Magia remata quem consegue matar")
	reset()
	var perigoso := place("player", unit("Perigoso", "GUERREIRO", 9, 20), "frente", 1)
	var quase := place("player", unit("Quase", "GUERREIRO", 4, 9), "frente", 2)
	quase["vidaAtual"] = 2

	var magia := tatico("Magia", "Golpe", {"dano": 3})
	var plano := ai.plan_tatico(engine, magia)
	check_eq(str(plano["target"]["nome"]), "Quase", "prefere o remate ao alvo mais forte")

	# Se ninguém morre, bate no mais perigoso
	quase["vidaAtual"] = 9
	plano = ai.plan_tatico(engine, magia)
	check_eq(str(plano["target"]["nome"]), "Perigoso", "sem remate, bate no mais perigoso")

	# O escudo conta para saber se remata
	quase["vidaAtual"] = 2
	quase["escudoAtual"] = 4
	plano = ai.plan_tatico(engine, magia)
	check_eq(str(plano["target"]["nome"]), "Perigoso", "com escudo já não é remate")
	quase["escudoAtual"] = 0

	# E joga mesmo
	set_taticos([magia])
	ai.step(engine)
	check(engine.players["player"]["front"][2] == null, "rematou o alvo")

	# Sem inimigos, guarda a magia
	reset()
	check(ai.plan_tatico(engine, magia).is_empty(), "sem inimigos, guarda a magia")

func test_tatico_consumable_only_when_worth_it() -> void:
	print("Consumível só quando há vida para repor")
	reset()
	var intacto := place("ai", unit("Intacto", "GUERREIRO", 2, 8), "frente", 1)

	var pocao := tatico("Consumível", "Elixir", {"cura": 4})
	check(ai.plan_tatico(engine, pocao).is_empty(), "ninguém ferido, guarda a poção")

	# Falta 1 de 4 de cura — desperdício
	intacto["vidaAtual"] = 7
	check(ai.plan_tatico(engine, pocao).is_empty(), "falta 1 para cura 4: não vale a pena")

	# Falta 5 — aproveita
	intacto["vidaAtual"] = 3
	var plano := ai.plan_tatico(engine, pocao)
	check(not plano.is_empty(), "com 5 de falta, usa")
	check_eq(str(plano["target"]["nome"]), "Intacto", "no ferido")

	# Escolhe o mais ferido de vários
	var pior := place("ai", unit("Pior", "GUERREIRO", 2, 10), "frente", 2)
	pior["vidaAtual"] = 1
	plano = ai.plan_tatico(engine, pocao)
	check_eq(str(plano["target"]["nome"]), "Pior", "escolhe o mais ferido")

	# Não cura quem não pode ser curado
	pior["cannotBeHealed"] = true
	plano = ai.plan_tatico(engine, pocao)
	check_eq(str(plano["target"]["nome"]), "Intacto", "ignora quem não pode ser curado")

func test_tatico_blessing_needs_attacker() -> void:
	print("Bênção só numa carta que vá atacar")
	reset()
	# Acabada de entrar: não age este turno
	var recem := place("ai", unit("Recém", "GUERREIRO", 4, 4), "frente", 1)
	recem["turnosEmCampo"] = 0

	var bencao := tatico("Bênção", "Bênção Real", {"tipo_efeito": "bencao"})
	check(ai.plan_tatico(engine, bencao).is_empty(), "ninguém pronto a atacar, guarda")

	# Já em campo há um turno: pode atacar
	recem["turnosEmCampo"] = 1
	var plano := ai.plan_tatico(engine, bencao)
	check(not plano.is_empty(), "com atacante pronto, usa")
	check_eq(str(plano["target"]["nome"]), "Recém", "no que vai atacar")

	# Entre dois prontos, escolhe o que bate mais
	var forte := place("ai", unit("Forte", "GUERREIRO", 7, 4), "frente", 2)
	forte["turnosEmCampo"] = 1
	plano = ai.plan_tatico(engine, bencao)
	check_eq(str(plano["target"]["nome"]), "Forte", "escolhe o que bate mais")

func test_tatico_skips_inert_types() -> void:
	print("Não gasta jogadas com Construção e Clima")
	reset()
	place("ai", unit("Qualquer", "GUERREIRO", 2, 5), "frente", 1)

	var construcao := tatico("Construção", "Barricada", {"vida_construcao": 8})
	var clima := tatico("Clima", "Chuva", {"duracao_turnos": 3})
	check(ai.plan_tatico(engine, construcao).is_empty(), "Construção não tem efeito no motor")
	check(ai.plan_tatico(engine, clima).is_empty(), "Clima também não")

	# Com só estas na mão tática, não joga nenhuma
	set_taticos([construcao, clima])
	engine.players["ai"]["reinforcements"] = []
	ai.step(engine)
	check_eq((engine.players["ai"]["hand"] as Array).size(), 2, "ficaram as duas na mão")
	check(engine.players["ai"]["donePlacing"], "passou em vez de as desperdiçar")

func test_tatico_turn_limit() -> void:
	print("Trava o número de táticas por turno")
	reset()
	var alvo := place("player", unit("Alvo", "GUERREIRO", 2, 40), "frente", 1)

	# Mão e baralho cheios de magias úteis: sem travão esvaziava tudo
	var magias := []
	for i in range(6):
		magias.append(tatico("Magia", "Golpe%d" % i, {"dano": 2}))
	engine.players["ai"]["hand"] = magias
	engine.players["ai"]["deck"] = magias.duplicate()
	# Um reforço na reserva para o motor não dar o turno por terminado à
	# primeira: sem jogadas possíveis, _check_auto_advance fecha-o logo.
	engine.players["ai"]["reinforcements"] = [unit("Reserva", "GUERREIRO", 1, 1)]

	var guard := 0
	while engine.phase == "placement" and engine.active_player == "ai" and guard < 20:
		guard += 1
		ai.step(engine)

	check(ai._taticas_neste_turno <= AIPlayer.MAX_TATICAS_POR_TURNO,
		"jogou %d táticas, limite %d" % [ai._taticas_neste_turno, AIPlayer.MAX_TATICAS_POR_TURNO])
	check_eq(int(alvo["vidaAtual"]), 40 - 2 * AIPlayer.MAX_TATICAS_POR_TURNO,
		"dano corresponde ao limite de táticas")

func test_tatico_order_before_units() -> void:
	print("Táticas antes de gastar o reforço")
	reset()
	place("ai", unit("EmCampo", "GUERREIRO", 5, 6), "frente", 1)
	engine.players["ai"]["reinforcements"] = [unit("NaReserva", "GUERREIRO", 3, 3)]
	set_taticos([tatico("Equipamento", "Espada", {"bonus_ataque": 2, "bonus_vida": 0})])

	ai.step(engine)
	check_eq(engine.reinforcement_count("ai"), 1, "não gastou o reforço")
	check_eq((engine.players["ai"]["hand"] as Array).size(), 0, "a tática saiu")

func test_ui_lets_ai_play() -> void:
	print("A UI deixa a IA jogar de verdade")
	reset()
	engine.players["ai"]["reinforcements"] = [
		unit("Guerreiro", "GUERREIRO", 3, 4),
		unit("Tanque", "TANQUE", 1, 6, 2)
	]
	engine.active_player = "ai"
	engine.players["player"]["donePlacing"] = true

	check(game.ai != null, "a cena tem uma IA ligada")
	await game._maybe_advance_ai()

	var jogou := engine.allies("ai").size() > 0 or engine.current_round > 2
	check(jogou, "a IA agiu — já não passa sempre")

func test_full_games_never_stall() -> void:
	print("Partidas inteiras da IA contra si própria")
	var cartas := Cards.as_dictionary()
	var faccoes := DeckManager.list_factions(cartas)

	var presas := 0
	var ilegais := 0
	var turnos_total := 0
	var vitorias := {}

	for i in range(PARTIDAS):
		var a := str(faccoes[i % faccoes.size()])
		var b := str(faccoes[(i + 1) % faccoes.size()])

		var g := Game.new()
		g.init_game(
			DeckManager.build_faction_deck(cartas, a),
			DeckManager.build_faction_deck(cartas, b),
			func(_m): pass
		)
		var jogador := AIPlayer.new("player")
		var adversario := AIPlayer.new("ai")

		var guard := 0
		while g.phase != "gameover" and guard < 3000:
			guard += 1
			if g.active_player == "player":
				jogador.step(g)
			else:
				adversario.step(g)

		if g.phase != "gameover":
			presas += 1
			continue

		# Nenhuma unidade pode ter ficado nas pontas de Apoio
		for owner_id in ["player", "ai"]:
			for lane in [0, 5]:
				if g.players[owner_id]["back"][lane] != null:
					ilegais += 1

		turnos_total += g.current_round
		vitorias[g.winner] = int(vitorias.get(g.winner, 0)) + 1

	check_eq(presas, 0, "%d partidas, nenhuma ficou presa" % PARTIDAS)
	check_eq(ilegais, 0, "nenhuma unidade nas pontas de Apoio")
	check(not vitorias.is_empty(), "as partidas chegaram ao fim")
	print("        média de %.1f turnos por partida" % (float(turnos_total) / float(PARTIDAS)))
	print("        vitórias: %s" % str(vitorias))

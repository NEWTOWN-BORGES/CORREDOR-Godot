extends Node

# Testes do combate e fim de partida (Fase 7).
#
#   godot --headless --path . res://scenes/TestCombat.tscn
#
# As animações correm a velocidade zero (animation_speed = 0), por isso o
# que se testa é a resolução e o que fica no ecrã depois — não os tempos.

var _passed := 0
var _failed := 0
var game: Control = null
var engine: Game = null
var board: BoardRenderer = null

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("\n=== CORREDOR — testes de combate ===\n")
	var tree := get_tree()

	Session.set_match("reinos", "coro")
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	game.animation_speed = 0.0
	engine = game.engine
	board = game.get_node("VBoxContainer/BoardArea/Board")
	await tree.process_frame

	test_combat_runs_when_both_pass()
	await test_column_duel()
	await test_siege_empty_column()
	await test_tank_absorbs_with_shield()
	await test_rupture_hits_tower()
	await test_assassin_skips_front()
	await test_archer_targets_weakest()
	await test_slow_summon()
	await test_pressure_accumulates()
	await test_victory_overlay()
	await test_defeat_overlay()
	await test_round_limit_decides()

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

func unit(nome: String, papel: String, atk: int, vida: int, escudo: int = 0) -> Dictionary:
	return {
		"id": "t-" + nome, "nome": nome, "papel": papel, "faccao_slug": "reinos",
		"tipo": [], "alinhamento": "NEUTRO", "ataque": atk, "vida": vida,
		"escudo": escudo, "custo": 1, "isApoio": false, "habilidade_texto": "",
		"imagem": "assets/cartas-3d/reinos-01-recruta-de-fronteira.png"
	}

# Coloca já pronta a atacar (turnosEmCampo = 1 salta a invocação lenta)
func place(owner_id: String, card_def: Dictionary, slot_type: String, lane: int, pronta: bool = true) -> Dictionary:
	var card: Dictionary = engine._instantiate(card_def, owner_id)
	card["slotType"] = slot_type
	card["slotIndex"] = lane
	if pronta:
		card["turnosEmCampo"] = 1
	var arr: Array = engine.players[owner_id]["front"] if slot_type == "frente" else engine.players[owner_id]["back"]
	arr[lane] = card
	return card

func reset() -> void:
	for owner_id in ["player", "ai"]:
		var p: Dictionary = engine.players[owner_id]
		p["front"] = [null, null, null, null, null, null]
		p["back"] = [null, null, null, null, null, null]
		p["hand"] = []
		p["graveyard"] = []
		p["unitPlaysThisRound"] = 0
		p["donePlacing"] = false
		p["lastApoio"] = null
		p["apoiosBlocked"] = false
	engine.towers = {"player": 30, "ai": 30}
	engine.phase = "placement"
	engine.active_player = "player"
	engine.winner = ""
	engine.current_round = 1
	engine.combat_steps = []
	game._gameover_shown = false
	game.gameover_overlay.visible = false
	game._clear_targeting()
	game._render_game()

# Faz o turno resolver: ambos passam
func resolve_turn() -> void:
	engine.players["ai"]["donePlacing"] = true
	await game._run_action(func(): return engine.pass_turn("player"))

func view_at(owner_id: String, slot_type: String, lane: int) -> CardView:
	var holder := board.card_holder(owner_id, slot_type, lane)
	if holder == null:
		return null
	for child in holder.get_children():
		if child is CardView:
			return child
	return null

# ---------------------------------------------------------------- testes

func test_combat_runs_when_both_pass() -> void:
	print("Combate corre quando ambos passam")
	reset()
	var antes: int = engine.combat_counter
	engine.players["ai"]["donePlacing"] = true
	engine.pass_turn("player")
	check(engine.combat_counter > antes, "houve resolução de combate")
	check_eq(engine.current_round, 2, "passou para o turno 2")

func test_column_duel() -> void:
	print("Duelo na mesma coluna")
	reset()
	var meu := place("player", unit("Meu", "GUERREIRO", 3, 5), "frente", 2)
	var dele := place("ai", unit("Dele", "GUERREIRO", 2, 6), "frente", 2)

	await resolve_turn()

	check_eq(int(dele["vidaAtual"]), 3, "o dele levou 3")
	check_eq(int(meu["vidaAtual"]), 3, "o meu levou 2")
	check_eq(int(engine.towers["ai"]), 30, "nenhuma torre foi tocada")
	check_eq(int(engine.towers["player"]), 30, "nem a minha")

func test_siege_empty_column() -> void:
	print("Coluna vazia: o ataque vai à Torre")
	reset()
	place("player", unit("Sitiante", "GUERREIRO", 4, 5), "frente", 0)

	await resolve_turn()

	check_eq(int(engine.towers["ai"]), 26, "torre inimiga desceu 4")
	check_eq(int(engine.towers["player"]), 30, "a minha ficou intacta")

	var barra_hp: Label = board._tower_labels["ai"]
	check_eq(barra_hp.text, "26/30", "a barra no ecrã mostra 26/30")

func test_tank_absorbs_with_shield() -> void:
	print("Escudo do Tanque absorve antes da vida")
	reset()
	place("player", unit("Lanceiro", "GUERREIRO", 3, 4), "frente", 1)
	var tanque := place("ai", unit("Muro", "TANQUE", 1, 6, 2), "frente", 1)

	await resolve_turn()

	check_eq(int(tanque["escudoAtual"]), 0, "escudo de 2 consumido")
	check_eq(int(tanque["vidaAtual"]), 5, "só 1 passou à vida")

func test_rupture_hits_tower() -> void:
	print("Ruptura ignora o que está à frente")
	reset()
	var rompedor := place("player", unit("Rompedor", "GUERREIRO", 5, 5), "frente", 3)
	place("ai", unit("Bloqueio", "GUERREIRO", 1, 9), "frente", 3)

	# 2 marcas é o limiar sem SOMBRA do outro lado
	rompedor["pressaoMarcas"] = 2
	check_eq(engine._rupture_threshold(rompedor), 2, "limiar é 2 sem SOMBRA")

	await resolve_turn()

	check_eq(int(engine.towers["ai"]), 25, "os 5 foram direitos à Torre")
	check_eq(int(rompedor["pressaoMarcas"]), 1, "marcas repostas e ganhou 1 no fim do turno")

func test_assassin_skips_front() -> void:
	print("Assassino salta a linha da frente")
	reset()
	var assassino := place("player", unit("Sombra", "ASSASSINO", 4, 3), "retaguarda", 2, false)
	var muro := place("ai", unit("Muro", "GUERREIRO", 1, 9), "frente", 2)
	var curador := place("ai", unit("Curador", "CURADOR", 1, 4), "retaguarda", 2)

	# Assassino ataca logo no turno em que entra
	check(engine._can_act(assassino), "Assassino age logo ao entrar")

	await resolve_turn()

	check_eq(int(curador["vidaAtual"]), 0, "atingiu a retaguarda")
	check_eq(int(muro["vidaAtual"]), 9, "o muro ficou intacto — foi ignorado")
	# E o muro, esse, bate na coluna 2 do meu lado: frente vazia, por isso
	# desce à retaguarda e acerta no próprio Assassino.
	check_eq(int(assassino["vidaAtual"]), 2, "o muro respondeu no Assassino")

func test_archer_targets_weakest() -> void:
	print("Atirador escolhe o alvo com menos Vida")
	reset()
	place("player", unit("Arqueiro", "ATIRADOR", 3, 3), "retaguarda", 2)
	var gordo := place("ai", unit("Gordo", "GUERREIRO", 1, 9), "frente", 0)
	var fraco := place("ai", unit("Fraco", "GUERREIRO", 1, 3), "frente", 4)

	await resolve_turn()

	check_eq(int(gordo["vidaAtual"]), 9, "o mais gordo não foi tocado pelo Atirador")
	check(int(fraco["vidaAtual"]) <= 0, "o mais fraco levou o tiro")

func test_slow_summon() -> void:
	print("Invocação lenta: não ataca no turno em que entra")
	reset()
	var recem := place("player", unit("Recém", "GUERREIRO", 4, 4), "frente", 1, false)
	var alvo := place("ai", unit("Alvo", "GUERREIRO", 0, 9), "frente", 1)

	check(not engine._can_act(recem), "acabada de entrar, não age")
	await resolve_turn()
	check_eq(int(alvo["vidaAtual"]), 9, "o alvo não levou nada")

	# No turno seguinte já ataca
	engine.players["ai"]["donePlacing"] = true
	await game._run_action(func(): return engine.pass_turn("player"))
	check(int(alvo["vidaAtual"]) < 9, "no turno seguinte já bateu")

func test_pressure_accumulates() -> void:
	print("Pressão acumula a cada turno sobrevivido")
	reset()
	var sobrevivente := place("player", unit("Firme", "GUERREIRO", 1, 20), "frente", 5)

	check_eq(int(sobrevivente["pressaoMarcas"]), 0, "entra sem marcas")
	await resolve_turn()
	check_eq(int(sobrevivente["pressaoMarcas"]), 1, "1 marca depois de um turno")

	var vista := view_at("player", "frente", 5)
	check(vista != null, "carta desenhada no tabuleiro")
	if vista != null:
		check_eq(vista._pressure_row.get_child_count(), 2, "duas marcas visíveis na carta")

func test_victory_overlay() -> void:
	print("Vitória quando a Torre inimiga cai")
	reset()
	engine.towers["ai"] = 3
	place("player", unit("Aríete", "GUERREIRO", 6, 5), "frente", 0)

	await resolve_turn()

	check_eq(int(engine.towers["ai"]), 0, "torre inimiga a zero")
	check_eq(engine.winner, "player", "vencedor é o jogador")
	check_eq(engine.phase, "gameover", "partida terminada")
	check(game.gameover_overlay.visible, "ecrã de fim aparece")
	check_eq(game.gameover_title.text, "Vitória", "diz Vitória")

func test_defeat_overlay() -> void:
	print("Derrota quando a minha Torre cai")
	reset()
	engine.towers["player"] = 2
	place("ai", unit("Aríete", "GUERREIRO", 6, 5), "frente", 0)

	await resolve_turn()

	check_eq(int(engine.towers["player"]), 0, "a minha torre caiu")
	check_eq(engine.winner, "ai", "vencedor é o adversário")
	check(game.gameover_overlay.visible, "ecrã de fim aparece")
	check_eq(game.gameover_title.text, "Derrota", "diz Derrota")

func test_round_limit_decides() -> void:
	print("Limite de turnos decide pela Torre mais baixa")
	reset()
	engine.current_round = Game.ROUND_LIMIT
	engine.towers["player"] = 20
	engine.towers["ai"] = 10

	await resolve_turn()

	check_eq(engine.phase, "gameover", "partida terminada no limite")
	check_eq(engine.winner, "player", "ganha quem deixou a Torre do outro mais baixa")
	check(game.gameover_overlay.visible, "ecrã de fim aparece")
	check_eq(game.gameover_title.text, "Vitória", "diz Vitória")

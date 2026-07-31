extends Node

# Testes da colocação e escolha de alvos (Fase 6).
#
#   godot --headless --path . res://scenes/TestPlacement.tscn
#
# Percorre o mesmo caminho do web: clicar na carta abre a ampliação, "Jogar"
# acende as casas válidas, clicar na casa coloca. E o mesmo para Apoios com
# alvo e Equipamentos.

var _passed := 0
var _failed := 0
var game: Control = null
var engine: Game = null
var board: BoardRenderer = null

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("\n=== CORREDOR — testes de colocação ===\n")
	var tree := get_tree()

	Session.set_match("reinos", "coro")
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	# Desde a Fase 7 as jogadas passam por _run_action, que é assíncrono.
	# Sem isto ficavam acções pendentes a resumir a meio do teste seguinte.
	game.set_animation_speed(0.0)
	# Sem adversário automático: estes testes verificam onde a carta ficou, e
	# a IA a jogar logo a seguir resolvia o combate e matava-a antes da
	# verificação — falhava ao calhar, conforme as cartas que lhe saíam.
	game.ai = null
	engine = game.engine
	board = game.get_node("BoardArea/Board")
	await tree.process_frame

	test_zoom_opens_and_closes()
	test_play_button_hidden_when_unplayable()
	test_valid_slots_highlighted()
	await test_slot_click_places_card()
	await test_wrong_slot_rejected()
	await test_enemy_slots_ignored()
	test_clicking_same_card_cancels()
	await test_apoio_without_target_plays_now()
	await test_apoio_with_target_enters_targeting()
	await test_apoio_pair_two_steps()
	await test_equipment_targeting()
	await test_graveyard_shows_last()
	test_board_card_readonly_zoom()

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

# Põe a mão exactamente como o teste precisa
func set_hand(cards: Array) -> void:
	engine.players["player"]["hand"] = cards.duplicate()

# As unidades já não vêm da mão — vêm da reserva de reforços.
func set_reinforcements(cards: Array) -> void:
	engine.players["player"]["reinforcements"] = cards.duplicate()

func place(owner_id: String, card_def: Dictionary, slot_type: String, lane: int) -> Dictionary:
	var card: Dictionary = engine._instantiate(card_def, owner_id)
	card["slotType"] = slot_type
	card["slotIndex"] = lane
	var arr: Array = engine.players[owner_id]["front"] if slot_type == "frente" else engine.players[owner_id]["back"]
	arr[lane] = card
	return card

func slot_highlighted(owner_id: String, slot_type: String, lane: int) -> bool:
	var slot := board.slot_control(owner_id, slot_type, lane)
	if slot == null:
		return false
	var sb: StyleBoxFlat = slot.get_theme_stylebox("panel")
	return sb.get_border_width(SIDE_TOP) > 0

func reset_board() -> void:
	for owner_id in ["player", "ai"]:
		var p: Dictionary = engine.players[owner_id]
		p["front"] = [null, null, null, null, null, null]
		p["back"] = [null, null, null, null, null, null]
		# Sem isto, um teste que jogue o AP-06 (dobra o próximo Apoio) deixa
		# o efeito ligado e falseia o teste seguinte.
		p["apoioDoubleNext"] = false
		p["apoiosBlocked"] = false
		p["apoiosBlockedNextRound"] = false
		p["lastApoio"] = null
		p["reinforcements"] = []
		p["donePlacing"] = false
	engine.phase = "placement"
	engine.active_player = "player"
	game._clear_targeting()
	game._render_game()

# ---------------------------------------------------------------- testes

func test_zoom_opens_and_closes() -> void:
	print("Ampliação abre e fecha")
	reset_board()
	set_reinforcements([unit("Recruta", "GUERREIRO")])
	game._render_hands()

	check(not game.zoom_overlay.visible, "começa fechada")
	game._on_reinforcement_click(0)
	check(game.zoom_overlay.visible, "clicar na carta abre")
	check(game.zoom_card.texture != null, "mostra a arte da carta")
	check(game.zoom_actions.visible, "mostra os botões")

	game._close_zoom()
	check(not game.zoom_overlay.visible, "Cancelar fecha")
	check_eq(game._selected_reinforcement, -1, "fechar sem jogar não escolhe nada")

func test_play_button_hidden_when_unplayable() -> void:
	print("Botão Jogar só aparece se der para jogar")
	reset_board()
	# Equipamento sem unidade amiga em campo não tem onde ir
	var espada := {"id": "TAC-9", "nome": "Espada", "tipo_tatico": "Equipamento",
		"bonus_ataque": 2, "isApoio": false, "imagem": "tatico-001.png"}
	set_hand([espada])
	game._render_hands()

	game._on_hand_card_click(0)
	check(not game.zoom_play.visible, "sem unidade para equipar, não deixa jogar")
	check(game.zoom_overlay.visible, "mas continua a poder ler a carta")
	game._close_zoom()

	# Com uma unidade em campo já dá
	place("player", unit("Alvo", "GUERREIRO"), "frente", 1)
	game._render_game()
	game._on_hand_card_click(0)
	check(game.zoom_play.visible, "com unidade em campo, deixa jogar")
	game._close_zoom()

func test_valid_slots_highlighted() -> void:
	print("Casas válidas acendem")
	reset_board()
	var atirador := unit("Arqueiro", "ATIRADOR")
	set_reinforcements([atirador])
	game._render_hands()

	game._commit_reinforcement_selection(0, atirador)
	check_eq(game._selected_reinforcement, 0, "reforço ficou escolhido")

	# ATIRADOR é de retaguarda: só as colunas 1-4 acendem
	for lane in range(6):
		check(not slot_highlighted("player", "frente", lane),
			"frente %d apagada (é carta de retaguarda)" % lane)
	for lane in [1, 2, 3, 4]:
		check(slot_highlighted("player", "retaguarda", lane), "retaguarda %d acesa" % lane)
	check(not slot_highlighted("player", "retaguarda", 0), "retaguarda 0 apagada (é de Apoio)")
	check(not slot_highlighted("player", "retaguarda", 5), "retaguarda 5 apagada (é de Apoio)")

	game._clear_targeting()
	check(not slot_highlighted("player", "retaguarda", 2), "desistir apaga tudo")

func test_slot_click_places_card() -> void:
	print("Clicar na casa coloca a carta")
	reset_board()
	var guerreiro := unit("Recruta", "GUERREIRO")
	set_reinforcements([guerreiro])
	game._render_hands()

	game._commit_reinforcement_selection(0, guerreiro)
	await game._on_slot_clicked("player", "frente", 3)

	var colocada = engine.players["player"]["front"][3]
	check(colocada != null, "carta entrou na casa 3")
	if colocada != null:
		check_eq(str(colocada.get("nome", "")), "Recruta", "é a carta certa")
	check_eq(engine.reinforcement_count("player"), 0, "saiu da reserva")
	check_eq(game._selected_reinforcement, -1, "escolha limpa depois de colocar")
	check(not slot_highlighted("player", "frente", 2), "destaques apagados")

func test_wrong_slot_rejected() -> void:
	print("Casa errada é recusada")
	reset_board()
	var atirador := unit("Arqueiro", "ATIRADOR")
	set_reinforcements([atirador])
	game._render_hands()
	game._commit_reinforcement_selection(0, atirador)

	# ATIRADOR não pode ir para a frente
	await game._on_slot_clicked("player", "frente", 0)
	check(engine.players["player"]["front"][0] == null, "atirador não entra na frente")
	check_eq(engine.reinforcement_count("player"), 1, "continua na reserva")

	# nem para as pontas de Apoio
	await game._on_slot_clicked("player", "retaguarda", 0)
	check(engine.players["player"]["back"][0] == null, "não entra na ponta de Apoio")
	check_eq(engine.reinforcement_count("player"), 1, "continua na reserva")

	# mas entra numa coluna de combate
	await game._on_slot_clicked("player", "retaguarda", 2)
	check(engine.players["player"]["back"][2] != null, "entra na retaguarda 2")

func test_enemy_slots_ignored() -> void:
	print("Casas do adversário não aceitam cartas tuas")
	reset_board()
	var guerreiro := unit("Recruta", "GUERREIRO")
	set_reinforcements([guerreiro])
	game._render_hands()
	game._commit_reinforcement_selection(0, guerreiro)

	await game._on_slot_clicked("ai", "frente", 2)
	check(engine.players["ai"]["front"][2] == null, "nada entrou no lado do adversário")
	check_eq(engine.reinforcement_count("player"), 1, "reforço continua na reserva")

func test_clicking_same_card_cancels() -> void:
	print("Clicar outra vez na mesma carta desiste")
	reset_board()
	var guerreiro := unit("Recruta", "GUERREIRO")
	set_reinforcements([guerreiro])
	game._render_hands()

	game._commit_reinforcement_selection(0, guerreiro)
	check_eq(game._selected_reinforcement, 0, "escolhido")

	game._on_reinforcement_click(0)
	check_eq(game._selected_reinforcement, -1, "segundo clique desiste")
	check(not game.zoom_overlay.visible, "e não reabre a ampliação")

func test_apoio_without_target_plays_now() -> void:
	print("Apoio sem alvo resolve-se logo")
	reset_board()
	# AP-06 não pede alvo (dobra o próximo Apoio)
	set_hand([apoio("AP-06", "Selo do Ecónomo")])
	game._render_hands()

	check(not engine.players["player"]["apoioDoubleNext"], "ainda não dobrou")
	await game._commit_hand_selection(0, engine.players["player"]["hand"][0])

	check(engine.players["player"]["apoioDoubleNext"], "efeito aplicado logo")
	check(not game.target_bar.visible, "não pediu alvo")

func test_apoio_with_target_enters_targeting() -> void:
	print("Apoio com alvo entra em modo de escolha")
	reset_board()
	var alvo := place("player", unit("Ferido", "GUERREIRO", 2, 6), "frente", 1)
	alvo["escudoAtual"] = 0
	# AP-01 dá 3 de Escudo a uma carta tua
	set_hand([apoio("AP-01", "Muralha")])
	game._render_game()

	await game._commit_hand_selection(0, engine.players["player"]["hand"][0])
	check(game.target_bar.visible, "barra de alvo apareceu")
	check(str(game.target_prompt.text).contains("carta tua"), "pede uma carta tua")
	check(game.is_targeting(), "está em modo de escolha")

	# Clicar numa carta inimiga não faz nada
	var inimigo := place("ai", unit("Inimigo", "GUERREIRO"), "frente", 1)
	game._render_game()
	await game._on_board_card_clicked(inimigo)
	check(game.is_targeting(), "carta inimiga não serve para Apoio de aliado")
	check_eq(int(alvo["escudoAtual"]), 0, "e nada foi aplicado")

	# Clicar na carta certa resolve
	await game._on_board_card_clicked(alvo)
	check_eq(int(alvo["escudoAtual"]), 3, "aliado ganhou 3 de escudo")
	check(not game.is_targeting(), "saiu do modo de escolha")
	check(not game.target_bar.visible, "barra desapareceu")

func test_apoio_pair_two_steps() -> void:
	print("Apoio de par pede origem e destino")
	reset_board()
	var origem := place("player", unit("Origem", "GUERREIRO", 2, 8), "frente", 1)
	var destino := place("player", unit("Destino", "GUERREIRO", 2, 8), "frente", 2)
	destino["vidaAtual"] = 3
	# AP-17 transfere vida de uma carta para outra
	set_hand([apoio("AP-17", "Transfusão")])
	game._render_game()

	await game._commit_hand_selection(0, engine.players["player"]["hand"][0])
	check(str(game.target_prompt.text).contains("origem"), "primeiro pede a origem")

	await game._on_board_card_clicked(origem)
	check(game.is_targeting(), "continua em modo de escolha")
	check(str(game.target_prompt.text).contains("recebe"), "agora pede quem recebe")

	# Clicar na mesma carta não vale como destino
	await game._on_board_card_clicked(origem)
	check(game.is_targeting(), "origem não pode ser também destino")

	var vida_destino_antes := int(destino["vidaAtual"])
	await game._on_board_card_clicked(destino)
	check(not game.is_targeting(), "par completo, Apoio resolvido")
	check(int(destino["vidaAtual"]) > vida_destino_antes, "destino recebeu vida")

func test_equipment_targeting() -> void:
	print("Equipamento pede unidade amiga")
	reset_board()
	var alvo := place("player", unit("Espadachim", "GUERREIRO", 2, 4), "frente", 2)
	game._render_game()

	var equipamento := {
		"id": "TAC-99", "nome": "Espada de Ferro", "faccao_slug": "reinos",
		"tipo_tatico": "Equipamento", "bonus_ataque": 2, "imagem": "tatico-001.png"
	}
	set_hand([equipamento])
	game._render_hands()

	var atk_antes := engine.get_effective_ataque(alvo)
	await game._commit_hand_selection(0, equipamento)
	check(game.target_bar.visible, "pede alvo para equipar")
	check(str(game.target_prompt.text).contains("Espada de Ferro"), "diz qual é o equipamento")

	# Unidade inimiga não pode ser equipada
	var inimigo := place("ai", unit("Inimigo", "GUERREIRO"), "frente", 2)
	game._render_game()
	await game._on_board_card_clicked(inimigo)
	check(game.is_targeting(), "não deixa equipar unidade inimiga")

	await game._on_board_card_clicked(alvo)
	check(not game.is_targeting(), "equipado")
	check_eq((alvo["equipamentos"] as Array).size(), 1, "equipamento pendurado na carta")
	check_eq(engine.get_effective_ataque(alvo), atk_antes + 2, "ataque subiu 2")

func test_graveyard_shows_last() -> void:
	print("Cemitério mostra a última carta que saiu")
	reset_board()
	place("player", unit("Alvo", "GUERREIRO", 2, 6), "frente", 1)
	set_hand([apoio("AP-09", "Cântico de Aurora")])
	game._render_game()

	var holder := board.graveyard_holder("player")
	check(holder != null, "o cemitério existe")
	if holder == null:
		return
	check_eq(holder.get_child_count(), 0, "começa vazia")

	# AP-09 cura todos os aliados, não pede alvo
	await game._commit_hand_selection(0, engine.players["player"]["hand"][0])
	game._render_game()

	check(engine.players["player"]["lastApoio"] != null, "motor guardou o último Apoio")
	var vista: CardView = null
	for child in holder.get_children():
		if child is CardView:
			vista = child
	check(vista != null, "cemitério mostra a carta")
	if vista != null:
		check_eq(str(vista.card.get("nome", "")), "Cântico de Aurora", "é o Apoio certo")
		check(not vista._stat_bar.visible, "sem barra de stats, é só a arte")

func test_board_card_readonly_zoom() -> void:
	print("Carta do tabuleiro fora de escolha é só para ler")
	reset_board()
	var carta := place("player", unit("Sentinela", "GUERREIRO"), "frente", 0)
	game._render_game()

	check(not game.is_targeting(), "não está em modo de escolha")
	await game._on_board_card_clicked(carta)
	check(game.zoom_overlay.visible, "abriu a ampliação")
	check(not game.zoom_actions.visible, "sem botão de jogar — é só para ler")
	game._close_zoom()

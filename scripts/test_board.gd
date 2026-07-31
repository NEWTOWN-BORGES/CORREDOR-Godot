extends Node

# Testes do tabuleiro (Fase 4).
#
#   godot --headless --path . res://scenes/TestBoard.tscn
#
# Verifica que as 24 casas existem, que caem nas coordenadas medidas na arte,
# que as pontas da retaguarda são só-Apoio, e que as Torres respondem à vida.

const BOARD_SIZE := Vector2(1402, 1122)

var _passed := 0
var _failed := 0
var game: Control = null
var board: BoardRenderer = null

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("\n=== CORREDOR — testes do tabuleiro ===\n")
	var tree := get_tree()

	Session.set_match("reinos", "coro")
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	board = game.get_node("VBoxContainer/Middle/BoardArea/Board")

	# Desde a Fase 9 as barras das Torres descem animadas e as casas válidas
	# pulsam. A zero, vão directas ao valor final e não fica nenhum ciclo
	# infinito a correr durante os testes.
	game.set_animation_speed(0.0)

	# Fixa o tamanho para as contas de percentagem serem verificáveis
	board.set_portrait(false)
	board.size = BOARD_SIZE
	board._relayout()
	await tree.process_frame

	test_geometry_math()
	test_all_slots_exist()
	test_apoio_edges()
	test_rank_positions()
	test_lane_alignment()
	test_towers()
	test_ruined_board()
	test_deck_zones()
	test_graveyard_zone()

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

func check_near(actual: float, expected: float, tol: float, label: String) -> void:
	if abs(actual - expected) <= tol:
		_passed += 1
		print("  ok   %s" % label)
	else:
		_failed += 1
		print("  FALHA %s  (esperado %.2f, obtido %.2f)" % [label, expected, actual])

# ---------------------------------------------------------------- testes

func test_geometry_math() -> void:
	print("Contas da geometria")
	# CSS: 6 casas com flex 1 1 0 e gap 0.8% -> largura (1 - 5*0.008)/6 = 0.16
	check_near(BoardGeometry.slot_width(), 0.16, 0.0001, "largura da casa = 16% da faixa")
	check_near(BoardGeometry.slot_left(0), 0.0, 0.0001, "casa 0 encosta à esquerda")
	check_near(BoardGeometry.slot_left(5) + BoardGeometry.slot_width(), 1.0, 0.0001,
		"casa 5 encosta à direita")
	check_near(BoardGeometry.aspect_ratio(false), 1402.0 / 1122.0, 0.0001, "proporção paisagem 1402:1122")
	check_near(BoardGeometry.aspect_ratio(true), 1024.0 / 1536.0, 0.0001, "proporção retrato 1024:1536")

func test_all_slots_exist() -> void:
	print("As 24 casas existem")
	var em_falta := 0
	for owner_id in ["player", "ai"]:
		for slot_type in ["frente", "retaguarda"]:
			for lane in range(6):
				if board.slot_control(owner_id, slot_type, lane) == null:
					em_falta += 1
	check(em_falta == 0, "4 faixas × 6 casas = 24 (faltam %d)" % em_falta)

	# Cada casa tem onde pendurar a carta na Fase 5
	check(board.card_holder("player", "frente", 0) != null, "casa tem suporte para a carta")

func test_apoio_edges() -> void:
	print("Pontas da retaguarda são só-Apoio")
	check(BoardGeometry.is_apoio_slot("retaguarda", 0), "retaguarda 0 é de Apoio")
	check(BoardGeometry.is_apoio_slot("retaguarda", 5), "retaguarda 5 é de Apoio")
	for lane in [1, 2, 3, 4]:
		check(not BoardGeometry.is_apoio_slot("retaguarda", lane),
			"retaguarda %d é de combate" % lane)
	for lane in range(6):
		check(not BoardGeometry.is_apoio_slot("frente", lane),
			"frente %d nunca é de Apoio" % lane)

	# E o motor concorda: nunca deixa colocar unidade nas pontas
	var engine: Game = game.engine
	var carta := {"papel": "ATIRADOR", "isApoio": false}
	check(not engine.can_place_unit("player", carta, "retaguarda", 0),
		"motor recusa unidade na retaguarda 0")
	check(not engine.can_place_unit("player", carta, "retaguarda", 5),
		"motor recusa unidade na retaguarda 5")

func test_rank_positions() -> void:
	print("Faixas nas coordenadas medidas na arte")
	# Valores do style.css: .rank.enemy-back { top: 22.0%; left: 18.0%; ... }
	var esperado := {
		"ai_retaguarda": Rect2(0.180, 0.220, 0.634, 0.118),
		"ai_frente": Rect2(0.180, 0.370, 0.634, 0.123),
		"player_frente": Rect2(0.180, 0.540, 0.634, 0.127),
		"player_retaguarda": Rect2(0.180, 0.701, 0.634, 0.131)
	}
	for chave in esperado:
		var partes: PackedStringArray = chave.split("_")
		var r: Rect2 = BoardGeometry.rank_rect(partes[0], partes[1], false)
		var e: Rect2 = esperado[chave]
		check(r.is_equal_approx(e), "%s em %.1f%% / %.1f%%" % [
			chave, e.position.y * 100.0, e.position.x * 100.0])

func test_lane_alignment() -> void:
	print("Colunas alinhadas entre frente e retaguarda")
	# A retaguarda usa o mesmo passo da frente, por isso a coluna 2 da frente
	# tem de ficar exactamente por cima da coluna 2 da retaguarda.
	for lane in range(6):
		var frente := board.slot_control("player", "frente", lane)
		var retaguarda := board.slot_control("player", "retaguarda", lane)
		if frente == null or retaguarda == null:
			check(false, "casas da coluna %d existem" % lane)
			continue
		check_near(frente.anchor_left, retaguarda.anchor_left, 0.0001,
			"coluna %d alinhada nas duas linhas" % lane)

func test_towers() -> void:
	print("Torres")
	board.set_tower("player", 30)
	var fill: ColorRect = board._tower_fills["player"]
	var label: Label = board._tower_labels["player"]
	check_near(fill.anchor_right, 1.0, 0.001, "vida cheia enche a barra")
	check(label.text == "30/30", "mostra 30/30")

	board.set_tower("player", 15)
	check_near(fill.anchor_right, 0.5, 0.001, "metade da vida, meia barra")
	check(label.text == "15/30", "mostra 15/30")

	board.set_tower("player", 0)
	check_near(fill.anchor_right, 0.0, 0.001, "sem vida, barra vazia")

	# Vida negativa não pode encolher a barra para lá do zero
	board.set_tower("player", -5)
	check_near(fill.anchor_right, 0.0, 0.001, "vida negativa fica a zero")
	check(label.text == "0/30", "mostra 0/30")

func test_ruined_board() -> void:
	print("Tabuleiro arruinado abaixo de 25%")
	board.update_board_art(30, 30)
	check(not board.is_ruined(), "torres cheias: tabuleiro inteiro")

	board.update_board_art(30, 8)
	check(not board.is_ruined(), "8/30 ainda está acima de 25%")

	board.update_board_art(30, 7)
	check(board.is_ruined(), "7/30 passa o limite: tabuleiro arruinado")

	board.update_board_art(30, 30)
	check(not board.is_ruined(), "recupera se as torres voltarem a subir")

# ---------------------------------------------------------------- zonas do PDF

func test_deck_zones() -> void:
	print("Zonas de baralho nas pontas da retaguarda")
	# TABULEIRO.pdf: espelhado. O jogador tem o Apoio à esquerda e o Militar
	# à direita; a IA ao contrário.
	check_eq(BoardGeometry.deck_kind("player", 0), "apoio", "jogador: esquerda é o Apoio")
	check_eq(BoardGeometry.deck_kind("player", 5), "militar", "jogador: direita é o Militar")
	check_eq(BoardGeometry.deck_kind("ai", 0), "militar", "IA: esquerda é o Militar")
	check_eq(BoardGeometry.deck_kind("ai", 5), "apoio", "IA: direita é o Apoio")
	check_eq(BoardGeometry.deck_kind("player", 2), "", "as colunas de combate não são baralhos")

	# Continuam a não receber unidades
	check(BoardGeometry.is_deck_slot("retaguarda", 0), "ponta 0 é baralho")
	check(BoardGeometry.is_deck_slot("retaguarda", 5), "ponta 5 é baralho")
	check(not BoardGeometry.is_deck_slot("retaguarda", 2), "coluna 2 não")
	check(not BoardGeometry.is_deck_slot("frente", 0), "a frente nunca é baralho")

	# O contador segue o motor
	board.set_deck_count("player", "militar", 14)
	board.set_deck_count("player", "apoio", 160)
	var militar := board.slot_control("player", "retaguarda", 5)
	var apoio := board.slot_control("player", "retaguarda", 0)
	check_eq((militar.get_node("Count") as Label).text, "14", "Militar mostra 14")
	check_eq((apoio.get_node("Count") as Label).text, "160", "Apoio mostra 160")

func test_graveyard_zone() -> void:
	print("Cemitério ao centro")
	for owner_id in ["player", "ai"]:
		var zona := board.graveyard_zone(owner_id)
		check(zona != null, "%s tem cemitério" % owner_id)
		check(board.graveyard_holder(owner_id) != null, "%s tem onde pendurar a carta" % owner_id)

	# Centrado, e de cada lado do tabuleiro
	var r_player := BoardGeometry.graveyard_rect("player", false)
	var r_ai := BoardGeometry.graveyard_rect("ai", false)
	check_near(r_player.position.x + r_player.size.x * 0.5, 0.5, 0.001, "centrado na horizontal")
	check(r_ai.position.y < 0.25, "o da IA fica em cima (%.2f)" % r_ai.position.y)
	check(r_player.position.y > 0.75, "o do jogador fica em baixo (%.2f)" % r_player.position.y)

	# Não colide com as faixas de retaguarda
	var ret_ai := BoardGeometry.rank_rect("ai", "retaguarda", false)
	var ret_player := BoardGeometry.rank_rect("player", "retaguarda", false)
	check(r_ai.position.y + r_ai.size.y <= ret_ai.position.y, "o da IA fica acima da retaguarda")
	check(r_player.position.y >= ret_player.position.y + ret_player.size.y, "o do jogador fica abaixo")

	board.set_graveyard_count("player", 7)
	var label := board.graveyard_zone("player").get_node("Count") as Label
	check_eq(label.text, "7", "contador mostra 7")

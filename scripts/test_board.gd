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
	board = game.get_node("BoardArea/Board")

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
	# Fórmula uniforme — só serve o retrato agora (paisagem tem cada casa
	# medida à parte, ver SLOTS_LANDSCAPE).
	check_near(BoardGeometry.slot_width(), 0.16, 0.0001, "largura da casa (retrato) = 16% da faixa")
	check_near(BoardGeometry.slot_left(0), 0.0, 0.0001, "casa 0 encosta à esquerda")
	check_near(BoardGeometry.slot_left(5) + BoardGeometry.slot_width(), 1.0, 0.0001,
		"casa 5 encosta à direita")
	check_near(BoardGeometry.aspect_ratio(false), 4963.0 / 3509.0, 0.0001, "proporção paisagem 4963:3509")
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
	print("Faixas nas coordenadas medidas no TABULEIRO.pdf (Ago 2026)")
	# Rect2 = união das 6 casas medidas de cada faixa (SLOTS_LANDSCAPE).
	var esperado := {
		"ai_retaguarda": Rect2(0.1830, 0.1981, 0.6313, 0.0721),
		"ai_frente": Rect2(0.2466, 0.3029, 0.5037, 0.0835),
		"player_frente": Rect2(0.2257, 0.4243, 0.5456, 0.0980),
		"player_retaguarda": Rect2(0.0975, 0.5660, 0.8021, 0.1166)
	}
	for chave in esperado:
		var partes: PackedStringArray = chave.split("_")
		var r: Rect2 = BoardGeometry.rank_rect(partes[0], partes[1], false)
		var e: Rect2 = esperado[chave]
		# Tolerância larga: e é a união das 6 casas arredondadas a 4 casas
		# decimais, por isso a soma pode divergir da medição original em
		# décimas de milésimo — ruído de arredondamento, não um erro real.
		var ok := r.position.distance_to(e.position) < 0.001 \
			and r.size.distance_to(e.size) < 0.001
		check(ok, "%s em %.1f%% / %.1f%%" % [
			chave, e.position.y * 100.0, e.position.x * 100.0])

func test_lane_alignment() -> void:
	print("Colunas de combate alinhadas entre frente e retaguarda")
	# A retaguarda só tem unidade nos lanes 1-4 (0 e 5 são baralho, medidos
	# mais afastados do centro do que uma simples continuação da frente daria
	# — ver o comentário no topo de BoardGeometry.gd). Só os 4 lanes de
	# combate partilhados é que têm de alinhar, e com folga: são duas medições
	# independentes no PDF, não a mesma fórmula.
	for lane in [1, 2, 3, 4]:
		var frente := board.slot_control("player", "frente", lane)
		var retaguarda := board.slot_control("player", "retaguarda", lane)
		if frente == null or retaguarda == null:
			check(false, "casas da coluna %d existem" % lane)
			continue
		check_near(frente.anchor_left, retaguarda.anchor_left, 0.03,
			"coluna %d aproximadamente alinhada nas duas linhas" % lane)

	# Os lanes 0 e 5 são deliberadamente diferentes: baralho na retaguarda,
	# unidade na frente — não fazia sentido alinhá-los.
	var frente0 := board.slot_control("player", "frente", 0)
	var retaguarda0 := board.slot_control("player", "retaguarda", 0)
	check(retaguarda0.anchor_left < frente0.anchor_left,
		"lane 0: o baralho da retaguarda fica mais para fora que a frente")

func test_towers() -> void:
	print("Torres")
	# Game.TOWER_MAX / BoardRenderer.TOWER_MAX = 100 (não 30 — desactualizado).
	var maximo := BoardRenderer.TOWER_MAX
	board.set_tower("player", maximo)
	var fill: ColorRect = board._tower_fills["player"]
	var label: Label = board._tower_labels["player"]
	check_near(fill.anchor_right, 1.0, 0.001, "vida cheia enche a barra")
	check(label.text == "%d/%d" % [maximo, maximo], "mostra %d/%d" % [maximo, maximo])

	board.set_tower("player", maximo / 2)
	check_near(fill.anchor_right, 0.5, 0.001, "metade da vida, meia barra")
	check(label.text == "%d/%d" % [maximo / 2, maximo], "mostra %d/%d" % [maximo / 2, maximo])

	board.set_tower("player", 0)
	check_near(fill.anchor_right, 0.0, 0.001, "sem vida, barra vazia")

	# Vida negativa não pode encolher a barra para lá do zero
	board.set_tower("player", -5)
	check_near(fill.anchor_right, 0.0, 0.001, "vida negativa fica a zero")
	check(label.text == "0/%d" % maximo, "mostra 0/%d" % maximo)

func test_ruined_board() -> void:
	print("Tabuleiro arruinado abaixo de 25%")
	var maximo := BoardRenderer.TOWER_MAX
	board.update_board_art(maximo, maximo)
	check(not board.is_ruined(), "torres cheias: tabuleiro inteiro")

	board.update_board_art(maximo, 26)
	check(not board.is_ruined(), "26%% ainda está acima de 25%%")

	board.update_board_art(maximo, 25)
	check(board.is_ruined(), "25%% passa o limite: tabuleiro arruinado")

	board.update_board_art(maximo, maximo)
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
	check_near(r_player.position.x + r_player.size.x * 0.5, 0.5, 0.002, "centrado na horizontal")
	check(r_ai.position.y < 0.5, "o da IA fica na metade de cima (%.2f)" % r_ai.position.y)
	check(r_player.position.y > 0.5, "o do jogador fica na metade de baixo (%.2f)" % r_player.position.y)

	# Não colide com as faixas de retaguarda
	var ret_ai := BoardGeometry.rank_rect("ai", "retaguarda", false)
	var ret_player := BoardGeometry.rank_rect("player", "retaguarda", false)
	check(r_ai.position.y + r_ai.size.y <= ret_ai.position.y, "o da IA fica acima da retaguarda")
	check(r_player.position.y >= ret_player.position.y + ret_player.size.y, "o do jogador fica abaixo")

	board.set_graveyard_count("player", 7)
	var label := board.graveyard_zone("player").get_node("Count") as Label
	check_eq(label.text, "7", "contador mostra 7")

extends SceneTree

# Testes do BoardSpec (geometria do tabuleiro inclinado, homografia).
#
#   godot --headless --path . --script res://scripts/test_board_spec.gd

var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("\n=== CORREDOR — testes de BoardSpec ===\n")

	# --script não regista class_name globais, por isso carrega-se à mão.
	var spec = load("res://scripts/BoardSpec.gd").new()
	check(spec.load_spec(), "carrega tabuleiro_spec.json")
	check_eq(spec.casas.size(), 40, "40 casas")

	test_ids_unicos(spec)
	test_grupos(spec)
	test_homografia_inversa(spec)
	test_toque(spec)
	test_ordem_desenho(spec)

	print("\n--- %d passaram, %d falharam ---\n" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func check(cond: bool, label: String) -> void:
	if cond:
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
		print("  FALHA %s  (esperado %.4f, obtido %.4f)" % [label, expected, actual])

func test_ids_unicos(spec) -> void:
	print("Identificadores")
	var vistos := {}
	var duplicados := 0
	for c in spec.casas:
		var id := str(c["id"])
		if vistos.has(id):
			duplicados += 1
		vistos[id] = true
	check_eq(duplicados, 0, "sem ids duplicados")
	check(not spec.by_id("jogador_L1_C1").is_empty(), "encontra jogador_L1_C1")
	check(spec.by_id("nao-existe").is_empty(), "id inexistente devolve vazio")

func test_grupos(spec) -> void:
	print("Grupos e contagens")
	check_eq(spec.casas_do_grupo("mao_adversario").size(), 8, "8 casas na mão do adversário")
	check_eq(spec.casas_do_grupo("mao_jogador").size(), 8, "8 casas na mão do jogador")

	var l1_jogador := 0
	var l2_jogador := 0
	for c in spec.casas:
		if str(c.get("lado","")) == "jogador":
			if c.get("linha") == 1:
				l1_jogador += 1
			elif c.get("linha") == 2:
				l2_jogador += 1
	check_eq(l1_jogador, 6, "6 casas na Linha 1 do jogador")
	check_eq(l2_jogador, 4, "4 casas na Linha 2 do jogador (mais os 2 baralhos)")

	check(not spec.casa_baralho("militar", "jogador").is_empty(), "baralho militar do jogador existe")
	check(not spec.casa_baralho("tatico", "jogador").is_empty(), "baralho tático do jogador existe")
	check(not spec.casa_baralho("militar", "adversario").is_empty(), "baralho militar do adversário existe")
	check(not spec.casa_baralho("tatico", "adversario").is_empty(), "baralho tático do adversário existe")

func test_homografia_inversa(spec) -> void:
	print("Homografia — ida e volta")
	# Projecta um ponto da planta para o ecrã e volta: tem de dar a mesma
	# coordenada (a menos de erro de ponto flutuante).
	var pontos := [Vector2(0.1, 0.1), Vector2(0.5, 0.5), Vector2(0.9, 0.9), Vector2(0.2, 0.8)]
	for p in pontos:
		var tela = spec.project(p.x, p.y)
		var volta = spec.unproject(tela.x, tela.y)
		check_near(volta.x, p.x, 0.001, "ida-e-volta x em (%.1f,%.1f)" % [p.x, p.y])
		check_near(volta.y, p.y, 0.001, "ida-e-volta y em (%.1f,%.1f)" % [p.x, p.y])

func test_toque(spec) -> void:
	print("Detecção de toque")
	# O centro de ecrã de cada casa tem de devolver essa mesma casa.
	var erros := 0
	for c in spec.casas:
		var centro = spec.screen_center(c)
		var achada = spec.casa_no_toque(centro.x, centro.y)
		if str(achada.get("id","")) != str(c["id"]):
			erros += 1
	check_eq(erros, 0, "o centro de cada casa devolve a própria casa (40 testadas)")

func test_ordem_desenho(spec) -> void:
	print("Ordem de desenho")
	var ordem = spec.ordem_de_desenho()
	check_eq(ordem.size(), 40, "ordem de desenho tem as 40 casas")
	check_eq(str(ordem[0]["id"]), "mao_adversario_1", "começa pela mão do adversário")
	check_eq(str(ordem[ordem.size()-1]["id"]), "mao_jogador_8", "acaba na mão do jogador")

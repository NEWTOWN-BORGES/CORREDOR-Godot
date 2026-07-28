extends SceneTree

# Testes de carregamento de assets (Fase 2).
#
#   godot --headless --script res://scripts/test_assets.gd
#
# Verifica que as 427 cartas resolvem para um ficheiro que existe e que
# carrega mesmo, que a cache respeita o limite, e mede quanto demora.
#
# Corre sem o autoload (os --script não instanciam autoloads), por isso
# instancia o CardLoader à mão.

var loader: Node = null
var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("\n=== CORREDOR — testes de assets ===\n")

	loader = load("res://scripts/CardLoader.gd").new()
	if not loader.load_all():
		print("FALHA: não carregou cartas.json")
		quit(1)
		return

	test_json_loaded()
	test_index_by_id()
	test_path_resolution()
	test_every_card_texture_exists()
	test_board_textures()
	test_cache_limit()
	test_cache_hits()
	test_load_timing()

	print("\n--- %d passaram, %d falharam ---\n" % [_passed, _failed])

	# Larga as texturas antes de sair, senão o Godot queixa-se de recursos
	# ainda em uso (o loader é um Node solto, não está na árvore).
	loader.clear_texture_cache()
	loader.free()
	loader = null

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

func all_cards() -> Array:
	var out: Array = []
	out.append_array(loader.unidades)
	out.append_array(loader.apoios)
	out.append_array(loader.taticos)
	return out

# ---------------------------------------------------------------- testes

func test_json_loaded() -> void:
	print("cartas.json")
	check_eq((loader.unidades as Array).size(), 100, "100 unidades")
	check_eq((loader.apoios as Array).size(), 27, "27 apoios")
	check_eq((loader.taticos as Array).size(), 300, "300 táticos")

func test_index_by_id() -> void:
	print("Índice por id")
	var primeira: Dictionary = loader.unidades[0]
	var id := str(primeira.get("id", ""))
	var achada: Dictionary = loader.by_id(id)
	check(not achada.is_empty(), "encontra %s pelo id" % id)
	check_eq(str(achada.get("nome", "")), str(primeira.get("nome", "")), "é a mesma carta")
	check(loader.by_id("nao-existe").is_empty(), "id inexistente devolve vazio")

func test_path_resolution() -> void:
	print("Resolução de caminhos")
	# unidades e apoios trazem o caminho completo
	var unidade: Dictionary = loader.unidades[0]
	var p1: String = loader.resolve_image_path(unidade)
	check(p1.begins_with("res://assets/cartas-3d/"), "unidade → res://assets/cartas-3d/…")

	var apoio: Dictionary = loader.apoios[0]
	var p2: String = loader.resolve_image_path(apoio)
	check(p2.begins_with("res://assets/apoios-3d/"), "apoio → res://assets/apoios-3d/…")

	# táticos trazem só o nome do ficheiro
	var tatico: Dictionary = loader.taticos[0]
	check(not str(tatico.get("imagem", "")).contains("/"), "tático no JSON não tem pasta")
	var p3: String = loader.resolve_image_path(tatico)
	check(p3.begins_with("res://assets/taticos-3d/"), "tático → res://assets/taticos-3d/…")

	check_eq(loader.resolve_image_path({}), "", "carta sem imagem devolve vazio")

func test_every_card_texture_exists() -> void:
	print("Todas as cartas têm arte no disco")
	var em_falta: Array = []
	for c in all_cards():
		var path: String = loader.resolve_image_path(c)
		if path == "" or not ResourceLoader.exists(path):
			em_falta.append("%s (%s) → %s" % [c.get("id", "?"), c.get("nome", "?"), path])

	check_eq(em_falta.size(), 0, "427 cartas com arte")
	for linha in em_falta.slice(0, 10):
		print("        em falta: %s" % linha)

func test_board_textures() -> void:
	print("Tabuleiros")
	for ruined in [false, true]:
		for portrait in [false, true]:
			var path: String = loader.board_texture_path(ruined, portrait)
			check(ResourceLoader.exists(path), path.get_file())

func test_cache_limit() -> void:
	print("Cache respeita o limite")
	loader.clear_texture_cache()
	var limite: int = loader.TEXTURE_CACHE_LIMIT
	var cartas := all_cards()
	var quantas: int = min(limite + 20, cartas.size())

	for i in range(quantas):
		loader.texture_for(cartas[i])

	check(loader.cache_size() <= limite, "carregadas %d, cache ficou em %d (limite %d)" % [
		quantas, loader.cache_size(), limite
	])

func test_cache_hits() -> void:
	print("Cache devolve a mesma textura")
	loader.clear_texture_cache()
	var carta: Dictionary = loader.unidades[0]

	var t1: Texture2D = loader.texture_for(carta)
	check(t1 != null, "primeira carga devolve textura")

	var hits_antes: int = loader.stats_hits
	var t2: Texture2D = loader.texture_for(carta)
	check(t2 == t1, "segunda chamada devolve a mesma instância")
	check_eq(loader.stats_hits, hits_antes + 1, "contabilizou como acerto de cache")

	if t1 != null:
		check_eq(t1.get_width(), 750, "largura 750")
		check_eq(t1.get_height(), 1050, "altura 1050")

func test_load_timing() -> void:
	print("Tempo de carregamento")
	loader.clear_texture_cache()
	var cartas := all_cards()
	var amostra: int = min(60, cartas.size())

	var inicio := Time.get_ticks_msec()
	for i in range(amostra):
		loader.texture_for(cartas[i])
	var decorrido := Time.get_ticks_msec() - inicio

	var por_carta := float(decorrido) / float(amostra)
	print("        %d cartas em %d ms (%.1f ms por carta)" % [amostra, decorrido, por_carta])
	check(por_carta < 50.0, "menos de 50 ms por carta")
	print("        %s" % loader.stats_line())

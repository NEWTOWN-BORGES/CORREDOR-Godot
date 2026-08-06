extends Node

# Testes de integridade — o que o resto da suite não cobre (cartas a sumir).
#
#   godot --headless --path . res://scenes/TestConservacao.tscn
#
# Duas perguntas:
#   1. Toda a arte das 570 cartas resolve para um ficheiro que existe?
#   2. Nenhuma carta se perde durante uma partida? Uma carta só pode estar
#      numa zona; a soma de todas as zonas tem de ser constante do princípio
#      ao fim. É assim que se apanha "algumas cartas desaparecem".

var _passed := 0
var _failed := 0
var _falhas: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== CORREDOR — integridade das cartas ===\n")
	test_toda_a_arte_resolve()
	test_ids_unicos()
	await test_conservacao_em_partidas()
	_relatorio()

func ok(cond: bool, nome: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_falhas.append(nome)
		print("  FALHOU  %s" % nome)

func _relatorio() -> void:
	print("\n--- %d passaram, %d falharam ---" % [_passed, _failed])
	if _failed > 0:
		print("\nFalhas:")
		for f in _falhas:
			print("  · %s" % f)
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------------------------------------------------------- arte

func test_toda_a_arte_resolve() -> void:
	print("Arte de todas as cartas")
	Cards.load_all()
	var grupos := {"unidades": Cards.unidades, "apoios": Cards.apoios, "taticos": Cards.taticos}
	var total := 0
	for nome in grupos:
		var em_falta: Array[String] = []
		for c in grupos[nome]:
			total += 1
			var caminho := Cards.resolve_image_path(c)
			if caminho == "" or not ResourceLoader.exists(caminho):
				em_falta.append("%s -> %s" % [str(c.get("id", "?")), caminho])
		ok(em_falta.is_empty(), "%s: arte toda existe (%d em falta%s)" % [
			nome, em_falta.size(),
			("" if em_falta.is_empty() else " — ex: " + em_falta[0])
		])
	ok(total == 570, "570 cartas carregadas (tem %d)" % total)

func test_ids_unicos() -> void:
	print("Identificadores")
	var vistos := {}
	var repetidos: Array[String] = []
	for c in Cards.unidades + Cards.apoios + Cards.taticos:
		var id := str(c.get("id", ""))
		if id == "":
			repetidos.append("(carta sem id)")
		elif vistos.has(id):
			repetidos.append(id)
		else:
			vistos[id] = true
	ok(repetidos.is_empty(), "ids únicos (%d repetidos%s)" % [
		repetidos.size(), ("" if repetidos.is_empty() else " — ex: " + repetidos[0])
	])

# ---------------------------------------------------------------- conservação

# Conta cada carta, esteja onde estiver — incluindo os Equipamentos, que saem
# da mão e passam a viver dentro da unidade que equiparam.
func _censo(engine: Game, owner_id: String) -> Dictionary:
	var p: Dictionary = engine.players[owner_id]
	var no_tabuleiro := 0
	var equipados := 0
	for c in p["front"]:
		if c != null:
			no_tabuleiro += 1
			equipados += (c.get("equipamentos", []) as Array).size()
	for c in p["back"]:
		if c != null:
			no_tabuleiro += 1
			equipados += (c.get("equipamentos", []) as Array).size()
	# As unidades mortas levam o equipamento com elas para o cemitério.
	for c in p["graveyard"]:
		equipados += (c.get("equipamentos", []) as Array).size()
	return {
		"militaryDeck": (p["militaryDeck"] as Array).size(),
		"reinforcements": (p["reinforcements"] as Array).size(),
		"tabuleiro": no_tabuleiro,
		"equipados": equipados,
		"graveyard": (p["graveyard"] as Array).size(),
		"deck": (p["deck"] as Array).size(),
		"hand": (p["hand"] as Array).size(),
		"discard": (p["discard"] as Array).size(),
		"activeTactics": (p["activeTactics"] as Array).size(),
	}

func _total(censo: Dictionary) -> int:
	var t := 0
	for k in censo:
		t += censo[k]
	return t

# Só as zonas que mudaram entre dois passos — aponta o dedo à culpada.
func _delta(antes: Dictionary, depois: Dictionary) -> String:
	var partes: Array[String] = []
	for k in depois:
		var d: int = int(depois[k]) - int(antes.get(k, 0))
		if d != 0:
			partes.append("%s %+d (%d->%d)" % [k, d, int(antes.get(k, 0)), int(depois[k])])
	return ", ".join(partes) if not partes.is_empty() else "(nada)"

func _detalhe(censo: Dictionary) -> String:
	var partes: Array[String] = []
	for k in censo:
		partes.append("%s=%d" % [k, censo[k]])
	return ", ".join(partes)

func test_conservacao_em_partidas() -> void:
	print("Conservação de cartas ao longo da partida")
	var faccoes := ["reinos", "coro", "verdemanto", "semceu", "despertos"]
	var cartas := Cards.as_dictionary()

	for i in range(faccoes.size()):
		var eu: String = faccoes[i]
		var ele: String = faccoes[(i + 1) % faccoes.size()]

		var engine := Game.new()
		var baralho_meu := DeckManager.build_faction_deck(cartas, eu)
		var baralho_dele := DeckManager.build_faction_deck(cartas, ele)
		engine.init_game(baralho_meu, baralho_dele, Callable())

		var ia_a := AIPlayer.new("player")
		var ia_b := AIPlayer.new("ai")

		var inicial_p := _total(_censo(engine, "player"))
		var inicial_a := _total(_censo(engine, "ai"))

		var perdeu_p := ""
		var perdeu_a := ""
		var guarda := 0
		var ant_p := _censo(engine, "player")
		var ant_a := _censo(engine, "ai")
		while engine.phase != "gameover" and guarda < 400:
			guarda += 1
			if engine.phase == "placement":
				if engine.active_player == "player":
					ia_a.step(engine)
				else:
					ia_b.step(engine)

			var cen_p := _censo(engine, "player")
			var cen_a := _censo(engine, "ai")
			if _total(cen_p) != inicial_p and perdeu_p == "":
				perdeu_p = "ronda %d: %d -> %d  |  mudou: %s" % [
					engine.current_round, inicial_p, _total(cen_p), _delta(ant_p, cen_p)]
			if _total(cen_a) != inicial_a and perdeu_a == "":
				perdeu_a = "ronda %d: %d -> %d  |  mudou: %s" % [
					engine.current_round, inicial_a, _total(cen_a), _delta(ant_a, cen_a)]
			ant_p = cen_p
			ant_a = cen_a

		ok(perdeu_p == "", "%s vs %s — jogador não perde cartas  %s" % [eu, ele, perdeu_p])
		ok(perdeu_a == "", "%s vs %s — IA não perde cartas  %s" % [eu, ele, perdeu_a])
		ok(guarda < 400, "%s vs %s — partida termina (não fica presa)" % [eu, ele])

		# Game é RefCounted — liberta-se sozinho, não se chama free().
		await get_tree().process_frame

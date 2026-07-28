extends SceneTree

# Simulação com as cartas reais — exercita o AbilityDispatcher com os textos
# de habilidade que estão mesmo impressos na arte.
#
#   godot --headless --script res://scripts/test_simulation.gd
#
# Joga todas as combinações de facções até ao fim e reporta:
#   - partidas que rebentaram
#   - textos de habilidade sem tradução no dispatcher

const GAMES_PER_PAIR := 3

var cartas: Dictionary = {}
var _failed := 0

func _initialize() -> void:
	print("\n=== CORREDOR — simulação com cartas reais ===\n")
	if not _load_cards():
		quit(1)
		return

	_report_missing_abilities()
	_play_all_matchups()

	print("\n--- %d problemas ---\n" % _failed)
	quit(1 if _failed > 0 else 0)

func _load_cards() -> bool:
	var path := "res://resources/cartas.json"
	if not FileAccess.file_exists(path):
		print("FALHA: %s não existe" % path)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("FALHA: cartas.json inválido")
		return false
	cartas = parsed
	print("%d unidades, %d apoios, %d táticos\n" % [
		(cartas["unidades"] as Array).size(),
		(cartas["apoios"] as Array).size(),
		(cartas.get("taticos", []) as Array).size()
	])
	return true

# Verifica que todo o texto de habilidade impresso nas cartas tem tradução.
func _report_missing_abilities() -> void:
	var dispatcher := AbilityDispatcher.new()
	var missing := {}
	for u in cartas["unidades"]:
		var texto := str(u.get("habilidade_texto", ""))
		if texto == "":
			continue
		if dispatcher.get_unit_ability(texto).is_empty():
			missing[texto] = str(u.get("nome", "?"))

	var missing_apoios := {}
	for a in cartas["apoios"]:
		var id := str(a.get("id", ""))
		if dispatcher.get_apoio_ability(id).is_empty():
			missing_apoios[id] = str(a.get("nome", "?"))

	print("Cobertura de habilidades")
	print("  unidades traduzidas: %d" % dispatcher.UNIT_ABILITIES.size())
	print("  apoios traduzidos:   %d" % dispatcher.APOIO_ABILITIES.size())

	if missing.is_empty():
		print("  ok   todas as habilidades de unidade têm tradução")
	else:
		_failed += missing.size()
		print("  FALHA %d textos de unidade sem tradução:" % missing.size())
		for texto in missing:
			print("        [%s] %s" % [missing[texto], texto])

	if missing_apoios.is_empty():
		print("  ok   todos os apoios têm tradução")
	else:
		_failed += missing_apoios.size()
		print("  FALHA %d apoios sem tradução:" % missing_apoios.size())
		for id in missing_apoios:
			print("        %s — %s" % [id, missing_apoios[id]])
	print("")

func _play_all_matchups() -> void:
	var factions := DeckManager.list_factions(cartas)
	print("Partidas completas (%d facções, %d por par)" % [factions.size(), GAMES_PER_PAIR])

	for a in factions:
		for b in factions:
			var wins := {}
			var rounds_total := 0
			for i in range(GAMES_PER_PAIR):
				var outcome := _play_one(a, b)
				if outcome.is_empty():
					_failed += 1
					print("  FALHA %s vs %s rebentou" % [a, b])
					break
				var w := str(outcome["winner"])
				wins[w] = int(wins.get(w, 0)) + 1
				rounds_total += int(outcome["rounds"])
			if not wins.is_empty():
				print("  ok   %-12s vs %-12s  %s   (média %.1f turnos)" % [
					a, b, _fmt_wins(wins), float(rounds_total) / GAMES_PER_PAIR
				])

func _fmt_wins(wins: Dictionary) -> String:
	var parts := []
	for k in wins:
		parts.append("%s×%d" % [k, wins[k]])
	return ", ".join(parts)

# Joga uma partida inteira com ambos os lados a jogar ao calhas.
func _play_one(faction_a: String, faction_b: String) -> Dictionary:
	var g := Game.new()
	g.init_game(
		DeckManager.build_faction_deck(cartas, faction_a),
		DeckManager.build_faction_deck(cartas, faction_b),
		func(_msg): pass
	)

	var guard := 0
	while g.phase != "gameover" and guard < 4000:
		guard += 1
		var who := g.active_player
		if not _take_random_action(g, who):
			g.pass_turn(who)

	if g.phase != "gameover":
		return {}
	return {"winner": g.winner, "rounds": g.current_round}

# Tenta uma jogada qualquer; devolve false se não houver nada a fazer.
func _take_random_action(g: Game, who: String) -> bool:
	var p: Dictionary = g.players[who]

	# 1. Carta da mão — Apoios e Táticas saem pela mesma porta
	var hand: Array = p["hand"]
	for i in range(hand.size()):
		var carta: Dictionary = hand[i]
		var spec := {}
		if carta.get("isApoio", false):
			spec = _apoio_target_spec(g, who, str(carta.get("id", "")))
		elif str(carta.get("tipo_tatico", "")) == "Equipamento":
			var friends: Array = g.allies(who)
			if friends.is_empty():
				continue
			spec["targetCard"] = friends[randi() % friends.size()]
		if g.play_hand_card(who, i, spec).get("ok", false):
			return true

	# 2. Reforço da reserva numa casa livre
	var reserva: Array = p["reinforcements"]
	for i in range(reserva.size()):
		for slot_type in ["frente", "retaguarda"]:
			var lanes: Array = range(Game.FRONT_LANES) if slot_type == "frente" else Game.BACK_LANES
			for lane in lanes:
				if g.can_place_unit(who, reserva[i], slot_type, lane):
					if g.place_reinforcement(who, i, slot_type, lane).get("ok", false):
						return true
	return false

# Escolhe um alvo plausível conforme o que o Apoio pede.
func _apoio_target_spec(g: Game, who: String, apoio_id: String) -> Dictionary:
	var dispatcher: AbilityDispatcher = g.abilities
	var def := dispatcher.get_apoio_ability(apoio_id)
	var needs = def.get("needsTarget")

	if needs == "ally":
		var friends: Array = g.allies(who)
		if friends.is_empty():
			return {}
		return {"target": friends[randi() % friends.size()]}
	if needs == "enemy":
		var foes: Array = g.enemies(who)
		if foes.is_empty():
			return {}
		return {"target": foes[randi() % foes.size()]}
	if needs == "allyPair":
		var friends: Array = g.allies(who)
		if friends.size() < 2:
			return {}
		return {"from": friends[0], "to": friends[1]}
	return {}

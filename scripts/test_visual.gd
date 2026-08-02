extends Node

# Testes de "a carta está mesmo no ecrã" (o que faltava à suite).
#
#   godot --headless --path . res://scenes/TestVisual.tscn
#
# A suite existente verifica o motor e casos isolados de UI. Este teste joga
# uma partida inteira na cena real e, a cada jogada, pergunta:
#
#   · toda a carta que o motor diz estar numa casa tem uma CardView lá?
#   · essa CardView tem textura, ou é um rectângulo invisível?
#   · a mão no ecrã tem tantas cartas quantas o motor diz?
#   · a reserva de reforços idem?
#
# É a diferença entre "a carta existe" e "a carta vê-se".

var _passed := 0
var _failed := 0
var _falhas: Array[String] = []

var game: Control = null
var engine: Game = null
var board: BoardRenderer = null

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== CORREDOR — as cartas vêem-se? ===\n")
	var faccoes := ["reinos", "coro", "verdemanto", "semceu", "despertos"]
	for i in range(faccoes.size()):
		var eu: String = faccoes[i]
		var ele: String = faccoes[(i + 1) % faccoes.size()]
		print("\n· %s contra %s" % [eu, ele])

		Session.set_match(eu, ele)
		game = load("res://scenes/Game.tscn").instantiate()
		add_child(game)
		await get_tree().process_frame
		# Rápido, mas > 0: com 0 as animações são saltadas e o caminho que
		# põe a carta a modulate.a = 0 nunca é exercitado.
		game.set_animation_speed(6.0)
		engine = game.engine
		board = game.get_node("BoardArea/Board")
		await get_tree().process_frame

		await test_partida_inteira()

		remove_child(game)
		game.queue_free()
		await get_tree().process_frame

	# Uma textura que falha a carregar é uma carta invisível no ecrã.
	print("\n%s" % Cards.stats_line())
	ok(Cards.stats_failures == 0, "nenhuma textura falhou (%d falhas)" % Cards.stats_failures)
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

# ------------------------------------------------------------------ ajudas

func _card_view_em(owner_id: String, slot_type: String, lane: int) -> CardView:
	var holder := board.card_holder(owner_id, slot_type, lane)
	if holder == null:
		return null
	for child in holder.get_children():
		if child is CardView:
			return child as CardView
	return null

func _tem_textura(vista: CardView) -> bool:
	var arte := vista.get_node_or_null("Art") as TextureRect
	return arte != null and arte.texture != null

# ------------------------------------------------------------------ teste

func test_partida_inteira() -> void:
	print("Partida completa, a verificar o ecrã a cada jogada")

	var ia_p := AIPlayer.new("player")
	var ia_a := AIPlayer.new("ai")

	var sem_vista := {}      # descrição -> primeira ocorrência
	var sem_textura := {}
	var tamanho_zero := {}
	var fora_do_ecra := {}
	var invisivel := {}      # existe, tem arte, mas está transparente ou encolhida
	var mao_errada := ""
	var reforcos_errados := ""
	var passos := 0
	var ecra := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)

	while engine.phase != "gameover" and passos < 260:
		passos += 1
		if engine.phase == "placement":
			if engine.active_player == "player":
				ia_p.step(engine)
			else:
				ia_a.step(engine)
		game._render_game()
		# Frames que cheguem para as animações de entrada terminarem. Uma
		# carta ainda transparente depois disto ficou assim para sempre.
		for _f in range(12):
			await get_tree().process_frame

		# 1. cada carta do motor tem vista, e a vista tem arte
		for owner_id in ["player", "ai"]:
			var p: Dictionary = engine.players[owner_id]
			for slot_type in ["frente", "retaguarda"]:
				var arr: Array = p["front"] if slot_type == "frente" else p["back"]
				for lane in range(Game.FRONT_LANES):
					if BoardGeometry.is_deck_slot(slot_type, lane):
						continue
					var card = arr[lane]
					if card == null:
						continue
					var vista := _card_view_em(owner_id, slot_type, lane)
					var onde := "%s %s[%d] %s" % [owner_id, slot_type, lane, str(card.get("nome", "?"))]
					if vista == null:
						if not sem_vista.has(onde):
							sem_vista[onde] = "ronda %d" % engine.current_round
						continue
					if not _tem_textura(vista):
						if not sem_textura.has(onde):
							sem_textura[onde] = "ronda %d" % engine.current_round
					# Existir e ter arte não chega: tem de estar visível.
					if vista.modulate.a < 0.9 or vista.scale.x < 0.9:
						if not invisivel.has(onde):
							invisivel[onde] = "%s alpha=%.2f escala=%.2f (ronda %d)" % [
								onde, vista.modulate.a, vista.scale.x, engine.current_round]
					if vista.size.x <= 1.0 or vista.size.y <= 1.0:
						if not tamanho_zero.has(onde):
							tamanho_zero[onde] = "%s tamanho %s" % [onde, str(vista.size)]
					elif not ecra.intersects(Rect2(vista.global_position, vista.size)):
						if not fora_do_ecra.has(onde):
							fora_do_ecra[onde] = "%s em %s (ecrã %s)" % [
								onde, str(vista.global_position), str(ecra.size)]

		# 2. a mão desenhada bate com a do motor
		var mao_motor: int = (engine.players["player"]["hand"] as Array).size()
		var mao_ecra := 0
		for child in game.hand_container.get_children():
			if child is CardView:
				mao_ecra += 1
				var v := child as CardView
				var nome := "mão: %s" % str(v.card.get("nome", "?"))
				if v.size.x <= 1.0 or v.size.y <= 1.0:
					if not tamanho_zero.has(nome):
						tamanho_zero[nome] = "%s tamanho %s" % [nome, str(v.size)]
				elif not ecra.intersects(Rect2(v.global_position, v.size)):
					if not fora_do_ecra.has(nome):
						fora_do_ecra[nome] = "%s em %s (ecrã %s)" % [
							nome, str(v.global_position), str(ecra.size)]
		if mao_motor != mao_ecra and mao_errada == "":
			mao_errada = "ronda %d: motor=%d ecrã=%d" % [engine.current_round, mao_motor, mao_ecra]

		# 3. a reserva de reforços idem
		var ref_motor: int = (engine.players["player"]["reinforcements"] as Array).size()
		var ref_ecra := 0
		for child in game.reinforcement_slots.get_children():
			if child is CardView:
				ref_ecra += 1
		if ref_motor != ref_ecra and reforcos_errados == "":
			reforcos_errados = "ronda %d: motor=%d ecrã=%d" % [engine.current_round, ref_motor, ref_ecra]

	print("  (%d jogadas, terminou em %s)" % [passos, engine.phase])
	ok(sem_vista.is_empty(), "toda a carta em campo tem vista no ecrã (%d sem vista%s)" % [
		sem_vista.size(), ("" if sem_vista.is_empty() else " — ex: " + sem_vista.keys()[0])])
	ok(sem_textura.is_empty(), "toda a vista tem arte carregada (%d invisíveis%s)" % [
		sem_textura.size(), ("" if sem_textura.is_empty() else " — ex: " + sem_textura.keys()[0])])
	ok(invisivel.is_empty(), "nenhuma carta transparente/encolhida (%d%s)" % [
		invisivel.size(), ("" if invisivel.is_empty() else " — ex: " + invisivel.values()[0])])
	ok(tamanho_zero.is_empty(), "nenhuma carta com tamanho zero (%d%s)" % [
		tamanho_zero.size(), ("" if tamanho_zero.is_empty() else " — ex: " + tamanho_zero.values()[0])])
	ok(fora_do_ecra.is_empty(), "nenhuma carta fora do ecrã (%d%s)" % [
		fora_do_ecra.size(), ("" if fora_do_ecra.is_empty() else " — ex: " + fora_do_ecra.values()[0])])
	ok(mao_errada == "", "mão no ecrã bate com o motor  %s" % mao_errada)
	ok(reforcos_errados == "", "reforços no ecrã batem com o motor  %s" % reforcos_errados)
	ok(engine.phase == "gameover", "a partida chegou ao fim (%s)" % engine.phase)

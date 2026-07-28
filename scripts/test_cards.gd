extends Node

# Testes das cartas no ecrã (Fase 5).
#
#   godot --headless --path . res://scenes/TestCards.tscn
#
# Verifica que a carta mostra a arte certa, que os stats batem com o motor
# (incluindo o bónus de Alinhamento), que as marcas de Pressão acendem, que
# os equipamentos aparecem e podem ser retirados, e que as casas de Apoio
# escondem os elementos sobrepostos.

var _passed := 0
var _failed := 0
var game: Control = null
var engine: Game = null
var board: BoardRenderer = null

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("\n=== CORREDOR — testes das cartas ===\n")
	var tree := get_tree()

	Session.set_match("reinos", "coro")
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	engine = game.engine
	board = game.get_node("VBoxContainer/BoardArea/Board")
	await tree.process_frame

	test_board_card_appears()
	await tree.process_frame
	test_stats_match_engine()
	test_alignment_bonus_shown()
	test_pressure_marks()
	test_shield_hidden_when_zero()
	test_equipment_badges()
	# Estes dois esperam por frames — sem await, devolviam uma corotina e as
	# verificações depois do await nunca corriam.
	await test_apoio_slot_hides_overlays()
	await test_slot_reuse_and_clear()

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

func place(owner_id: String, card_def: Dictionary, slot_type: String, lane: int) -> Dictionary:
	var card: Dictionary = engine._instantiate(card_def, owner_id)
	card["slotType"] = slot_type
	card["slotIndex"] = lane
	var arr: Array = engine.players[owner_id]["front"] if slot_type == "frente" else engine.players[owner_id]["back"]
	arr[lane] = card
	return card

func view_at(owner_id: String, slot_type: String, lane: int) -> CardView:
	var holder := board.card_holder(owner_id, slot_type, lane)
	if holder == null:
		return null
	for child in holder.get_children():
		if child is CardView:
			return child
	return null

func unit(nome: String, papel: String, atk: int, vida: int, escudo: int = 0, alinhamento: String = "NEUTRO", custo: int = 1) -> Dictionary:
	return {
		"id": "t-" + nome, "nome": nome, "papel": papel, "faccao_slug": "reinos",
		"tipo": [], "alinhamento": alinhamento, "ataque": atk, "vida": vida,
		"escudo": escudo, "custo": custo, "isApoio": false, "habilidade_texto": "",
		"imagem": "assets/cartas-3d/reinos-01-recruta-de-fronteira.png"
	}

# ---------------------------------------------------------------- testes

func test_board_card_appears() -> void:
	print("Carta aparece no tabuleiro")
	place("player", unit("Guardião", "GUERREIRO", 3, 5), "frente", 2)
	game._render_board()

	var vista := view_at("player", "frente", 2)
	check(vista != null, "CardView criada na casa 2")
	if vista == null:
		return
	check_eq(str(vista.card.get("nome", "")), "Guardião", "é a carta certa")
	check(vista._art.texture != null, "arte carregada")
	check(vista._art.texture.get_width() == 750, "arte é a de 750×1050")

func test_stats_match_engine() -> void:
	print("Stats batem com o motor")
	var vista := view_at("player", "frente", 2)
	if vista == null:
		check(false, "carta presente")
		return

	var esperado := engine.get_effective_ataque(vista.card) + engine.get_alignment_atk_bonus(vista.card)
	check_eq(vista._label_ataque.text, "%d" % esperado, "ataque mostrado = %d" % esperado)
	check_eq(vista._label_vida.text, "5", "vida mostrada = 5")

	# Levar dano tem de se reflectir depois de refrescar
	engine.deal_damage(vista.card, 2, null)
	vista.refresh()
	check_eq(vista._label_vida.text, "3", "depois de 2 de dano, vida = 3")

	# Vida negativa nunca aparece como negativa (o web usa Math.max(0, ...))
	vista.card["vidaAtual"] = -4
	vista.refresh()
	check_eq(vista._label_vida.text, "0", "vida negativa mostra 0")
	vista.card["vidaAtual"] = 5

func test_alignment_bonus_shown() -> void:
	print("Bónus de Alinhamento entra no ataque")
	# ORDEM dá +1 de Ataque a cartas de custo 3 ou mais
	var card := place("player", unit("Capitão", "GUERREIRO", 2, 4, 0, "ORDEM", 3), "frente", 3)
	game._render_board()

	var vista := view_at("player", "frente", 3)
	if vista == null:
		check(false, "carta presente")
		return

	check_eq(engine.get_alignment_atk_bonus(card), 1, "motor dá +1 por ORDEM custo 3")
	check_eq(vista._label_ataque.text, "3", "carta mostra 2+1 = 3")

func test_pressure_marks() -> void:
	print("Marcas de Pressão")
	var vista := view_at("player", "frente", 2)
	if vista == null:
		return

	check_eq(vista._pressure_row.get_child_count(), 2, "duas marcas desenhadas")

	vista.card["pressaoMarcas"] = 0
	vista.refresh()
	check(not _dot_lit(vista, 0), "sem Pressão: primeira marca apagada")

	vista.card["pressaoMarcas"] = 1
	vista.refresh()
	check(_dot_lit(vista, 0), "1 marca: primeira acesa")
	check(not _dot_lit(vista, 1), "1 marca: segunda apagada")

	vista.card["pressaoMarcas"] = 2
	vista.refresh()
	check(_dot_lit(vista, 0) and _dot_lit(vista, 1), "2 marcas: as duas acesas — pronta a Romper")

func _dot_lit(vista: CardView, idx: int) -> bool:
	var ponto: Panel = vista._pressure_row.get_child(idx)
	var sb: StyleBoxFlat = ponto.get_theme_stylebox("panel")
	return sb.bg_color.is_equal_approx(Palette.EMBER_400)

func test_shield_hidden_when_zero() -> void:
	print("Escudo só aparece se houver")
	var card := place("player", unit("Muro", "TANQUE", 1, 6, 2), "frente", 4)
	game._render_board()

	var vista := view_at("player", "frente", 4)
	if vista == null:
		check(false, "carta presente")
		return

	check(vista._label_escudo.visible, "com escudo 2, aparece")
	check_eq(vista._label_escudo.text, "2", "mostra 2")

	engine.deal_damage(card, 2, null)
	vista.refresh()
	check(not vista._label_escudo.visible, "escudo gasto, deixa de aparecer")
	check_eq(vista._label_vida.text, "6", "e a vida ficou intacta")

func test_equipment_badges() -> void:
	print("Equipamentos pendurados na carta")
	var card := place("player", unit("Espadachim", "GUERREIRO", 2, 4), "frente", 1)
	game._render_board()

	var vista := view_at("player", "frente", 1)
	if vista == null:
		check(false, "carta presente")
		return
	check_eq(vista._equip_layer.get_child_count(), 0, "começa sem equipamentos")

	var atk_antes := engine.get_effective_ataque(card)
	card["equipamentos"].append({
		"id": "TAC-01", "nome": "Espada de Ferro", "tipo_tatico": "Equipamento",
		"bonus_ataque": 2, "imagem": "tatico-001.png"
	})
	card["permBuffAtk"] = int(card["permBuffAtk"]) + 2
	vista.refresh()

	check_eq(vista._equip_layer.get_child_count(), 1, "mini-carta do equipamento aparece")
	check_eq(vista._label_ataque.text, "%d" % (atk_antes + 2), "ataque subiu 2")

	var badge: Control = vista._equip_layer.get_child(0)
	check_eq(str(badge.tooltip_text), "Espada de Ferro", "mini-carta identifica o equipamento")

	# Dois equipamentos ficam lado a lado, sem se taparem
	card["equipamentos"].append({
		"id": "TAC-02", "nome": "Elmo", "tipo_tatico": "Equipamento",
		"bonus_ataque": 0, "imagem": "tatico-002.png"
	})
	vista.refresh()
	# Em headless as casas ficam com tamanho zero e o _relayout desiste; damos
	# um tamanho concreto para as posições poderem ser verificadas. É preciso
	# soltar as âncoras primeiro, senão o Godot repõe o tamanho a seguir.
	vista.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	vista.size = Vector2(142, 138)
	vista._relayout()
	check_eq(vista._equip_layer.get_child_count(), 2, "dois equipamentos desenhados")
	var b0: Control = vista._equip_layer.get_child(0)
	var b1: Control = vista._equip_layer.get_child(1)
	check(b1.position.x < b0.position.x, "o segundo desloca-se para a esquerda")
	check(b0.position.x + b0.size.x <= vista.size.x + 1.0, "o primeiro não sai pela direita")
	check(b0.position.y + b0.size.y > vista.size.y, "transborda por baixo, como no web")

	# Retirar devolve o bónus
	engine.remove_equipamento(str(card["uid"]), 0)
	vista.refresh()
	check_eq((card["equipamentos"] as Array).size(), 1, "equipamento retirado")
	check_eq(vista._label_ataque.text, "%d" % atk_antes, "ataque voltou ao que era")

func test_apoio_slot_hides_overlays() -> void:
	print("Casas de Apoio escondem stats e Pressão")
	var vista := CardView.new()
	vista.show_overlays = false
	add_child(vista)
	vista.bind(engine, unit("Apoio", "CURADOR", 1, 1))
	await get_tree().process_frame

	check(not vista._stat_bar.visible, "barra de stats escondida")
	check(not vista._pressure_row.visible, "marcas de Pressão escondidas")
	check(vista._art.texture != null, "mas a arte continua visível")
	vista.queue_free()

func test_slot_reuse_and_clear() -> void:
	print("Casas seguem o motor")
	# Trocar a carta da casa tem de trocar a vista
	var antiga := view_at("player", "frente", 2)
	var uid_antigo := str(antiga.card.get("uid", "")) if antiga != null else ""

	engine.players["player"]["front"][2] = null
	place("player", unit("Substituto", "GUERREIRO", 1, 2), "frente", 2)
	game._render_board()
	await get_tree().process_frame

	var nova := view_at("player", "frente", 2)
	check(nova != null, "casa voltou a ter carta")
	if nova != null:
		check(str(nova.card.get("uid", "")) != uid_antigo, "é uma vista nova, não a antiga")
		check_eq(str(nova.card.get("nome", "")), "Substituto", "mostra a carta certa")

	# Esvaziar a casa tem de apagar a vista
	engine.players["player"]["front"][2] = null
	game._render_board()
	await get_tree().process_frame
	check(view_at("player", "frente", 2) == null, "casa vazia deixa de ter carta desenhada")

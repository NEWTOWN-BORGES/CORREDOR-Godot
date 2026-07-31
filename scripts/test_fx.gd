extends Node

# Testes das animações (Fase 9).
#
#   godot --headless --path . res://scenes/TestFx.tscn
#
# As animações correm a velocidade normal aqui — o que se verifica é que os
# elementos aparecem, ficam onde devem e se limpam sozinhos no fim. Também
# se confirma que a velocidade zero desliga tudo, que é o que permite às
# outras suites correrem depressa.

var _passed := 0
var _failed := 0
var game: Control = null
var board: BoardRenderer = null
var fx: FxLayer = null

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("\n=== CORREDOR — testes de animação ===\n")
	var tree := get_tree()

	Session.set_match("reinos", "coro")
	game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	game.ai = null
	board = game.get_node("BoardArea/Board")
	fx = game.get_node("FxLayer")
	await tree.process_frame

	await test_speed_propagates()
	await test_float_number_appears_and_clears()
	await test_float_colours()
	await test_attack_trail_points_at_target()
	await test_skull_pop()
	await test_travel_card()
	await test_zero_speed_draws_nothing()
	await test_slot_pulse_starts_and_stops()
	await test_tower_bar_animates()
	await test_low_tower_pulses()

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

func check_near(actual: float, expected: float, tol: float, label: String) -> void:
	if abs(actual - expected) <= tol:
		_passed += 1
		print("  ok   %s" % label)
	else:
		_failed += 1
		print("  FALHA %s  (esperado %.3f, obtido %.3f)" % [label, expected, actual])

func fx_children() -> int:
	return fx.get_child_count()

func clear_fx() -> void:
	for child in fx.get_children():
		fx.remove_child(child)
		child.queue_free()

# Espera tempo de relógio, para as animações correrem mesmo
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

# ---------------------------------------------------------------- testes

func test_speed_propagates() -> void:
	print("Velocidade chega aos nós que animam")
	game.set_animation_speed(1.0)
	check_near(fx.speed, 1.0, 0.001, "camada de efeitos a 1")
	check_near(board.pulse_speed, 1.0, 0.001, "tabuleiro a 1")

	game.set_animation_speed(0.0)
	check_near(fx.speed, 0.0, 0.001, "camada de efeitos a 0")
	check_near(board.pulse_speed, 0.0, 0.001, "tabuleiro a 0")

	game.set_animation_speed(1.0)

func test_float_number_appears_and_clears() -> void:
	print("Número de dano aparece e some")
	clear_fx()
	fx.float_number(Vector2(300, 200), "-7", "dano")
	await wait(0.1)

	check(fx_children() == 1, "número desenhado")
	var label: Label = fx.get_child(0)
	check(label.text == "-7", "mostra -7")

	var y_inicial := label.position.y
	await wait(0.5)
	check(label.position.y < y_inicial, "sobe enquanto desvanece")

	# 1.1s de animação — depois disso tem de se limpar sozinho
	await wait(1.0)
	check(fx_children() == 0, "limpou-se sozinho no fim")

func test_float_colours() -> void:
	print("Cor do número diz o que aconteceu")
	clear_fx()
	for par in [["dano", FxLayer.COR_DANO], ["cura", FxLayer.COR_CURA],
				["escudo", FxLayer.COR_ESCUDO], ["buff", FxLayer.COR_BUFF]]:
		clear_fx()
		fx.float_number(Vector2(100, 100), "1", str(par[0]))
		await wait(0.08)
		if fx_children() == 0:
			check(false, "número %s desenhado" % par[0])
			continue
		var label: Label = fx.get_child(0)
		var cor: Color = label.get_theme_color("font_color")
		check(cor.is_equal_approx(par[1]), "%s usa a cor certa" % par[0])
	clear_fx()

func test_attack_trail_points_at_target() -> void:
	print("Rasto do golpe aponta ao alvo")
	clear_fx()
	var de := Vector2(100, 100)
	var para := Vector2(300, 100)
	fx.attack_trail(de, para)
	await wait(0.05)

	check(fx_children() == 1, "rasto desenhado")
	var linha: ColorRect = fx.get_child(0)
	check_near(linha.size.x, 200.0, 1.0, "comprimento igual à distância")
	check_near(linha.rotation, 0.0, 0.01, "na horizontal, sem rodar")

	# Na diagonal tem de rodar
	clear_fx()
	fx.attack_trail(Vector2(0, 0), Vector2(100, 100))
	await wait(0.05)
	var diagonal: ColorRect = fx.get_child(0)
	check_near(diagonal.rotation, PI / 4.0, 0.01, "a 45 graus roda 45 graus")

	await wait(0.6)
	check(fx_children() == 0, "rasto limpou-se sozinho")

func test_skull_pop() -> void:
	print("Marca da morte")
	clear_fx()
	fx.skull_pop(Vector2(250, 250))
	await wait(0.15)
	check(fx_children() == 1, "marca desenhada")

	await wait(0.9)
	check(fx_children() == 0, "limpou-se sozinha")

func test_travel_card() -> void:
	print("Carta voa da mão para a casa")
	clear_fx()
	var tex := Cards.texture_for(Cards.unidades[0])
	check(tex != null, "arte disponível para a viagem")

	var de := Rect2(Vector2(50, 400), Vector2(80, 112))
	var para := Rect2(Vector2(400, 150), Vector2(140, 136))

	# As lambdas do GDScript capturam variáveis locais por valor, por isso um
	# bool simples nunca sairia de dentro da lambda. Um Array já é referência.
	var estado := [false]
	var viagem := func():
		await fx.travel_card(tex, de, para)
		estado[0] = true
	viagem.call()

	await wait(0.15)
	check(fx_children() == 1, "cópia da carta em voo")
	var clone: TextureRect = fx.get_child(0)
	check(clone.position != de.position - fx.global_position, "já saiu do sítio de partida")

	await wait(0.6)
	check(estado[0], "a viagem terminou")
	check(fx_children() == 0, "cópia removida no fim")

func test_zero_speed_draws_nothing() -> void:
	print("Velocidade zero não desenha nada")
	clear_fx()
	game.set_animation_speed(0.0)

	fx.float_number(Vector2(100, 100), "-5", "dano")
	fx.attack_trail(Vector2(0, 0), Vector2(100, 0))
	fx.skull_pop(Vector2(50, 50))
	await fx.travel_card(Cards.texture_for(Cards.unidades[0]), Rect2(0, 0, 10, 10), Rect2(50, 50, 10, 10))
	await wait(0.1)

	check(fx_children() == 0, "nenhum efeito criado — é isto que faz os testes serem rápidos")
	game.set_animation_speed(1.0)

func test_slot_pulse_starts_and_stops() -> void:
	print("Casas válidas pulsam e param")
	game.set_animation_speed(1.0)
	var slot := board.slot_control("player", "frente", 2)
	check(slot != null, "casa existe")
	if slot == null:
		return

	board.highlight_slot("player", "frente", 2, true)
	check(slot.has_meta("pulse_tween"), "ciclo de pulsar a correr")

	await wait(0.3)
	check(slot.modulate != Color(1, 1, 1, 1), "o brilho está mesmo a mudar")

	board.clear_highlights()
	check(not slot.has_meta("pulse_tween"), "ciclo parado ao limpar")
	check(slot.modulate.is_equal_approx(Color(1, 1, 1, 1)), "brilho reposto")

func test_tower_bar_animates() -> void:
	print("Barra da Torre desce animada")
	game.set_animation_speed(1.0)
	board.set_tower("ai", 30)
	await wait(0.7)

	var fill: ColorRect = board._tower_fills["ai"]
	check_near(fill.anchor_right, 1.0, 0.02, "começa cheia")

	board.set_tower("ai", 15)
	await wait(0.05)
	check(fill.anchor_right > 0.6, "logo a seguir ainda vai a meio caminho")

	await wait(0.8)
	check_near(fill.anchor_right, 0.5, 0.02, "acaba em metade")

func test_low_tower_pulses() -> void:
	print("Torre em perigo lateja")
	game.set_animation_speed(1.0)
	board.set_tower("ai", 30)
	await wait(0.7)
	var fill: ColorRect = board._tower_fills["ai"]
	check(fill.modulate.is_equal_approx(Color(1, 1, 1, 1)), "cheia não lateja")

	# 7/30 fica abaixo dos 25%
	board.set_tower("ai", 7)
	await wait(0.6)
	check(not fill.modulate.is_equal_approx(Color(1, 1, 1, 1)), "abaixo de 25% começa a latejar")

	board.set_tower("ai", 30)
	await wait(0.1)
	check(fill.modulate.is_equal_approx(Color(1, 1, 1, 1)), "ao recuperar, pára")

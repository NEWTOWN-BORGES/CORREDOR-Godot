extends Node

# Testes do menu (Fase 3).
#
#   godot --headless --path . res://scenes/TestMenu.tscn
#
# Corre como cena, não com --script: o MenuController depende dos autoloads
# Cards e Session, e esses só são instanciados quando o Godot arranca uma
# cena a sério.
#
# Instancia a cena real do menu e verifica que a lista de facções é
# construída a partir de cartas.json, que a escolha marca só uma opção e
# liberta o botão, e que o arranque guarda uma partida válida na Session.

var _passed := 0
var _failed := 0
var menu: Control = null

func _ready() -> void:
	# Adiado um frame: um dos testes chama _on_start_pressed(), que troca de
	# cena, e isso não pode acontecer enquanto a árvore ainda está a montar-se.
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("\n=== CORREDOR — testes do menu ===\n")

	# O último teste troca de cena, o que arranca este nó da árvore — a partir
	# daí get_tree() devolve nulo. Guardamos a referência antes.
	var tree := get_tree()

	menu = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)

	test_faction_list_built()
	test_selection_marks_one()
	test_start_requires_choice()
	test_start_picks_different_ai()

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

func faction_buttons() -> Array:
	var list: Node = menu.get_node("Center/MenuCard/Layout/FactionList")
	var out := []
	for child in list.get_children():
		if child is Button:
			out.append(child)
	return out

func start_button() -> Button:
	return menu.get_node("Center/MenuCard/Layout/StartButton") as Button

func _labels_of(btn: Button) -> Array:
	var out := []
	for child in btn.get_children():
		if child is VBoxContainer:
			for label in child.get_children():
				if label is Label:
					out.append((label as Label).text)
	return out

# ---------------------------------------------------------------- testes

func test_faction_list_built() -> void:
	print("Lista de facções")
	var botoes := faction_buttons()
	check_eq(botoes.size(), 5, "5 facções listadas")
	if botoes.is_empty():
		return

	var slugs := []
	for b in botoes:
		slugs.append(str(b.get_meta("slug")))
	for esperado in ["reinos", "coro", "verdemanto", "semceu", "despertos"]:
		check(slugs.has(esperado), "inclui %s" % esperado)

	# Cada opção mostra nome e alinhamentos, como no web
	var labels := _labels_of(botoes[0])
	check_eq(labels.size(), 2, "cada opção tem nome e alinhamentos")
	if labels.size() == 2:
		check(str(labels[0]) != "", "nome preenchido: %s" % labels[0])
		check(str(labels[1]) != "", "alinhamentos preenchidos: %s" % labels[1])

func test_selection_marks_one() -> void:
	print("Escolher facção")
	var botoes := faction_buttons()
	if botoes.size() < 4:
		check(false, "facções suficientes para testar")
		return

	check(start_button().disabled, "botão de arranque começa bloqueado")

	botoes[1].pressed.emit()
	var marcados := 0
	for b in botoes:
		if bool(b.get_meta("selected")):
			marcados += 1
	check_eq(marcados, 1, "só uma opção marcada")
	check(bool(botoes[1].get_meta("selected")), "a marcada é a que foi carregada")
	check(not start_button().disabled, "botão de arranque libertado")

	# Escolher outra tem de desmarcar a anterior
	botoes[3].pressed.emit()
	check(not bool(botoes[1].get_meta("selected")), "a anterior desmarcou")
	check(bool(botoes[3].get_meta("selected")), "a nova ficou marcada")

func test_start_requires_choice() -> void:
	print("Arranque sem escolha")
	Session.clear()
	var fresh: Control = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(fresh)

	var btn: Button = fresh.get_node("Center/MenuCard/Layout/StartButton")
	check(btn.disabled, "sem escolha, não deixa arrancar")
	btn.pressed.emit()
	check(not Session.has_match(), "nada foi guardado na Session")

	fresh.queue_free()

func test_start_picks_different_ai() -> void:
	print("Arranque guarda a partida")
	var botoes := faction_buttons()
	if botoes.is_empty():
		return

	var esperado := str(botoes[0].get_meta("slug"))

	# O sorteio do adversário testa-se à parte da troca de cena
	var vistos := {}
	var sempre_diferente := true
	for i in range(40):
		var ai: String = menu.pick_ai_faction(esperado)
		if ai == esperado:
			sempre_diferente = false
			break
		vistos[ai] = true

	check(sempre_diferente, "40 sorteios: adversário nunca é a facção do jogador")
	check(vistos.size() > 1, "adversário é mesmo sorteado (%d facções diferentes)" % vistos.size())

	# E o arranque a sério guarda tudo na Session
	Session.clear()
	botoes[0].pressed.emit()
	menu._on_start_pressed()
	check(Session.has_match(), "Session ficou preenchida")
	check_eq(Session.player_faction, esperado, "facção do jogador guardada")
	check(Session.ai_faction != Session.player_faction, "adversário diferente do jogador")

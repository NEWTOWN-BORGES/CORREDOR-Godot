extends Node
# Quick test for Game.gd motor

func test_basic_init():
	print("=== Test: Basic Init ===")
	var game = Game.new()

	# Create minimal decks
	var deck = [
		{
			"id": "test-1",
			"nome": "Teste Guerreiro",
			"papel": "GUERREIRO",
			"faccao_slug": "reinos",
			"tipo": [],
			"alinhamento": "ORDEM",
			"ataque": 2,
			"vida": 3,
			"escudo": 0,
			"custo": 1,
			"isApoio": false,
			"habilidade_texto": ""
		},
		{
			"id": "test-2",
			"nome": "Teste Tanque",
			"papel": "TANQUE",
			"faccao_slug": "reinos",
			"tipo": [],
			"alinhamento": "ORDEM",
			"ataque": 1,
			"vida": 5,
			"escudo": 2,
			"custo": 2,
			"isApoio": false,
			"habilidade_texto": ""
		},
		{
			"id": "test-ap1",
			"nome": "Teste Apoio",
			"faccao_slug": "reinos",
			"isApoio": true
		}
	]

	var log_lines = []
	game.init_game(deck, deck, func(msg): log_lines.append(msg))

	assert(game.towers["player"] == 30, "Player tower should start at 30")
	assert(game.towers["ai"] == 30, "AI tower should start at 30")
	assert(game.round == 1, "Should start at round 1")
	assert(game.phase == "placement", "Should start in placement phase")
	assert(game.activePlayer == "player", "Player should start")
	assert(game.players["player"]["hand"].size() > 0, "Player should have cards in hand")
	print("✓ Init test passed")

func test_play_unit():
	print("=== Test: Play Unit ===")
	var game = Game.new()

	var deck = [
		{
			"id": "test-1",
			"nome": "Guerreiro",
			"papel": "GUERREIRO",
			"faccao_slug": "reinos",
			"tipo": [],
			"alinhamento": "ORDEM",
			"ataque": 2,
			"vida": 3,
			"escudo": 0,
			"custo": 1,
			"isApoio": false,
			"habilidade_texto": ""
		}
	]

	game.init_game(deck, deck, func(msg): pass)

	# Play a unit
	var result = game.play_unit("player", 0, "frente", 0)
	assert(result["ok"] == true, "Should play unit successfully")
	assert(game.players["player"]["hand"].size() == 0, "Card should be removed from hand")
	assert(game.players["player"]["front"][0] != null, "Card should be on board")

	var card_on_board = game.players["player"]["front"][0]
	assert(card_on_board["nome"] == "Guerreiro", "Card name should match")
	assert(card_on_board["vidaAtual"] == 3, "Card should have full life")
	print("✓ Play unit test passed")

func test_damage():
	print("=== Test: Damage ===")
	var game = Game.new()

	var deck = [
		{
			"id": "test-1",
			"nome": "Card",
			"papel": "GUERREIRO",
			"faccao_slug": "reinos",
			"tipo": [],
			"alinhamento": "ORDEM",
			"ataque": 2,
			"vida": 5,
			"escudo": 2,
			"custo": 1,
			"isApoio": false,
			"habilidade_texto": ""
		}
	]

	game.init_game(deck, deck, func(msg): pass)
	game.play_unit("player", 0, "frente", 0)

	var card = game.players["player"]["front"][0]
	assert(card["escudoAtual"] == 2, "Shield should start at 2")

	# Deal 3 damage (2 absorbed by shield, 1 to HP)
	game.deal_damage(card, 3)
	assert(card["escudoAtual"] == 0, "Shield should be consumed")
	assert(card["vidaAtual"] == 4, "Card should take 1 damage to HP")
	print("✓ Damage test passed")

func _ready():
	print("\n=== CORREDOR Motor Tests ===\n")
	test_basic_init()
	test_play_unit()
	test_damage()
	print("\n✅ All tests passed!\n")

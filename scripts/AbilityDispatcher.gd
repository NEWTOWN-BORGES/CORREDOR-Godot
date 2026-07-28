extends Node
class_name AbilityDispatcher

# Despachador de habilidades — 86 unidades + 27 apoios
# Placeholder inicial; será expandido com todas as 86 abilities do web

var UNIT_ABILITIES: Dictionary = {}
var APOIO_ABILITIES: Dictionary = {}

func _init():
	_setup_unit_abilities()
	_setup_apoio_abilities()

func _setup_unit_abilities():
	# TODO: Add all 86 unit abilities
	# Placeholder abilities for testing
	UNIT_ABILITIES[""] = {"trigger": "none"}
	UNIT_ABILITIES["test"] = {"trigger": "static", "run": func(engine, card): pass}

func _setup_apoio_abilities():
	# TODO: Add all 27 support abilities
	APOIO_ABILITIES[""] = {"needsTarget": "none", "run": func(engine, owner_id): pass}

func get_unit_ability(ability_text: String) -> Dictionary:
	return UNIT_ABILITIES.get(ability_text, {})

func get_apoio_ability(apoio_id: String) -> Dictionary:
	return APOIO_ABILITIES.get(apoio_id, {})

func run_trigger(engine, card, trigger: String):
	var ability = get_unit_ability(card.get("habilidade_texto", ""))
	if ability.is_empty():
		return

	if ability.get("trigger") == trigger and ability.has("run"):
		ability["run"].call(engine, card)

func run_apoio(engine, apoio_id: String, owner_id: String, target = null, extra = null):
	var ability = get_apoio_ability(apoio_id)
	if ability.is_empty():
		return

	if ability.has("run"):
		if ability.get("needsTarget") == "ally" or ability.get("needsTarget") == "enemy":
			ability["run"].call(engine, owner_id, target, extra)
		elif ability.get("needsTarget") == "allyPair":
			ability["run"].call(engine, owner_id, target, extra)
		else:
			ability["run"].call(engine, owner_id)

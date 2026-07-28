extends Node
class_name DeckManager

# Constrói um baralho de 20 cartas para uma facção

static func build_faction_deck(cartas: Dictionary, faccao_slug: String) -> Array:
	var apoios_f = (cartas.get("apoios", []) as Array).filter(func(c): return c.get("faccao_slug") == faccao_slug)
	for c in apoios_f:
		c["isApoio"] = true

	var unidades_f = (cartas.get("unidades", []) as Array).filter(func(c): return c.get("faccao_slug") == faccao_slug)
	unidades_f.sort_custom(func(a, b): return a.get("custo", 0) < b.get("custo", 0))
	for c in unidades_f:
		c["isApoio"] = false

	var remaining = maxf(0, 20 - apoios_f.size())
	var deck = apoios_f + unidades_f.slice(0, remaining)

	# Add tactical cards from faction if they exist
	var taticos_f = (cartas.get("taticos", []) as Array).filter(func(c): return c.get("faccao_slug") == faccao_slug)
	deck.append_array(taticos_f)

	return deck

static func list_factions(cartas: Dictionary) -> Array:
	var factions = {}
	for c in cartas.get("unidades", []):
		var slug = c.get("faccao_slug", "")
		if slug and !slug.is_empty():
			factions[slug] = true
	return factions.keys()

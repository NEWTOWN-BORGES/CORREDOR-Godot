extends RefCounted
class_name DeckManager

# Constrói um baralho para uma facção (tradução de js/deck-builder.js):
# todos os Apoios dessa facção + unidades por ordem de custo crescente até
# completar 20, mais todas as cartas táticas da facção.
#
# As cartas são duplicadas — nunca devolvemos referências para as definições
# originais de cartas.json, senão os dois jogadores partilhariam o mesmo
# objecto e marcar `isApoio` num contaminaria o outro.

const DECK_SIZE := 20

static func build_faction_deck(cartas: Dictionary, faccao_slug: String) -> Array:
	var apoios_f := []
	for c in cartas.get("apoios", []):
		if str(c.get("faccao_slug", "")) == faccao_slug:
			var copy: Dictionary = c.duplicate(true)
			copy["isApoio"] = true
			apoios_f.append(copy)

	var unidades_f := []
	for c in cartas.get("unidades", []):
		if str(c.get("faccao_slug", "")) == faccao_slug:
			var copy: Dictionary = c.duplicate(true)
			copy["isApoio"] = false
			unidades_f.append(copy)
	unidades_f.sort_custom(func(a, b): return int(a.get("custo", 0)) < int(b.get("custo", 0)))

	var remaining: int = max(0, DECK_SIZE - apoios_f.size())
	var deck := apoios_f.duplicate()
	deck.append_array(unidades_f.slice(0, remaining))

	# Cartas táticas da facção (baralho separado, o motor separa-as por tipo_tatico)
	for c in cartas.get("taticos", []):
		if str(c.get("faccao_slug", "")) == faccao_slug:
			deck.append(c.duplicate(true))

	return deck

static func list_factions(cartas: Dictionary) -> Array:
	var seen := {}
	var out := []
	for c in cartas.get("unidades", []):
		var slug := str(c.get("faccao_slug", ""))
		if slug != "" and not seen.has(slug):
			seen[slug] = true
			out.append(slug)
	return out

# Nome legível da facção (a partir da primeira carta que a use).
static func faction_display_name(cartas: Dictionary, faccao_slug: String) -> String:
	for c in cartas.get("unidades", []):
		if str(c.get("faccao_slug", "")) == faccao_slug:
			return str(c.get("faccao", faccao_slug))
	return faccao_slug

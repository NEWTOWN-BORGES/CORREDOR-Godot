extends RefCounted
class_name DeckManager

# Monta os dois montes de uma facção:
#
#   militar — só unidades. Fica oculto e vai largando reforços.
#   mao     — Apoios. É de onde sai a única mão do jogador.
#
# As cartas são duplicadas — nunca devolvemos referências para as definições
# originais de cartas.json, senão os dois jogadores partilhariam o mesmo
# objecto e marcar `isApoio` num contaminaria o outro.

# As cartas Táticas foram removidas do jogo (design antigo, sem arte nova) —
# cartas.json já não traz nenhuma, mas o filtro fica pronto para se um dia
# voltarem a entrar.
const CATEGORIAS_APOIO := ["Equipamento", "Magia", "Consumível"]

static func build_faction_deck(cartas: Dictionary, faccao_slug: String) -> Dictionary:
	var militar := []
	for c in cartas.get("unidades", []):
		if str(c.get("faccao_slug", "")) == faccao_slug:
			var copia: Dictionary = c.duplicate(true)
			copia["isApoio"] = false
			militar.append(copia)

	# A mão é formada exclusivamente por cartas de Apoio reais (novas 45 cartas 3D)
	var mao := []
	for c in cartas.get("apoios", []):
		if str(c.get("faccao_slug", "")) == faccao_slug:
			var copia: Dictionary = c.duplicate(true)
			copia["isApoio"] = true
			mao.append(copia)

	# Caso a facção tenha menos de 15 Apoios próprios, complementa com Apoios gerais
	if mao.size() < 15:
		for c in cartas.get("apoios", []):
			if str(c.get("faccao_slug", "")) != faccao_slug:
				var copia: Dictionary = c.duplicate(true)
				copia["isApoio"] = true
				mao.append(copia)
				if mao.size() >= 15:
					break

	return {"militar": militar, "mao": mao}

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

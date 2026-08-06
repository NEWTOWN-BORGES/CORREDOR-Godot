extends RefCounted
class_name DeckManager

# Monta os dois montes de uma facção:
#
#   militar — só unidades. Fica oculto e vai largando reforços.
#   mao     — Apoios + Táticas. É de onde sai a única mão do jogador.
#
# Os Apoios ficam com as Táticas porque são o mesmo tipo de carta: jogas da
# mão, faz efeito, sai. Não ocupam casa nem combatem.
#
# As cartas são duplicadas — nunca devolvemos referências para as definições
# originais de cartas.json, senão os dois jogadores partilhariam o mesmo
# objecto e marcar `isApoio` num contaminaria o outro.

# A Bíblia fixa o Baralho de Apoio em três categorias. Construções, Climas e
# Bênçãos ficam fora do baralho — a arte fica no disco, só não entra em jogo.
const CATEGORIAS_APOIO := ["Equipamento", "Magia", "Consumível"]

static func build_faction_deck(cartas: Dictionary, faccao_slug: String) -> Dictionary:
	var militar := []
	for c in cartas.get("unidades", []):
		if str(c.get("faccao_slug", "")) == faccao_slug:
			var copia: Dictionary = c.duplicate(true)
			copia["isApoio"] = false
			militar.append(copia)
	# Sem custo no sistema, o Baralho Militar é só baralhado — o motor trata
	# disso no _make_player_state.

	var mao := []
	for c in cartas.get("apoios", []):
		if str(c.get("faccao_slug", "")) == faccao_slug:
			var copia: Dictionary = c.duplicate(true)
			copia["isApoio"] = true
			mao.append(copia)
	for c in cartas.get("taticos", []):
		if str(c.get("faccao_slug", "")) != faccao_slug:
			continue
		if not CATEGORIAS_APOIO.has(str(c.get("tipo_tatico", ""))):
			continue
		var copia: Dictionary = c.duplicate(true)
		copia["isApoio"] = false
		mao.append(copia)

	# Se mesmo assim a facção ficar com poucas cartas de mão, complementa com
	# Apoios de outras facções — melhor emprestar do que a mão nunca encher.
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

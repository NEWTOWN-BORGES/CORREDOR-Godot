extends RefCounted
class_name BoardGeometry

# Geometria do tabuleiro.
#
# Paisagem: medida directamente no TABULEIRO.pdf (calibração de Agosto 2026 —
# 26 casas com centro e cantos, imagem de referência 4963×3509). A retaguarda
# NÃO tem a mesma largura da frente: os dois baralhos nas pontas ficam mais
# afastados do centro do que uma simples continuação das 6 colunas da frente
# daria — por isso cada casa tem o seu próprio Rect2 medido, em vez de uma
# fórmula única de "faixa + passo uniforme". Os 4 lanes de combate (1-4) da
# retaguarda alinham com os 4 lanes centrais da frente; os lanes 0 e 5 da
# frente (combate) não têm equivalente na retaguarda (lá são baralho).
#
# Retrato: ainda não foi medido de novo — mantém a fórmula antiga (faixa
# única + 6 lanes uniformes) até haver dados equivalentes aos da paisagem.
#
# Rect2(x, y, largura, altura), tudo em fracções do tabuleiro.

const ART_LANDSCAPE := Vector2(4963, 3509)
const ART_PORTRAIT := Vector2(1024, 1536)

# Cada casa da paisagem, na ordem dos lanes (0=esquerda .. 5=direita), medida
# directamente no PDF. Retaguarda: lane 0 e 5 são os baralhos.
const SLOTS_LANDSCAPE := {
	"ai_retaguarda": [
		Rect2(0.1830, 0.1981, 0.0798, 0.0721),
		Rect2(0.3443, 0.1981, 0.0723, 0.0718),
		Rect2(0.4241, 0.1981, 0.0687, 0.0718),
		Rect2(0.5041, 0.1981, 0.0685, 0.0721),
		Rect2(0.5801, 0.1983, 0.0725, 0.0715),
		Rect2(0.7342, 0.1981, 0.0800, 0.0718),
	],
	"ai_frente": [
		Rect2(0.2466, 0.3029, 0.0824, 0.0835),
		Rect2(0.3327, 0.3029, 0.0780, 0.0835),
		Rect2(0.4187, 0.3029, 0.0737, 0.0835),
		Rect2(0.5045, 0.3032, 0.0739, 0.0829),
		Rect2(0.5861, 0.3032, 0.0782, 0.0832),
		Rect2(0.6677, 0.3032, 0.0826, 0.0832),
	],
	"player_frente": [
		Rect2(0.2257, 0.4243, 0.0901, 0.0975),
		Rect2(0.3190, 0.4246, 0.0850, 0.0975),
		Rect2(0.4118, 0.4243, 0.0802, 0.0972),
		Rect2(0.5051, 0.4243, 0.0796, 0.0980),
		Rect2(0.5930, 0.4246, 0.0852, 0.0975),
		Rect2(0.6812, 0.4243, 0.0901, 0.0975),
	],
	"player_retaguarda": [
		Rect2(0.0975, 0.5660, 0.1048, 0.1166),
		Rect2(0.3028, 0.5663, 0.0927, 0.1160),
		Rect2(0.4044, 0.5663, 0.0868, 0.1160),
		Rect2(0.5055, 0.5665, 0.0873, 0.1154),
		Rect2(0.6015, 0.5663, 0.0929, 0.1157),
		Rect2(0.7947, 0.5660, 0.1050, 0.1163),
	],
}

# Rect2 de cada faixa, em fracção da faixa (formulaico, só usado em retrato).
const RANKS_PORTRAIT := {
	"ai_retaguarda": Rect2(0.125, 0.100, 0.750, 0.155),
	"ai_frente": Rect2(0.125, 0.280, 0.750, 0.155),
	"player_frente": Rect2(0.125, 0.480, 0.750, 0.155),
	"player_retaguarda": Rect2(0.125, 0.660, 0.750, 0.155)
}

# CSS: `gap: 0.8%` numa flex de 6 items com `flex: 1 1 0`. Só serve o retrato.
const SLOT_GAP := 0.008
const LANES := 6

# --- Zonas do TABULEIRO.pdf ---------------------------------------------
# As pontas da retaguarda são os dois baralhos, espelhados entre os lados:
# o jogador tem o Apoio à esquerda e o Militar à direita, a IA ao contrário.
const LANE_ESQUERDA := 0
const LANE_DIREITA := 5

# Cemitério: paisagem medida directamente (casa "descarte" do PDF); retrato
# continua na fórmula antiga.
const GRAVEYARD_LANDSCAPE := {
	"ai": Rect2(0.4542, 0.1385, 0.0887, 0.0470),
	"player": Rect2(0.4352, 0.7033, 0.1265, 0.0958),
}
const CEMITERIO_PORTRAIT := {"ai": 0.170, "player": 0.730}
const CEMITERIO_TAMANHO := Vector2(0.088, 0.120)

# Torres: CSS `left: 50%; transform: translateX(-50%); width: 30%`
const TOWER_WIDTH := 0.30
const TOWER_MIN_WIDTH := 180.0
const TOWER_TOP_LANDSCAPE := {"ai": 0.018, "player": 0.938}
const TOWER_TOP_PORTRAIT := {"ai": 0.018, "player": 0.945}

# O tabuleiro passa a "arruinado" quando uma das torres desce a 25% ou menos.
const RUINED_THRESHOLD := 0.25

static func art_size(portrait: bool) -> Vector2:
	return ART_PORTRAIT if portrait else ART_LANDSCAPE

static func aspect_ratio(portrait: bool) -> float:
	var s := art_size(portrait)
	return s.x / s.y

# Rect2 absoluto (fracção do tabuleiro) de uma casa específica.
static func slot_rect(owner_id: String, slot_type: String, lane: int, portrait: bool) -> Rect2:
	if not portrait:
		var lista: Array = SLOTS_LANDSCAPE.get("%s_%s" % [owner_id, slot_type], [])
		if lane >= 0 and lane < lista.size():
			return lista[lane]
		return Rect2()

	var rank := rank_rect(owner_id, slot_type, true)
	var largura := slot_width()
	var esquerda := slot_left(lane)
	return Rect2(
		rank.position.x + esquerda * rank.size.x, rank.position.y,
		largura * rank.size.x, rank.size.y
	)

# Rect2 da faixa inteira (união das 6 casas). Só usado para posicionamento em
# retrato e para o teste de não-colisão do cemitério.
static func rank_rect(owner_id: String, slot_type: String, portrait: bool) -> Rect2:
	if portrait:
		return RANKS_PORTRAIT.get("%s_%s" % [owner_id, slot_type], Rect2())

	var lista: Array = SLOTS_LANDSCAPE.get("%s_%s" % [owner_id, slot_type], [])
	if lista.is_empty():
		return Rect2()
	var esquerda: float = lista[0].position.x
	var topo: float = lista[0].position.y
	var direita: float = lista[0].position.x + lista[0].size.x
	var fundo: float = lista[0].position.y + lista[0].size.y
	for r in lista:
		var rect: Rect2 = r
		esquerda = min(esquerda, rect.position.x)
		topo = min(topo, rect.position.y)
		direita = max(direita, rect.position.x + rect.size.x)
		fundo = max(fundo, rect.position.y + rect.size.y)
	return Rect2(esquerda, topo, direita - esquerda, fundo - topo)

static func tower_top(owner_id: String, portrait: bool) -> float:
	var tops := TOWER_TOP_PORTRAIT if portrait else TOWER_TOP_LANDSCAPE
	return float(tops.get(owner_id, 0.5))

# Largura de um slot, em fracção da faixa. Só usado em retrato — a paisagem
# tem cada casa medida individualmente em SLOTS_LANDSCAPE.
static func slot_width() -> float:
	return (1.0 - float(LANES - 1) * SLOT_GAP) / float(LANES)

# Posição horizontal do slot dentro da faixa, em fracção da faixa. Só retrato.
static func slot_left(lane: int) -> float:
	return float(lane) * (slot_width() + SLOT_GAP)

# As colunas 0 e 5 da retaguarda nunca recebem unidades — são os baralhos.
static func is_deck_slot(slot_type: String, lane: int) -> bool:
	return slot_type == "retaguarda" and (lane == LANE_ESQUERDA or lane == LANE_DIREITA)

# Mantido pelo nome antigo: a regra de jogo é a mesma, mudou o que lá está.
static func is_apoio_slot(slot_type: String, lane: int) -> bool:
	return is_deck_slot(slot_type, lane)

# Qual dos dois baralhos está nesta ponta. Espelhado, como no PDF: o jogador
# tem o Apoio à esquerda e o Militar à direita; a IA ao contrário.
static func deck_kind(owner_id: String, lane: int) -> String:
	if lane == LANE_ESQUERDA:
		return "apoio" if owner_id == "player" else "militar"
	if lane == LANE_DIREITA:
		return "militar" if owner_id == "player" else "apoio"
	return ""

# Onde fica o cemitério desse lado, em fracções do tabuleiro.
static func graveyard_rect(owner_id: String, portrait: bool) -> Rect2:
	if not portrait:
		return GRAVEYARD_LANDSCAPE.get(owner_id, Rect2())
	var y := float(CEMITERIO_PORTRAIT.get(owner_id, 0.5))
	var tamanho := CEMITERIO_TAMANHO
	return Rect2(0.5 - tamanho.x * 0.5, y - tamanho.y * 0.5, tamanho.x, tamanho.y)

extends RefCounted
class_name BoardGeometry

# Geometria do tabuleiro — copiada das medidas do style.css do web, que por
# sua vez foram medidas directamente na arte. A arte já tem as molduras dos
# slots desenhadas, por isso estes valores não podem ser inventados: cada
# faixa tem de cair exactamente onde a imagem a desenhou.
#
# Rect2(x, y, largura, altura), tudo em fracções do tabuleiro.

const ART_LANDSCAPE := Vector2(1402, 1122)
const ART_PORTRAIT := Vector2(1024, 1536)

# As linhas de retaguarda usam a MESMA largura e passo das 6 colunas da frente
# — as 4 colunas de combate (1-4) caem dentro da caixa de 4 cartas desenhada
# na arte, e as 2 pontas (0 e 5, só-Apoio) ficam nas margens de fora.
const RANKS_LANDSCAPE := {
	"ai_retaguarda": Rect2(0.180, 0.220, 0.634, 0.118),
	"ai_frente": Rect2(0.180, 0.370, 0.634, 0.123),
	"player_frente": Rect2(0.180, 0.540, 0.634, 0.127),
	"player_retaguarda": Rect2(0.180, 0.701, 0.634, 0.131)
}

const RANKS_PORTRAIT := {
	"ai_retaguarda": Rect2(0.250, 0.200, 0.500, 0.100),
	"ai_frente": Rect2(0.125, 0.356, 0.750, 0.108),
	"player_frente": Rect2(0.125, 0.549, 0.750, 0.112),
	"player_retaguarda": Rect2(0.250, 0.718, 0.500, 0.103)
}

# CSS: `gap: 0.8%` numa flex de 6 items com `flex: 1 1 0`.
const SLOT_GAP := 0.008
const LANES := 6

# Torres: CSS `left: 50%; transform: translateX(-50%); width: 30%`
const TOWER_WIDTH := 0.30
const TOWER_MIN_WIDTH := 180.0
const TOWER_TOP_LANDSCAPE := {"ai": 0.030, "player": 0.945}
const TOWER_TOP_PORTRAIT := {"ai": 0.028, "player": 0.958}

# O tabuleiro passa a "arruinado" quando uma das torres desce a 25% ou menos.
const RUINED_THRESHOLD := 0.25

static func art_size(portrait: bool) -> Vector2:
	return ART_PORTRAIT if portrait else ART_LANDSCAPE

static func aspect_ratio(portrait: bool) -> float:
	var s := art_size(portrait)
	return s.x / s.y

static func ranks(portrait: bool) -> Dictionary:
	return RANKS_PORTRAIT if portrait else RANKS_LANDSCAPE

static func rank_rect(owner_id: String, slot_type: String, portrait: bool) -> Rect2:
	return ranks(portrait).get("%s_%s" % [owner_id, slot_type], Rect2())

static func tower_top(owner_id: String, portrait: bool) -> float:
	var tops := TOWER_TOP_PORTRAIT if portrait else TOWER_TOP_LANDSCAPE
	return float(tops.get(owner_id, 0.5))

# Largura de um slot, em fracção da faixa: (1 - 5 intervalos) / 6.
static func slot_width() -> float:
	return (1.0 - float(LANES - 1) * SLOT_GAP) / float(LANES)

# Posição horizontal do slot dentro da faixa, em fracção da faixa.
static func slot_left(lane: int) -> float:
	return float(lane) * (slot_width() + SLOT_GAP)

# As colunas 0 e 5 da retaguarda nunca recebem unidades — são só de Apoio.
static func is_apoio_slot(slot_type: String, lane: int) -> bool:
	return slot_type == "retaguarda" and (lane == 0 or lane == LANES - 1)

extends RefCounted
class_name BoardSpec

# Geometria do tabuleiro inclinado — carrega resources/tabuleiro_spec.json
# (LORE_Tabuleiro_spec, medido por homografia sobre os desenhos AutoCAD:
# cards-Layout2.pdf a planta, TABULEIRO.pdf o tabuleiro inclinado).
#
# As 40 casas já vêm com os 4 cantos em coordenadas de ecrã normalizadas
# (`normal_ecra`, fracção 0..1 do tabuleiro) — não recalcular a homografia
# para desenhar, só para o sentido inverso (detecção de toque).

const SPEC_PATH := "res://resources/tabuleiro_spec.json"

var casas: Array = []
var _by_id: Dictionary = {}
var H: Array = []
var _h_inv: Array = []
var card_ratio: float = 1.36232

func load_spec() -> bool:
	if not FileAccess.file_exists(SPEC_PATH):
		return false
	var texto := FileAccess.get_file_as_string(SPEC_PATH)
	var parsed = JSON.parse_string(texto)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	casas = parsed.get("casas", [])
	_by_id.clear()
	for c in casas:
		_by_id[str(c["id"])] = c

	H = parsed.get("homografia_normalizada", {}).get("H", [])
	_h_inv = _invert_3x3(H)
	card_ratio = float(parsed.get("carta", {}).get("racio", 1.36232))
	return true

func by_id(id: String) -> Dictionary:
	return _by_id.get(id, {})

# Cantos já em fracção do tabuleiro (0..1), na ordem
# superior-esquerdo, superior-direito, inferior-direito, inferior-esquerdo.
func screen_quad(casa: Dictionary) -> Array:
	var out := []
	for p in casa.get("normal_ecra", []):
		out.append(Vector2(float(p[0]), float(p[1])))
	return out

func screen_center(casa: Dictionary) -> Vector2:
	var pts := screen_quad(casa)
	if pts.is_empty():
		return Vector2.ZERO
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / pts.size()

# ---------------------------------------------------------------- homografia

# planta [0,1]^2 -> ecrã [0,1]^2
func project(u: float, v: float) -> Vector2:
	return _apply(H, u, v)

# ecrã [0,1]^2 -> planta [0,1]^2 — usado para saber em que casa se tocou.
func unproject(sx: float, sy: float) -> Vector2:
	return _apply(_h_inv, sx, sy)

func _apply(m: Array, x: float, y: float) -> Vector2:
	if m.size() != 3:
		return Vector2(x, y)
	var w := float(m[2][0]) * x + float(m[2][1]) * y + float(m[2][2])
	if is_zero_approx(w):
		return Vector2.ZERO
	var rx := (float(m[0][0]) * x + float(m[0][1]) * y + float(m[0][2])) / w
	var ry := (float(m[1][0]) * x + float(m[1][1]) * y + float(m[1][2])) / w
	return Vector2(rx, ry)

func _invert_3x3(m: Array) -> Array:
	if m.size() != 3:
		return []
	var a: float = m[0][0]; var b: float = m[0][1]; var c: float = m[0][2]
	var d: float = m[1][0]; var e: float = m[1][1]; var f: float = m[1][2]
	var g: float = m[2][0]; var h: float = m[2][1]; var i: float = m[2][2]

	var det := a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
	if is_zero_approx(det):
		return []
	var inv_det := 1.0 / det

	return [
		[(e * i - f * h) * inv_det, (c * h - b * i) * inv_det, (b * f - c * e) * inv_det],
		[(f * g - d * i) * inv_det, (a * i - c * g) * inv_det, (c * d - a * f) * inv_det],
		[(d * h - e * g) * inv_det, (b * g - a * h) * inv_det, (a * e - b * d) * inv_det],
	]

# Devolve a casa cujo rectângulo de planta (normal_planta) contém o ponto,
# ou {} se o toque caiu fora de todas. `sx`/`sy` são fracção do tabuleiro.
func casa_no_toque(sx: float, sy: float) -> Dictionary:
	var p := unproject(sx, sy)
	for c in casas:
		var pts: Array = c.get("normal_planta", [])
		if pts.is_empty():
			continue
		var min_x: float = pts[0][0]
		var max_x: float = pts[0][0]
		var min_y: float = pts[0][1]
		var max_y: float = pts[0][1]
		for pt in pts:
			min_x = min(min_x, float(pt[0]))
			max_x = max(max_x, float(pt[0]))
			min_y = min(min_y, float(pt[1]))
			max_y = max(max_y, float(pt[1]))
		if p.x >= min_x and p.x <= max_x and p.y >= min_y and p.y <= max_y:
			return c
	return {}

# ---------------------------------------------------------------- consultas

func casas_do_grupo(grupo: String) -> Array:
	var out := []
	for c in casas:
		if str(c.get("grupo", "")) == grupo:
			out.append(c)
	return out

func casa_campo(lado: String, linha: int, coluna: int) -> Dictionary:
	for c in casas:
		if str(c.get("lado", "")) == lado and _linha(c) == linha \
				and int(c.get("coluna", -1)) == coluna:
			return c
	return {}

func casa_mao(lado: String, coluna: int) -> Dictionary:
	var grupo := "mao_%s" % lado
	for c in casas:
		if str(c.get("grupo", "")) == grupo and int(c.get("coluna", -1)) == coluna:
			return c
	return {}

func casa_baralho(tipo: String, lado: String) -> Dictionary:
	return by_id("baralho_%s_%s" % [tipo, lado])

# As casas de mão e de baralho têm "linha": null no JSON (chave presente,
# valor nulo) — .get("linha", -1) devolve esse null tal e qual, não o
# omissão. int(null) rebenta, por isso este passo intermédio.
func _linha(c: Dictionary) -> int:
	var v = c.get("linha")
	return -1 if v == null else int(v)

# Ordem de trás para a frente: mão do adversário -> L2 adversário ->
# L1 adversário -> L1 jogador -> L2 jogador -> mão do jogador.
func ordem_de_desenho() -> Array:
	var ordem := []
	ordem.append_array(casas_do_grupo("mao_adversario"))
	for c in casas:
		if str(c.get("lado","")) == "adversario" and _linha(c) == 2:
			ordem.append(c)
	ordem.append(casa_baralho("militar", "adversario"))
	ordem.append(casa_baralho("tatico", "adversario"))
	for c in casas:
		if str(c.get("lado","")) == "adversario" and _linha(c) == 1:
			ordem.append(c)
	for c in casas:
		if str(c.get("lado","")) == "jogador" and _linha(c) == 1:
			ordem.append(c)
	for c in casas:
		if str(c.get("lado","")) == "jogador" and _linha(c) == 2:
			ordem.append(c)
	ordem.append(casa_baralho("militar", "jogador"))
	ordem.append(casa_baralho("tatico", "jogador"))
	ordem.append_array(casas_do_grupo("mao_jogador"))
	return ordem

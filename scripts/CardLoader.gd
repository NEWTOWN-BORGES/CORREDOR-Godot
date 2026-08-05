extends Node
# Autoload: Cards
#
# Carrega cartas.json uma vez e serve as texturas a pedido.
#
# Porquê a pedido: a arte é 750×1050 sem compressão (compress/mode=0 nos
# .import), o que dá ~3 MB em RAM por carta. As 427 cartas de uma só vez
# seriam ~1,3 GB. Em jogo nunca há mais de ~30 cartas visíveis, por isso
# carregamos quando é preciso e despejamos as menos usadas.

const CARTAS_PATH := "res://resources/cartas.json"
const TATICOS_DIR := "res://assets/taticos-3d/"
const BOARD_DIR := "res://assets/board/"

# Quantas texturas de carta manter em memória. 64 × ~3 MB ≈ 200 MB no pior
# caso; baixa este valor se o telemóvel se queixar.
const TEXTURE_CACHE_LIMIT := 64

var unidades: Array = []
var apoios: Array = []
var taticos: Array = []

var _by_id: Dictionary = {}
var _texture_cache: Dictionary = {}   # res_path -> Texture2D
var _usage_order: Array = []          # res_path, do menos ao mais recente
var _loaded := false

# Diagnóstico
var stats_hits := 0
var stats_misses := 0
var stats_failures := 0

func _ready() -> void:
	load_all()

func load_all() -> bool:
	if _loaded:
		return true
	if not FileAccess.file_exists(CARTAS_PATH):
		push_error("CardLoader: %s não encontrado" % CARTAS_PATH)
		return false

	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CARTAS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CardLoader: cartas.json inválido")
		return false

	unidades = parsed.get("unidades", [])
	apoios = parsed.get("apoios", [])
	taticos = parsed.get("taticos", [])

	_by_id.clear()
	for c in unidades:
		_by_id[str(c.get("id", ""))] = c
	for c in apoios:
		_by_id[str(c.get("id", ""))] = c
	for c in taticos:
		_by_id[str(c.get("id", ""))] = c

	_loaded = true
	return true

# Dicionário no formato que o DeckManager e o Game esperam.
func as_dictionary() -> Dictionary:
	return {"unidades": unidades, "apoios": apoios, "taticos": taticos}

func by_id(card_id: String) -> Dictionary:
	return _by_id.get(card_id, {})

# ---------------------------------------------------------------------------
# Caminhos
# ---------------------------------------------------------------------------

# As unidades e os apoios trazem o caminho completo ("assets/cartas-3d/x.png");
# os táticos trazem só o nome do ficheiro ("tatico-001.png"), tal como no web,
# onde o ui-controller prefixava a pasta à mão.
func resolve_image_path(card_def: Dictionary) -> String:
	var imagem := str(card_def.get("imagem", ""))
	if imagem == "":
		return ""
	if imagem.begins_with("res://"):
		return imagem
	if imagem.contains("/"):
		return "res://" + imagem
	return TATICOS_DIR + imagem

func board_texture_path(ruined: bool = false, portrait: bool = false) -> String:
	var nome := "board-ruined" if ruined else "board-normal"
	if portrait:
		nome += "-portrait"
	return BOARD_DIR + nome + ".png"

# ---------------------------------------------------------------------------
# Texturas
# ---------------------------------------------------------------------------

func texture_for(card_def: Dictionary) -> Texture2D:
	return texture_at(resolve_image_path(card_def))

func texture_at(res_path: String) -> Texture2D:
	if res_path == "":
		return null

	if _texture_cache.has(res_path):
		stats_hits += 1
		_touch(res_path)
		return _texture_cache[res_path]

	# Tenta carregar directamente a textura de res_path
	var tex: Texture2D = null
	if ResourceLoader.exists(res_path):
		tex = load(res_path) as Texture2D

	if tex == null:
		# Fallback de carregamento directo caso ResourceLoader.exists dê falso negativo em .png
		if FileAccess.file_exists(res_path):
			tex = load(res_path) as Texture2D

	if tex == null:
		# Alguns dados de teste e as cartas táticas antigas referem arte que já
		# não existe no projecto. Nunca chame load() num caminho inexistente: o
		# Godot regista um erro e a UI fica sem imagem. Mostramos uma carta real
		# de reserva enquanto os dados antigos forem actualizados.
		var fallback_path: String = _fallback_texture_path(res_path)
		if fallback_path != "" and ResourceLoader.exists(fallback_path):
			tex = load(fallback_path) as Texture2D

	if tex == null:
		stats_failures += 1
		push_warning("CardLoader: falhou a carregar — %s" % res_path)
		return null

	stats_misses += 1
	_texture_cache[res_path] = tex
	_usage_order.append(res_path)
	_evict_if_needed()
	return tex

func _fallback_texture_path(res_path: String) -> String:
	var file_name: String = res_path.get_file().to_lower()
	if file_name.begins_with("reinos-01-"):
		return "res://assets/cartas-3d/REI-GR-01.png"
	if file_name.begins_with("tatico-"):
		return "res://assets/apoios-3d/APO-NE-01.png"
	return ""

func _touch(res_path: String) -> void:
	_usage_order.erase(res_path)
	_usage_order.append(res_path)

func _evict_if_needed() -> void:
	while _usage_order.size() > TEXTURE_CACHE_LIMIT:
		var oldest: String = _usage_order.pop_front()
		_texture_cache.erase(oldest)

func clear_texture_cache() -> void:
	_texture_cache.clear()
	_usage_order.clear()

func cache_size() -> int:
	return _texture_cache.size()

func stats_line() -> String:
	return "CardLoader: %d em cache, %d acertos, %d cargas, %d falhas" % [
		_texture_cache.size(), stats_hits, stats_misses, stats_failures
	]

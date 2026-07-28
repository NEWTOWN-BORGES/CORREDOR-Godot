extends Control
class_name BoardRenderer

# Tabuleiro — 4 faixas de 6 casas e as duas Torres, colocadas sobre a arte
# nas coordenadas medidas em BoardGeometry.
#
# Só trata de desenhar e de reportar cliques. Quem decide o que é jogada
# válida é o Game; este nó limita-se a perguntar.

signal slot_clicked(owner_id: String, slot_type: String, lane: int)

const TOWER_MAX := 30

var portrait: bool = false

# "player_frente_3" -> Control da casa
var _slots: Dictionary = {}
var _ranks: Dictionary = {}
var _tower_fills: Dictionary = {}
var _tower_labels: Dictionary = {}
var _tower_bars: Dictionary = {}

var _art: TextureRect = null
var _overlay: Control = null
var _ruined: bool = false

func _ready() -> void:
	_build()
	resized.connect(_relayout)
	_relayout()

# ---------------------------------------------------------------- construção

func _build() -> void:
	_art = TextureRect.new()
	_art.name = "BoardArt"
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_art)

	_overlay = Control.new()
	_overlay.name = "Slots"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	for owner_id in ["ai", "player"]:
		for slot_type in ["frente", "retaguarda"]:
			_build_rank(owner_id, slot_type)
		_build_tower(owner_id)

	_load_art()

func _build_rank(owner_id: String, slot_type: String) -> void:
	var rank := Control.new()
	rank.name = "Rank_%s_%s" % [owner_id, slot_type]
	rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(rank)
	_ranks["%s_%s" % [owner_id, slot_type]] = rank

	for lane in range(BoardGeometry.LANES):
		var slot := _build_slot(owner_id, slot_type, lane)
		rank.add_child(slot)
		_slots[_key(owner_id, slot_type, lane)] = slot

func _build_slot(owner_id: String, slot_type: String, lane: int) -> Control:
	var apoio := BoardGeometry.is_apoio_slot(slot_type, lane)

	var slot := Panel.new()
	slot.name = "Slot_%d" % lane
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.set_meta("owner_id", owner_id)
	slot.set_meta("slot_type", slot_type)
	slot.set_meta("lane", lane)
	slot.set_meta("apoio", apoio)
	slot.add_theme_stylebox_override("panel", _slot_style(false))

	# Ícone ténue por baixo, como no web (.slot-icon, opacidade 0.14)
	var icon := Label.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if apoio:
		icon.text = "APOIO"
		icon.add_theme_font_size_override("font_size", 9)
		icon.add_theme_color_override("font_color", Color(Palette.PARCHMENT, 0.20))
	else:
		icon.text = "FRENTE" if slot_type == "frente" else "RETAGUARDA"
		icon.add_theme_font_size_override("font_size", 9)
		icon.add_theme_color_override("font_color", Color(Palette.PARCHMENT, 0.14))
	slot.add_child(icon)

	# Onde a carta vai ser pendurada na Fase 5
	var holder := Control.new()
	holder.name = "CardHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(holder)

	slot.gui_input.connect(_on_slot_input.bind(owner_id, slot_type, lane))
	return slot

func _slot_style(highlighted: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	if highlighted:
		# .slot.valid-target
		sb.bg_color = Color(Palette.EMBER_GLOW, 0.18)
		sb.border_color = Palette.EMBER_500
		sb.set_border_width_all(2)
	else:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(0)
	return sb

func _build_tower(owner_id: String) -> void:
	var bar := PanelContainer.new()
	bar.name = "Tower_%s" % owner_id
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var fundo := StyleBoxFlat.new()
	fundo.bg_color = Color(0.039, 0.027, 0.020, 0.55)
	fundo.set_corner_radius_all(20)
	fundo.content_margin_left = 10
	fundo.content_margin_right = 10
	fundo.content_margin_top = 3
	fundo.content_margin_bottom = 3
	bar.add_theme_stylebox_override("panel", fundo)

	var linha := HBoxContainer.new()
	linha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	linha.add_theme_constant_override("separation", 6)
	bar.add_child(linha)

	var etiqueta := Label.new()
	etiqueta.text = "Torre"
	etiqueta.add_theme_font_size_override("font_size", 10)
	etiqueta.add_theme_color_override("font_color",
		Palette.EMBER_300 if owner_id == "player" else Color("e6a288"))
	linha.add_child(etiqueta)

	# Calha com o preenchimento por dentro
	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, 10)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Palette.STONE_950
	track_style.border_color = Palette.STONE_600
	track_style.set_border_width_all(1)
	track_style.set_corner_radius_all(7)
	track.add_theme_stylebox_override("panel", track_style)
	linha.add_child(track)

	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.offset_left = 1
	fill.offset_top = 1
	fill.offset_bottom = -1
	fill.color = Palette.EMBER_500
	track.add_child(fill)

	var hp := Label.new()
	hp.name = "HP"
	hp.text = "%d/%d" % [TOWER_MAX, TOWER_MAX]
	hp.custom_minimum_size = Vector2(46, 0)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp.add_theme_font_size_override("font_size", 11)
	hp.add_theme_color_override("font_color", Palette.PARCHMENT_DIM)
	linha.add_child(hp)

	_overlay.add_child(bar)
	_tower_bars[owner_id] = bar
	_tower_fills[owner_id] = fill
	_tower_labels[owner_id] = hp

func _load_art() -> void:
	var caminho := Cards.board_texture_path(_ruined, portrait)
	var tex := Cards.texture_at(caminho)
	if tex != null:
		_art.texture = tex

# ---------------------------------------------------------------- colocação

func _relayout() -> void:
	for owner_id in ["ai", "player"]:
		for slot_type in ["frente", "retaguarda"]:
			_place_rank(owner_id, slot_type)
		_place_tower(owner_id)

func _place_rank(owner_id: String, slot_type: String) -> void:
	var rank: Control = _ranks.get("%s_%s" % [owner_id, slot_type])
	if rank == null:
		return

	var r := BoardGeometry.rank_rect(owner_id, slot_type, portrait)
	rank.anchor_left = r.position.x
	rank.anchor_top = r.position.y
	rank.anchor_right = r.position.x + r.size.x
	rank.anchor_bottom = r.position.y + r.size.y
	rank.offset_left = 0.0
	rank.offset_top = 0.0
	rank.offset_right = 0.0
	rank.offset_bottom = 0.0

	var largura := BoardGeometry.slot_width()
	for lane in range(BoardGeometry.LANES):
		var slot: Control = _slots.get(_key(owner_id, slot_type, lane))
		if slot == null:
			continue
		var esquerda := BoardGeometry.slot_left(lane)
		slot.anchor_left = esquerda
		slot.anchor_right = esquerda + largura
		slot.anchor_top = 0.0
		slot.anchor_bottom = 1.0
		slot.offset_left = 0.0
		slot.offset_top = 0.0
		slot.offset_right = 0.0
		slot.offset_bottom = 0.0

func _place_tower(owner_id: String) -> void:
	var bar: Control = _tower_bars.get(owner_id)
	if bar == null:
		return

	var topo := BoardGeometry.tower_top(owner_id, portrait)
	var largura_frac := BoardGeometry.TOWER_WIDTH
	var largura_px: float = max(size.x * largura_frac, BoardGeometry.TOWER_MIN_WIDTH)
	var metade := largura_px * 0.5

	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = topo
	bar.anchor_bottom = topo
	bar.offset_left = -metade
	bar.offset_right = metade
	bar.offset_top = 0.0
	bar.offset_bottom = 22.0

# ---------------------------------------------------------------- API

func _key(owner_id: String, slot_type: String, lane: int) -> String:
	return "%s_%s_%d" % [owner_id, slot_type, lane]

func slot_control(owner_id: String, slot_type: String, lane: int) -> Control:
	return _slots.get(_key(owner_id, slot_type, lane))

func card_holder(owner_id: String, slot_type: String, lane: int) -> Control:
	var slot := slot_control(owner_id, slot_type, lane)
	return slot.get_node("CardHolder") if slot != null else null

func highlight_slot(owner_id: String, slot_type: String, lane: int, on: bool) -> void:
	var slot := slot_control(owner_id, slot_type, lane)
	if slot != null:
		slot.add_theme_stylebox_override("panel", _slot_style(on))

func clear_highlights() -> void:
	for slot in _slots.values():
		(slot as Control).add_theme_stylebox_override("panel", _slot_style(false))

# Espelha setTower() do web: fracção da barra, estado "low" abaixo de 25%.
func set_tower(owner_id: String, hp: int) -> void:
	var seguro: int = max(0, hp)
	var frac := float(seguro) / float(TOWER_MAX)

	var fill: ColorRect = _tower_fills.get(owner_id)
	if fill != null:
		fill.anchor_right = frac
		fill.color = Color("c23a1e") if frac <= BoardGeometry.RUINED_THRESHOLD else Palette.EMBER_500

	var label: Label = _tower_labels.get(owner_id)
	if label != null:
		label.text = "%d/%d" % [seguro, TOWER_MAX]

# O tabuleiro fica arruinado quando qualquer das torres desce a 25% ou menos.
func update_board_art(player_hp: int, ai_hp: int) -> void:
	var limite := float(TOWER_MAX) * BoardGeometry.RUINED_THRESHOLD
	var arruinado: bool = float(player_hp) <= limite or float(ai_hp) <= limite
	if arruinado != _ruined:
		_ruined = arruinado
		_load_art()

func is_ruined() -> bool:
	return _ruined

func set_portrait(value: bool) -> void:
	if value == portrait:
		return
	portrait = value
	_load_art()
	_relayout()

func _on_slot_input(event: InputEvent, owner_id: String, slot_type: String, lane: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			slot_clicked.emit(owner_id, slot_type, lane)

extends Control
class_name BoardRenderer

# Tabuleiro — 4 faixas de 6 casas e as duas Torres, colocadas sobre a arte
# nas coordenadas medidas em BoardGeometry.
#
# Só trata de desenhar e de reportar cliques. Quem decide o que é jogada
# válida é o Game; este nó limita-se a perguntar.

signal slot_clicked(owner_id: String, slot_type: String, lane: int)

const TOWER_MAX := 100

var portrait: bool = false

# "player_frente_3" -> Control da casa
var _slots: Dictionary = {}
var _ranks: Dictionary = {}
var _tower_fills: Dictionary = {}
var _tower_labels: Dictionary = {}
var _tower_bars: Dictionary = {}
var _graveyards: Dictionary = {}

var _art: TextureRect = null
var _overlay: Control = null
var _ruined: bool = false

# Posto a 0 pelos testes, para as barras irem directas ao valor final e as
# casas não ficarem com um pulsar infinito a correr.
var pulse_speed: float = 1.0
var _tower_tweens: Dictionary = {}
var _low_tweens: Dictionary = {}

func _ready() -> void:
	_build()
	resized.connect(_relayout)
	_relayout()

# ---------------------------------------------------------------- construção

func _build() -> void:
	# Fundo escuro limpo e elegante em substituição da imagem antiga de fundo
	var bg := Panel.new()
	bg.name = "BoardBackground"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Palette.STONE_950
	bg_style.border_color = Palette.STONE_700
	bg_style.set_border_width_all(2)
	bg_style.set_corner_radius_all(10)
	bg.add_theme_stylebox_override("panel", bg_style)
	add_child(bg)

	_art = TextureRect.new()
	_art.name = "BoardArt"
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.visible = false
	add_child(_art)

	_overlay = Control.new()
	_overlay.name = "Slots"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	# Linha divisória central entre os dois lados do tabuleiro
	var divider := ColorRect.new()
	divider.name = "CenterDivider"
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.color = Color(Palette.EMBER_500, 0.3)
	divider.anchor_left = 0.15
	divider.anchor_right = 0.85
	divider.anchor_top = 0.448
	divider.anchor_bottom = 0.452
	_overlay.add_child(divider)

	for owner_id in ["ai", "player"]:
		for slot_type in ["frente", "retaguarda"]:
			_build_rank(owner_id, slot_type)
		_build_tower(owner_id)
		_build_graveyard(owner_id)

	_load_art()

# Cemitério ao centro, entre a barra da Torre e a linha de retaguarda —
# o "baralho das cartas que morrem" do TABULEIRO.pdf.
func _build_graveyard(owner_id: String) -> void:
	var zona := Panel.new()
	zona.name = "Graveyard_%s" % owner_id
	zona.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var moldura := StyleBoxFlat.new()
	moldura.bg_color = Color(Palette.ZONA_CEMITERIO, 0.25)
	moldura.border_color = Color(Palette.ZONA_CEMITERIO, 0.85)
	moldura.set_border_width_all(2)
	moldura.set_corner_radius_all(6)
	zona.add_theme_stylebox_override("panel", moldura)

	var holder := Control.new()
	holder.name = "CardHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	zona.add_child(holder)

	var contador := Label.new()
	contador.name = "Count"
	contador.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contador.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contador.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	contador.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	contador.add_theme_font_size_override("font_size", 13)
	contador.add_theme_color_override("font_color", Palette.PARCHMENT)
	contador.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	contador.add_theme_constant_override("shadow_offset_y", 1)
	contador.text = "0"
	zona.add_child(contador)

	_overlay.add_child(zona)
	_graveyards[owner_id] = zona

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
	var baralho := BoardGeometry.is_deck_slot(slot_type, lane)
	var tipo_baralho := BoardGeometry.deck_kind(owner_id, lane) if baralho else ""

	var slot := Panel.new()
	slot.name = "Slot_%d" % lane
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.set_meta("owner_id", owner_id)
	slot.set_meta("slot_type", slot_type)
	slot.set_meta("lane", lane)
	slot.set_meta("apoio", baralho)
	slot.set_meta("deck_kind", tipo_baralho)
	slot.add_theme_stylebox_override("panel", _deck_style(tipo_baralho) if baralho else _slot_style(false))

	# Ícone ténue por baixo, como no web (.slot-icon, opacidade 0.14)
	var icon := Label.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 9)
	if baralho:
		icon.text = "MILITAR" if tipo_baralho == "militar" else "APOIO"
		icon.add_theme_color_override("font_color", _deck_color(tipo_baralho))
	else:
		icon.text = "FRENTE" if slot_type == "frente" else "RETAGUARDA"
		icon.add_theme_color_override("font_color", Color(Palette.PARCHMENT, 0.14))
	slot.add_child(icon)

	# Quantas cartas restam no baralho, por baixo do nome
	if baralho:
		var contador := Label.new()
		contador.name = "Count"
		contador.mouse_filter = Control.MOUSE_FILTER_IGNORE
		contador.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		contador.offset_top = 14
		contador.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		contador.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		contador.add_theme_font_size_override("font_size", 13)
		contador.add_theme_color_override("font_color", Palette.PARCHMENT)
		contador.text = "—"
		slot.add_child(contador)

	# Onde a carta vai ser pendurada na Fase 5
	var holder := Control.new()
	holder.name = "CardHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(holder)

	slot.gui_input.connect(_on_slot_input.bind(owner_id, slot_type, lane))
	return slot

func _deck_color(kind: String) -> Color:
	return Palette.ZONA_MILITAR if kind == "militar" else Palette.ZONA_APOIO

# Moldura das zonas de baralho, nas cores com que o tabuleiro foi traçado.
func _deck_style(kind: String) -> StyleBoxFlat:
	var cor := _deck_color(kind)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(cor, 0.22)
	sb.border_color = Color(cor, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	return sb

func _slot_style(highlighted: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	if highlighted:
		# Slot destacado para colocação de carta
		sb.bg_color = Color(Palette.EMBER_GLOW, 0.25)
		sb.border_color = Palette.EMBER_400
		sb.set_border_width_all(2)
		sb.shadow_color = Color(Palette.EMBER_500, 0.4)
		sb.shadow_size = 4
	else:
		# Slot normal em repouso - moldura escura elegante
		sb.bg_color = Color(0.04, 0.05, 0.07, 0.35)
		sb.border_color = Color(0.65, 0.55, 0.40, 0.30)
		sb.set_border_width_all(1)
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
	# A imagem antiga de fundo foi removida para eliminar a confusão.
	# O tabuleiro utiliza agora o fundo escuro moderno e profissional.
	if _art != null:
		_art.texture = null
		_art.visible = false

# ---------------------------------------------------------------- colocação

func _relayout() -> void:
	for owner_id in ["ai", "player"]:
		for slot_type in ["frente", "retaguarda"]:
			_place_rank(owner_id, slot_type)
		_place_tower(owner_id)
		_place_graveyard(owner_id)

func _place_graveyard(owner_id: String) -> void:
	var zona: Control = _graveyards.get(owner_id)
	if zona == null:
		return
	var r := BoardGeometry.graveyard_rect(owner_id, portrait)
	zona.anchor_left = r.position.x
	zona.anchor_top = r.position.y
	zona.anchor_right = r.position.x + r.size.x
	zona.anchor_bottom = r.position.y + r.size.y
	zona.offset_left = 0.0
	zona.offset_top = 0.0
	zona.offset_right = 0.0
	zona.offset_bottom = 0.0

func _place_rank(owner_id: String, slot_type: String) -> void:
	var rank: Control = _ranks.get("%s_%s" % [owner_id, slot_type])
	if rank == null:
		return

	# A faixa em si só agrupa; cada casa tem a sua posição absoluta (medida
	# individualmente em paisagem, ou calculada pela fórmula em retrato).
	rank.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for lane in range(BoardGeometry.LANES):
		var slot: Control = _slots.get(_key(owner_id, slot_type, lane))
		if slot == null:
			continue
		var r := BoardGeometry.slot_rect(owner_id, slot_type, lane, portrait)
		slot.anchor_left = r.position.x
		slot.anchor_top = r.position.y
		slot.anchor_right = r.position.x + r.size.x
		slot.anchor_bottom = r.position.y + r.size.y
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

# --- Zonas do TABULEIRO.pdf --------------------------------------------

# Quantas cartas restam num dos baralhos das pontas.
func set_deck_count(owner_id: String, kind: String, count: int) -> void:
	for lane in [BoardGeometry.LANE_ESQUERDA, BoardGeometry.LANE_DIREITA]:
		if BoardGeometry.deck_kind(owner_id, lane) != kind:
			continue
		var slot := slot_control(owner_id, "retaguarda", lane)
		if slot == null:
			continue
		var label := slot.get_node_or_null("Count")
		if label != null:
			(label as Label).text = str(count)

func graveyard_zone(owner_id: String) -> Control:
	return _graveyards.get(owner_id)

func graveyard_holder(owner_id: String) -> Control:
	var zona: Control = _graveyards.get(owner_id)
	return zona.get_node("CardHolder") if zona != null else null

func set_graveyard_count(owner_id: String, count: int) -> void:
	var zona: Control = _graveyards.get(owner_id)
	if zona == null:
		return
	var label := zona.get_node_or_null("Count")
	if label != null:
		(label as Label).text = str(count)

func highlight_slot(owner_id: String, slot_type: String, lane: int, on: bool) -> void:
	var slot := slot_control(owner_id, slot_type, lane)
	if slot == null:
		return
	slot.add_theme_stylebox_override("panel", _slot_style(on))
	_set_slot_pulse(slot, on)

func clear_highlights() -> void:
	for slot in _slots.values():
		var s := slot as Control
		s.add_theme_stylebox_override("panel", _slot_style(false))
		_set_slot_pulse(s, false)

# As casas válidas pulsam devagar (.slot.valid-target no web).
func _set_slot_pulse(slot: Control, on: bool) -> void:
	# has_meta antes de get_meta: no Godot 4.7 o get_meta com valor por
	# omissão continua a dar erro se a chave nunca foi criada.
	if slot.has_meta("pulse_tween"):
		var anterior = slot.get_meta("pulse_tween")
		if anterior != null and is_instance_valid(anterior):
			(anterior as Tween).kill()
		slot.remove_meta("pulse_tween")
	slot.modulate = Color(1, 1, 1, 1)

	if not on or pulse_speed <= 0.0:
		return

	var tw := create_tween().set_loops()
	var meio := 0.55 / pulse_speed
	tw.tween_property(slot, "modulate", Color(1.35, 1.2, 1.0, 1), meio) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(slot, "modulate", Color(1, 1, 1, 1), meio) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	slot.set_meta("pulse_tween", tw)

# Espelha setTower() do web: fracção da barra, estado "low" abaixo de 25%.
# A barra desce animada (no web era uma transition de 0.6s).
func set_tower(owner_id: String, hp: int) -> void:
	var seguro: int = max(0, hp)
	var frac := float(seguro) / float(TOWER_MAX)
	var baixa := frac <= BoardGeometry.RUINED_THRESHOLD

	var fill: ColorRect = _tower_fills.get(owner_id)
	if fill != null:
		var cor := Color("c23a1e") if baixa else Palette.EMBER_500

		var anterior = _tower_tweens.get(owner_id)
		if anterior != null and is_instance_valid(anterior):
			(anterior as Tween).kill()

		if pulse_speed <= 0.0:
			fill.anchor_right = frac
			fill.color = cor
		else:
			var tw := create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_property(fill, "anchor_right", frac, 0.6 / pulse_speed)
			tw.parallel().tween_property(fill, "color", cor, 0.3 / pulse_speed)
			_tower_tweens[owner_id] = tw

		_set_low_pulse(owner_id, fill, baixa)

	var label: Label = _tower_labels.get(owner_id)
	if label != null:
		label.text = "%d/%d" % [seguro, TOWER_MAX]

# Torre em perigo lateja (.tower-fill.low no web).
func _set_low_pulse(owner_id: String, fill: ColorRect, on: bool) -> void:
	var anterior = _low_tweens.get(owner_id)
	if anterior != null and is_instance_valid(anterior):
		(anterior as Tween).kill()
	_low_tweens.erase(owner_id)
	fill.modulate = Color(1, 1, 1, 1)

	if not on or pulse_speed <= 0.0:
		return

	var tw := create_tween().set_loops()
	tw.tween_property(fill, "modulate", Color(1.5, 1.5, 1.5, 1), 0.5 / pulse_speed)
	tw.tween_property(fill, "modulate", Color(1, 1, 1, 1), 0.5 / pulse_speed)
	_low_tweens[owner_id] = tw

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

extends Control
class_name CardView

# Uma carta no ecrã: a arte, as marcas de Pressão, a barra de stats e os
# equipamentos pendurados. Tradução de cardHtml() do js/ui-controller.js.
#
# A arte actual (750×1050) já traz moldura, nome, stats e texto desenhados.
# Quando chegarem molduras e arte novas, só estas constantes precisam de
# mudar — tudo o que se sobrepõe está em fracções do tamanho da carta, não
# em pixéis, por isso adapta-se a qualquer escala.

# --- Posição do que se sobrepõe, em fracções da carta ----------------------
const PRESSURE_MARGIN := 0.02      # canto superior esquerdo
const PRESSURE_DOT_SIZE := 0.075   # diâmetro de cada marca
const PRESSURE_DOT_GAP := 0.02
const PRESSURE_MAX_DOTS := 2       # o web mostra 2, mesmo com SOMBRA a pedir 3

const STAT_BAR_HEIGHT := 0.14      # faixa escura no fundo
const STAT_FONT_RATIO := 0.105     # tamanho da letra dos stats
const STAT_PADDING := 0.03

const EQUIP_WIDTH := 0.42          # mini-carta do equipamento
const EQUIP_HEIGHT := 0.42
const EQUIP_BOTTOM_OVERHANG := 0.06
const EQUIP_STEP := 0.36           # deslocamento por cada equipamento extra

# --- Cores dos stats (do style.css) ---------------------------------------
const COR_ATAQUE := Color("ff9a5c")
const COR_VIDA := Color("8fe0ff")
const COR_ESCUDO := Color("bcd8ff")
const COR_EQUIP_BORDA := Color(0.784, 0.627, 0.314, 0.8)

signal card_clicked(card: Dictionary)
signal equipment_clicked(card: Dictionary, equip_index: int)

var card: Dictionary = {}
var engine: Game = null

# Nas casas de Apoio o web esconde stats e Pressão (.slot-apoio .cstat-bar)
var show_overlays: bool = true

# --- Realce ao passar o rato, ao estilo Gwent ------------------------------
# Na mão as cartas sobrepõem-se; passar o rato levanta a carta e amplia-a
# para se poder ler sem ter de clicar.
var hover_enabled: bool = false
const HOVER_LIFT := 46.0
const HOVER_SCALE := 1.42
const HOVER_TIME := 0.14

var _hover_tween: Tween = null
var _base_position := Vector2.ZERO
var _base_z := 0
var _hovering := false

var _art: TextureRect = null
var _pressure_row: HBoxContainer = null
var _stat_bar: Control = null
var _label_ataque: Label = null
var _label_escudo: Label = null
var _label_vida: Label = null
var _equip_layer: Control = null

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(_relayout)
	if hover_enabled:
		mouse_entered.connect(_on_hover_start)
		mouse_exited.connect(_on_hover_end)
	if not card.is_empty():
		refresh()

# --- Realce ao passar o rato ---------------------------------------------

func _on_hover_start() -> void:
	if _hovering:
		return
	_hovering = true
	# Guarda o sítio de origem à primeira vez: o contentor já a colocou
	_base_position = position
	_base_z = z_index

	# Por cima das vizinhas, senão a ampliação fica cortada pelas de cima
	z_index = 100
	pivot_offset = Vector2(size.x * 0.5, size.y)   # cresce a partir da base

	_animate_hover(_base_position + Vector2(0, -HOVER_LIFT), Vector2(HOVER_SCALE, HOVER_SCALE))

func _on_hover_end() -> void:
	if not _hovering:
		return
	_hovering = false
	_animate_hover(_base_position, Vector2.ONE)
	z_index = _base_z

func _animate_hover(destino: Vector2, escala: Vector2) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_hover_tween.tween_property(self, "position", destino, HOVER_TIME)
	_hover_tween.parallel().tween_property(self, "scale", escala, HOVER_TIME)

# A carta entra a crescer e a aparecer (.card-el.entering do web).
func play_enter_animation(speed: float = 1.0) -> void:
	if speed <= 0.0:
		return
	pivot_offset = size * 0.5
	scale = Vector2(0.4, 0.4)
	modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2.ONE, 0.35 / speed)
	tw.parallel().tween_property(self, "modulate", Color(1, 1, 1, 1), 0.35 / speed)

# ---------------------------------------------------------------- construção

func _build() -> void:
	_art = TextureRect.new()
	_art.name = "Art"
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# object-fit: cover; object-position: top
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_art)

	_stat_bar = Control.new()
	_stat_bar.name = "StatBar"
	_stat_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stat_bar)

	var fundo := ColorRect.new()
	fundo.name = "StatBg"
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fundo.color = Color(0, 0, 0, 0.85)
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stat_bar.add_child(fundo)

	_label_ataque = _make_stat_label(COR_ATAQUE, HORIZONTAL_ALIGNMENT_LEFT)
	_label_escudo = _make_stat_label(COR_ESCUDO, HORIZONTAL_ALIGNMENT_CENTER)
	_label_vida = _make_stat_label(COR_VIDA, HORIZONTAL_ALIGNMENT_RIGHT)
	_stat_bar.add_child(_label_ataque)
	_stat_bar.add_child(_label_escudo)
	_stat_bar.add_child(_label_vida)

	_pressure_row = HBoxContainer.new()
	_pressure_row.name = "Pressure"
	_pressure_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pressure_row)

	# As marcas são criadas uma vez; refrescar só lhes troca o estilo. Recriá-las
	# a cada refresh acumulava-as, porque queue_free() só liberta no fim do frame.
	for i in range(PRESSURE_MAX_DOTS):
		var ponto := Panel.new()
		ponto.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ponto.add_theme_stylebox_override("panel", _pressure_style(false))
		_pressure_row.add_child(ponto)

	_equip_layer = Control.new()
	_equip_layer.name = "Equipment"
	_equip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equip_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_equip_layer)

func _make_stat_label(cor: Color, alinhamento: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = alinhamento
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", cor)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

# ---------------------------------------------------------------- ligação

func bind(a_engine: Game, a_card: Dictionary) -> void:
	engine = a_engine
	card = a_card
	if is_inside_tree():
		refresh()

func refresh() -> void:
	if card.is_empty():
		return

	var tex := Cards.texture_for(card)
	if tex != null and _art != null:
		_art.texture = tex

	_refresh_stats()
	_refresh_pressure()
	_refresh_equipment()
	_relayout()

func _refresh_stats() -> void:
	var visivel := show_overlays
	_stat_bar.visible = visivel
	if not visivel:
		return

	# O web mostra o ataque já com o bónus de Alinhamento incluído
	var ataque := 0
	if engine != null:
		ataque = engine.get_effective_ataque(card) + engine.get_alignment_atk_bonus(card)
	else:
		ataque = int(card.get("baseAtaque", 0))

	var escudo := int(card.get("escudoAtual", 0))
	var vida: int = max(0, int(card.get("vidaAtual", 0)))

	_label_ataque.text = "%d" % ataque
	_label_vida.text = "%d" % vida
	_label_escudo.text = "%d" % escudo
	_label_escudo.visible = escudo > 0   # o web só mostra o escudo se houver

func _refresh_pressure() -> void:
	var visivel := show_overlays
	_pressure_row.visible = visivel
	if not visivel:
		return

	var marcas := int(card.get("pressaoMarcas", 0))
	for i in range(_pressure_row.get_child_count()):
		var ponto: Panel = _pressure_row.get_child(i)
		ponto.add_theme_stylebox_override("panel", _pressure_style(i < marcas))

func _pressure_style(aceso: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(64)   # círculo
	sb.set_border_width_all(1)
	if aceso:
		sb.bg_color = Palette.EMBER_400
		sb.border_color = Palette.EMBER_300
	else:
		sb.bg_color = Color(0, 0, 0, 0.5)
		sb.border_color = Color(1, 1, 1, 0.3)
	return sb

func _refresh_equipment() -> void:
	# remove_child antes de queue_free: sem isso os filhos antigos ainda contam
	# até ao fim do frame e os equipamentos duplicavam a cada refresh.
	for child in _equip_layer.get_children():
		_equip_layer.remove_child(child)
		child.queue_free()

	var equipamentos: Array = card.get("equipamentos", [])
	for idx in range(equipamentos.size()):
		_equip_layer.add_child(_make_equipment_badge(equipamentos[idx], idx))

func _make_equipment_badge(equip: Dictionary, idx: int) -> Control:
	var badge := Panel.new()
	badge.name = "Equip_%d" % idx
	badge.mouse_filter = Control.MOUSE_FILTER_STOP
	badge.set_meta("equip_index", idx)
	badge.tooltip_text = str(equip.get("nome", ""))

	var moldura := StyleBoxFlat.new()
	moldura.bg_color = Color("0a0908")
	moldura.border_color = COR_EQUIP_BORDA
	moldura.set_border_width_all(2)
	moldura.set_corner_radius_all(4)
	badge.add_theme_stylebox_override("panel", moldura)

	var arte := TextureRect.new()
	arte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arte.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arte.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	arte.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arte.offset_left = 2
	arte.offset_top = 2
	arte.offset_right = -2
	arte.offset_bottom = -2
	var tex := Cards.texture_for(equip)
	if tex != null:
		arte.texture = tex
	badge.add_child(arte)

	badge.gui_input.connect(_on_equipment_input.bind(idx))
	return badge

# ---------------------------------------------------------------- colocação

func _relayout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	# Barra de stats no fundo
	var altura_barra := h * STAT_BAR_HEIGHT
	_stat_bar.position = Vector2(0, h - altura_barra)
	_stat_bar.size = Vector2(w, altura_barra)

	var fonte: int = max(7, int(h * STAT_FONT_RATIO))
	var margem := w * STAT_PADDING
	var largura_terco := (w - margem * 2.0) / 3.0
	var stats := [_label_ataque, _label_escudo, _label_vida]
	for i in range(stats.size()):
		var label: Label = stats[i]
		label.add_theme_font_size_override("font_size", fonte)
		label.position = Vector2(margem + largura_terco * float(i), 0)
		label.size = Vector2(largura_terco, altura_barra)

	# Marcas de Pressão no canto superior esquerdo
	var ponto := h * PRESSURE_DOT_SIZE
	var espaco := h * PRESSURE_DOT_GAP
	_pressure_row.position = Vector2(w * PRESSURE_MARGIN, h * PRESSURE_MARGIN)
	_pressure_row.add_theme_constant_override("separation", int(espaco))
	for child in _pressure_row.get_children():
		(child as Control).custom_minimum_size = Vector2(ponto, ponto)

	# Equipamentos, encostados ao canto inferior direito e a transbordar
	var eq_w := w * EQUIP_WIDTH
	var eq_h := h * EQUIP_HEIGHT
	var passo := w * EQUIP_STEP
	var transborda := h * EQUIP_BOTTOM_OVERHANG
	var badges := _equip_layer.get_children()
	for i in range(badges.size()):
		var badge: Control = badges[i]
		badge.size = Vector2(eq_w, eq_h)
		badge.position = Vector2(
			w - eq_w - passo * float(i),
			h - eq_h + transborda
		)

# ---------------------------------------------------------------- entrada

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			card_clicked.emit(card)

func _on_equipment_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# Não deixa o clique passar para a carta por baixo
			accept_event()
			equipment_clicked.emit(card, idx)

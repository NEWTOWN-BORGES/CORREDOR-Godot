extends Control

# Menu inicial — tradução de buildFactionMenu() e startGame() do
# js/ui-controller.js do web.
#
# Cada facção mostra o nome e os alinhamentos que tem, tal como no web
# (`aligns.join(' / ')`). O adversário é sorteado entre as outras facções.

const GAME_SCENE := "res://scenes/Game.tscn"

var _chosen_slug: String = ""
var _options: Array[Button] = []

@onready var faction_list: VBoxContainer = $Center/MenuCard/Layout/FactionList
@onready var start_button: Button = $Center/MenuCard/Layout/StartButton
@onready var title_label: Label = $Center/MenuCard/Layout/Title
@onready var subtitle_label: Label = $Center/MenuCard/Layout/Subtitle
@onready var card_panel: PanelContainer = $Center/MenuCard
@onready var background: ColorRect = $Background

func _ready() -> void:
	_style_static_bits()
	if not Cards.load_all():
		subtitle_label.text = "Erro: não foi possível carregar as cartas."
		return
	_build_faction_menu()

	start_button.disabled = true
	start_button.pressed.connect(_on_start_pressed)

	get_viewport().size_changed.connect(_update_background_size)
	_update_background_size()

func _style_static_bits() -> void:
	card_panel.add_theme_stylebox_override("panel", UITheme.menu_card())

	# .brand-title — 2.6rem, espaçado, cor ember-300
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.add_theme_color_override("font_color", Palette.EMBER_300)

	# .brand-sub
	subtitle_label.add_theme_font_size_override("font_size", 15)
	subtitle_label.add_theme_color_override("font_color", Palette.PARCHMENT_DIM)

	UITheme.apply_ember(start_button)
	start_button.add_theme_font_size_override("font_size", 16)

# O shader precisa de saber o tamanho do ecrã para as elipses não esticarem.
func _update_background_size() -> void:
	var mat := background.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("viewport_size", Vector2(get_viewport_rect().size))

# ---------------------------------------------------------------- facções

func _build_faction_menu() -> void:
	for child in faction_list.get_children():
		child.queue_free()
	_options.clear()

	var cartas := Cards.as_dictionary()
	for slug in DeckManager.list_factions(cartas):
		faction_list.add_child(_make_faction_option(cartas, str(slug)))

func _make_faction_option(cartas: Dictionary, slug: String) -> Button:
	var nome := DeckManager.faction_display_name(cartas, slug)
	var alinhamentos := _alignments_of(cartas, slug)

	# Um Button com dois Labels dentro, para ter estados de hover/foco de graça.
	var btn := Button.new()
	btn.name = "Faction_" + slug
	btn.custom_minimum_size = Vector2(0, 62)
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta("slug", slug)
	btn.set_meta("selected", false)

	var texto := VBoxContainer.new()
	texto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texto.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texto.offset_left = 14
	texto.offset_right = -14
	texto.alignment = BoxContainer.ALIGNMENT_CENTER
	texto.add_theme_constant_override("separation", 2)

	var nome_label := Label.new()
	nome_label.text = nome
	nome_label.add_theme_font_size_override("font_size", 17)
	nome_label.add_theme_color_override("font_color", Palette.PARCHMENT)
	texto.add_child(nome_label)

	var align_label := Label.new()
	align_label.text = " / ".join(alinhamentos)
	align_label.add_theme_font_size_override("font_size", 12)
	align_label.add_theme_color_override("font_color", Palette.PARCHMENT_DIM)
	texto.add_child(align_label)

	btn.add_child(texto)

	_paint_option(btn, false, false)
	btn.pressed.connect(_on_faction_pressed.bind(btn))
	btn.mouse_entered.connect(_on_faction_hover.bind(btn, true))
	btn.mouse_exited.connect(_on_faction_hover.bind(btn, false))

	_options.append(btn)
	return btn

func _alignments_of(cartas: Dictionary, slug: String) -> Array:
	var seen := {}
	var out := []
	for c in cartas.get("unidades", []):
		if str(c.get("faccao_slug", "")) != slug:
			continue
		var a := str(c.get("alinhamento", ""))
		if a != "" and not seen.has(a):
			seen[a] = true
			out.append(a)
	return out

func _paint_option(btn: Button, selected: bool, hovered: bool) -> void:
	var sb := UITheme.faction_option(selected, hovered)
	for estado in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(estado, sb)

func _on_faction_hover(btn: Button, entered: bool) -> void:
	if bool(btn.get_meta("selected")):
		return
	_paint_option(btn, false, entered)

func _on_faction_pressed(btn: Button) -> void:
	Sfx.clique()
	_chosen_slug = str(btn.get_meta("slug"))
	for other in _options:
		var is_chosen: bool = other == btn
		other.set_meta("selected", is_chosen)
		_paint_option(other, is_chosen, false)
	start_button.disabled = false

# ---------------------------------------------------------------- arranque

# O adversário é sorteado entre as outras facções, como no web.
# Separado do handler para poder ser testado sem trocar de cena.
func pick_ai_faction(player_slug: String) -> String:
	var outras := []
	for slug in DeckManager.list_factions(Cards.as_dictionary()):
		if str(slug) != player_slug:
			outras.append(str(slug))
	if outras.is_empty():
		return player_slug
	return str(outras[randi() % outras.size()])

func _on_start_pressed() -> void:
	if _chosen_slug == "":
		return
	Sfx.clique()
	Session.set_match(_chosen_slug, pick_ai_faction(_chosen_slug))
	get_tree().change_scene_to_file(GAME_SCENE)

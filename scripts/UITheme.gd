extends RefCounted
class_name UITheme

# Estilos partilhados, traduzidos das classes do style.css do web.
# Usados pelo menu (Fase 3) e reaproveitados pelo tabuleiro e mão adiante.

# --------------------------------------------------------------- .menu-card
# background: linear-gradient(180deg, stone-800, stone-900)
# border: 2px solid stone-600; border-radius: 14px
# box-shadow: 0 0 0 6px stone-950, 0 20px 60px shadow-deep
static func menu_card() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.STONE_800
	sb.border_color = Palette.STONE_600
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(22)
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	sb.shadow_color = Palette.SHADOW_DEEP
	sb.shadow_size = 20
	sb.shadow_offset = Vector2(0, 10)
	return sb

# ----------------------------------------------------------- .faction-option
# border: 1px solid stone-600; border-radius: 10px
static func faction_option(selected: bool, hovered: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.03) if not selected else Color(1, 1, 1, 0.05)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12

	if selected:
		# .selected — contorno cor de brasa e halo
		sb.border_color = Palette.EMBER_400
		sb.set_border_width_all(2)
		sb.shadow_color = Color(Palette.EMBER_GLOW, 0.35)
		sb.shadow_size = 12
	elif hovered:
		# :hover — só muda a cor do contorno
		sb.border_color = Palette.EMBER_500
	else:
		sb.border_color = Palette.STONE_600
	return sb

# ---------------------------------------------------------------- .btn-ember
# background: linear-gradient(180deg, ember-300, ember-500 60%, ember-600)
# O StyleBoxFlat não faz gradientes, por isso usamos o tom do meio (ember-500)
# e sugerimos o relevo com a borda inferior mais escura.
static func ember_button(state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.border_color = Palette.EMBER_EDGE
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3

	match state:
		"hover":
			sb.bg_color = Palette.EMBER_400
			sb.shadow_color = Color(Palette.EMBER_500, 0.45)
			sb.shadow_size = 10
		"pressed":
			# :active — afunda, sombra mais curta
			sb.bg_color = Palette.EMBER_600
			sb.border_width_bottom = 1
			sb.content_margin_top = 14
			sb.content_margin_bottom = 10
		"disabled":
			# :disabled — filter: grayscale(.6) brightness(.6)
			sb.bg_color = Palette.EMBER_500.lerp(Color(0.25, 0.22, 0.20), 0.6)
			sb.border_color = Palette.STONE_600
		_:
			sb.bg_color = Palette.EMBER_500
			sb.shadow_color = Color(Palette.EMBER_500, 0.35)
			sb.shadow_size = 8
			sb.shadow_offset = Vector2(0, 3)
	return sb

# --------------------------------------------------- .btn-ember.btn-ghost
static func ghost_button(state: String) -> StyleBoxFlat:
	var sb := ember_button(state)
	sb.border_color = Palette.STONE_500
	match state:
		"hover":
			sb.bg_color = Palette.STONE_500
		"pressed":
			sb.bg_color = Palette.STONE_700
		"disabled":
			sb.bg_color = Palette.STONE_700.lerp(Color(0.2, 0.18, 0.16), 0.6)
		_:
			sb.bg_color = Palette.STONE_600
	sb.shadow_size = 0
	return sb

# Aplica o visual de brasa a um Button já existente.
static func apply_ember(button: Button, ghost: bool = false) -> void:
	var maker := Callable(UITheme, "ghost_button") if ghost else Callable(UITheme, "ember_button")
	button.add_theme_stylebox_override("normal", maker.call("normal"))
	button.add_theme_stylebox_override("hover", maker.call("hover"))
	button.add_theme_stylebox_override("pressed", maker.call("pressed"))
	button.add_theme_stylebox_override("disabled", maker.call("disabled"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var texto := Palette.PARCHMENT if ghost else Palette.ON_EMBER
	button.add_theme_color_override("font_color", texto)
	button.add_theme_color_override("font_hover_color", texto)
	button.add_theme_color_override("font_pressed_color", texto)
	button.add_theme_color_override("font_disabled_color", Color(texto, 0.5))

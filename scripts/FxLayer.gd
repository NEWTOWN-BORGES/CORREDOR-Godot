extends Control
class_name FxLayer

# Camada de efeitos por cima do tabuleiro — números a subir, rasto do golpe,
# caveira na morte e a carta a voar da mão para a casa.
#
# Tradução das animações do style.css: .dmg-float, .attack-trail-line,
# .skull-pop e .travel-clone.

# Cores dos números, conforme o que aconteceu (do style.css)
const COR_DANO := Color("ff4a36")
const COR_CURA := Color("38ef7d")
const COR_ESCUDO := Color("56ccf2")
const COR_BUFF := Color("f2c94c")

const T_FLOAT := 1.1
const T_TRAIL := 0.5
const T_SKULL := 0.7
const T_TRAVEL := 0.42

# Posto a 0 pelos testes, para não esperarem por animações.
var speed: float = 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _enabled() -> bool:
	return speed > 0.0

func _dur(seconds: float) -> float:
	return seconds / speed

func _cor(kind: String) -> Color:
	match kind:
		"cura": return COR_CURA
		"escudo": return COR_ESCUDO
		"buff": return COR_BUFF
		_: return COR_DANO

# ---------------------------------------------------------------- números

# Número a subir e a desvanecer sobre a carta atingida (.dmg-float).
func float_number(centro_global: Vector2, texto: String, kind: String = "dano") -> void:
	if not _enabled():
		return

	var label := Label.new()
	label.text = texto
	label.add_theme_font_size_override("font_size", 24 if kind == "dano" else 22)
	label.add_theme_color_override("font_color", _cor(kind))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate = Color(1, 1, 1, 0)
	add_child(label)

	# Centrar exige o tamanho já calculado
	await get_tree().process_frame
	if not is_instance_valid(label):
		return
	var inicio := centro_global - global_position - Vector2(label.size.x * 0.5, 0)
	label.position = inicio

	# 0% invisível e a subir, 25% no auge, 100% desvanecido mais acima
	var tw := create_tween()
	tw.set_parallel(false)
	tw.tween_property(label, "modulate", Color(1, 1, 1, 1), _dur(T_FLOAT * 0.25))
	tw.parallel().tween_property(label, "position", inicio + Vector2(0, -14), _dur(T_FLOAT * 0.25))
	tw.parallel().tween_property(label, "scale", Vector2(1.25, 1.25), _dur(T_FLOAT * 0.25))
	tw.tween_property(label, "modulate", Color(1, 1, 1, 0), _dur(T_FLOAT * 0.75))
	tw.parallel().tween_property(label, "position", inicio + Vector2(0, -46), _dur(T_FLOAT * 0.75))
	tw.parallel().tween_property(label, "scale", Vector2.ONE, _dur(T_FLOAT * 0.75))
	tw.tween_callback(label.queue_free)

# ---------------------------------------------------------------- rasto

# Risco luminoso entre quem bate e quem leva (.attack-trail-line).
func attack_trail(de_global: Vector2, para_global: Vector2) -> void:
	if not _enabled():
		return

	var delta := para_global - de_global
	var comprimento := delta.length()
	if comprimento < 1.0:
		return

	var linha := ColorRect.new()
	linha.color = Palette.EMBER_400
	linha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	linha.size = Vector2(comprimento, 4)
	linha.pivot_offset = Vector2(0, 2)
	linha.position = de_global - global_position - Vector2(0, 2)
	linha.rotation = delta.angle()
	add_child(linha)

	var tw := create_tween()
	tw.tween_property(linha, "modulate", Color(1, 1, 1, 0), _dur(T_TRAIL))
	tw.parallel().tween_property(linha, "scale", Vector2(1, 0.2), _dur(T_TRAIL))
	tw.tween_callback(linha.queue_free)

# ---------------------------------------------------------------- morte

# Caveira a saltar sobre a carta que morreu (.skull-pop).
func skull_pop(centro_global: Vector2) -> void:
	if not _enabled():
		return

	var label := Label.new()
	label.text = "✝"
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Palette.PARCHMENT)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate = Color(1, 1, 1, 0)
	label.scale = Vector2(0.3, 0.3)
	add_child(label)

	await get_tree().process_frame
	if not is_instance_valid(label):
		return
	var inicio := centro_global - global_position - label.size * 0.5
	label.pivot_offset = label.size * 0.5
	label.position = inicio

	var tw := create_tween()
	tw.tween_property(label, "modulate", Color(1, 1, 1, 1), _dur(T_SKULL * 0.3))
	tw.parallel().tween_property(label, "scale", Vector2(1.3, 1.3), _dur(T_SKULL * 0.3))
	tw.tween_property(label, "modulate", Color(1, 1, 1, 0), _dur(T_SKULL * 0.7))
	tw.parallel().tween_property(label, "scale", Vector2.ONE, _dur(T_SKULL * 0.7))
	tw.parallel().tween_property(label, "position", inicio + Vector2(0, -20), _dur(T_SKULL * 0.7))
	tw.tween_callback(label.queue_free)

# ---------------------------------------------------------------- viagem

# A carta voa da mão para a casa, com um arco por cima (.travel-clone).
func travel_card(textura: Texture2D, de: Rect2, para: Rect2) -> void:
	if not _enabled() or textura == null:
		return

	var clone := TextureRect.new()
	clone.texture = textura
	clone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	clone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	clone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clone.position = de.position - global_position
	clone.size = de.size
	clone.pivot_offset = de.size * 0.5
	add_child(clone)

	var fim := para.position - global_position
	# Ponto alto do arco, a meio caminho e mais acima
	var meio := Vector2(
		(clone.position.x + fim.x) * 0.5,
		min(clone.position.y, fim.y) - 70.0
	)

	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(clone, "position", meio, _dur(T_TRAVEL * 0.55))
	tw.parallel().tween_property(clone, "rotation", deg_to_rad(-8), _dur(T_TRAVEL * 0.55))
	tw.tween_property(clone, "position", fim, _dur(T_TRAVEL * 0.45))
	tw.parallel().tween_property(clone, "size", para.size, _dur(T_TRAVEL * 0.45))
	tw.parallel().tween_property(clone, "rotation", 0.0, _dur(T_TRAVEL * 0.45))
	await tw.finished
	clone.queue_free()

extends Node

# Testes do som (Fase 10).
#
#   godot --headless --path . res://scenes/TestAudio.tscn
#
# Em headless não há placa de som, mas dá para verificar o que interessa:
# que as ondas são geradas, que têm a duração e o formato certos, que ficam
# guardadas em vez de serem refeitas, e que o silêncio cala tudo.

var _passed := 0
var _failed := 0

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("\n=== CORREDOR — testes de som ===\n")
	var tree := get_tree()

	test_autoload_ready()
	test_every_effect_generates()
	test_durations_match_web()
	test_samples_are_audible()
	test_cache_reuses()
	test_waveforms()
	test_mute_silences()
	await test_music_cycle()

	print("\n--- %d passaram, %d falharam ---\n" % [_passed, _failed])
	tree.quit(1 if _failed > 0 else 0)

# ---------------------------------------------------------------- utilitários

func check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  ok   %s" % label)
	else:
		_failed += 1
		print("  FALHA %s" % label)

func check_near(actual: float, expected: float, tol: float, label: String) -> void:
	if abs(actual - expected) <= tol:
		_passed += 1
		print("  ok   %s" % label)
	else:
		_failed += 1
		print("  FALHA %s  (esperado %.3f, obtido %.3f)" % [label, expected, actual])

const EFEITOS := ["carta", "unidade", "apoio", "golpe", "impacto", "morte",
	"cura", "cerco", "passar", "clique", "erro", "vitoria", "derrota"]

func duracao(stream: AudioStreamWAV) -> float:
	# 16 bits mono: 2 bytes por amostra
	return float(stream.data.size()) / 2.0 / float(stream.mix_rate)

# Maior amplitude do stream, entre 0 e 1
func pico(stream: AudioStreamWAV) -> float:
	var maior := 0
	var dados := stream.data
	var passo: int = max(2, (dados.size() / 2 / 400) * 2)
	for i in range(0, dados.size() - 1, passo):
		var v: int = dados.decode_s16(i)
		maior = max(maior, abs(v))
	return float(maior) / 32767.0

# ---------------------------------------------------------------- testes

func test_autoload_ready() -> void:
	print("Autoload do som")
	check(Sfx != null, "Sfx registado")
	check(not Sfx.is_muted(), "começa com som")
	check(Sfx.get_child_count() >= Sfx.CANAIS_SIMULTANEOS, "canais criados")

func test_every_effect_generates() -> void:
	print("Todos os efeitos geram onda")
	for nome in EFEITOS:
		var s: AudioStreamWAV = Sfx._stream_de(nome)
		if s == null:
			check(false, "%s gerado" % nome)
			continue
		var ok: bool = s.data.size() > 0 \
			and s.format == AudioStreamWAV.FORMAT_16_BITS \
			and s.mix_rate == Sfx.RATE \
			and not s.stereo
		check(ok, "%s: %d amostras, 16 bits mono a %d Hz" % [
			nome, s.data.size() / 2, s.mix_rate])

func test_durations_match_web() -> void:
	print("Durações batem com o sound.js")
	# Valores do web: tone/noiseBurst mais longos de cada efeito
	var esperado := {
		"clique": 0.08, "erro": 0.15, "passar": 0.12,
		"carta": 0.20, "golpe": 0.15, "impacto": 0.25,
		"morte": 0.50, "cerco": 0.60, "vitoria": 1.10, "derrota": 1.10
	}
	for nome in esperado:
		var s: AudioStreamWAV = Sfx._stream_de(nome)
		check_near(duracao(s), float(esperado[nome]), 0.01, "%s dura %.2fs" % [nome, esperado[nome]])

func test_samples_are_audible() -> void:
	print("As ondas têm mesmo sinal")
	for nome in EFEITOS:
		var s: AudioStreamWAV = Sfx._stream_de(nome)
		var p := pico(s)
		check(p > 0.02, "%s tem amplitude (pico %.2f)" % [nome, p])
		check(p <= 1.0, "%s não satura" % nome)

func test_cache_reuses() -> void:
	print("Ondas geradas uma vez só")
	var primeira: AudioStreamWAV = Sfx._stream_de("impacto")
	var segunda: AudioStreamWAV = Sfx._stream_de("impacto")
	check(primeira == segunda, "segunda chamada devolve a mesma onda")

	# Gerar de novo custaria tempo; em cache é imediato
	var inicio := Time.get_ticks_usec()
	for i in range(200):
		Sfx._stream_de("impacto")
	var decorrido := Time.get_ticks_usec() - inicio
	check(decorrido < 20000, "200 pedidos em %d µs" % decorrido)

func test_waveforms() -> void:
	print("Formas de onda")
	# Quadrada só tem dois valores; seno passeia por muitos
	check_near(Sfx._onda(Sfx.QUADRADA, 0.25), 1.0, 0.001, "quadrada sobe na primeira metade")
	check_near(Sfx._onda(Sfx.QUADRADA, 0.75), -1.0, 0.001, "e desce na segunda")

	check_near(Sfx._onda(Sfx.SERRA, 0.0), -1.0, 0.001, "serra começa em baixo")
	check_near(Sfx._onda(Sfx.SERRA, 1.0), 1.0, 0.001, "e acaba em cima")

	check_near(Sfx._onda(Sfx.TRIANGULO, 0.5), -1.0, 0.001, "triângulo no vale a meio")
	check_near(Sfx._onda(Sfx.TRIANGULO, 0.0), 1.0, 0.001, "e no pico nas pontas")

	check_near(Sfx._onda(Sfx.SENO, 0.25), 1.0, 0.001, "seno no máximo a um quarto")
	check_near(Sfx._onda(Sfx.SENO, 0.5), 0.0, 0.001, "e a cruzar o zero a meio")

func test_mute_silences() -> void:
	print("Silêncio cala tudo")
	Sfx.set_muted(false)
	Sfx.start_music()
	check(Sfx.is_music_playing(), "música a tocar")

	Sfx.set_muted(true)
	check(Sfx.is_muted(), "ficou em silêncio")
	check(not Sfx.is_music_playing(), "música parou")

	# Tocar em silêncio não pode arrancar nenhum canal
	Sfx.impacto()
	var algum_a_tocar := false
	for child in Sfx.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing:
			algum_a_tocar = true
	check(not algum_a_tocar, "pedir um som em silêncio não toca nada")

	check(not Sfx.toggle_muted(), "alternar devolve o som")
	check(not Sfx.is_muted(), "voltou a ter som")

func test_music_cycle() -> void:
	print("Música percorre as notas")
	Sfx.set_muted(false)
	Sfx.stop_music()
	Sfx._bgm_passo = 0
	Sfx.start_music()

	check(Sfx.is_music_playing(), "arrancou")
	check(Sfx._bgm_passo > 0, "tocou a primeira nota logo")

	# De quatro em quatro compassos junta a oitava abaixo — essa nota é mais
	# longa, por isso a onda é maior
	var normal: AudioStreamWAV = Sfx._cache.get("bgm_1")
	var grave: AudioStreamWAV = Sfx._cache.get("bgm_0_grave")
	check(grave != null, "primeira nota é das graves")
	if grave != null:
		check(pico(grave) > 0.02, "nota grave tem sinal")

	# Deixar correr um compasso para vir a nota seguinte
	await get_tree().create_timer(Sfx.BGM_INTERVALO + 0.2).timeout
	check(Sfx._bgm_passo >= 2, "avançou para a nota seguinte")

	normal = Sfx._cache.get("bgm_1")
	check(normal != null, "segunda nota gerada e guardada")

	Sfx.stop_music()
	check(not Sfx.is_music_playing(), "parou quando pedido")

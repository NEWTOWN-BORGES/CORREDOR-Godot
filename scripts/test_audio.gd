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
	test_envelope_adsr()
	test_buses()
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

func check_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("  ok   %s" % label)
	else:
		_failed += 1
		print("  FALHA %s  (esperado %s, obtido %s)" % [label, str(expected), str(actual)])

func check_near(actual: float, expected: float, tol: float, label: String) -> void:
	if abs(actual - expected) <= tol:
		_passed += 1
		print("  ok   %s" % label)
	else:
		_failed += 1
		print("  FALHA %s  (esperado %.3f, obtido %.3f)" % [label, expected, actual])

const EFEITOS := ["clique", "realce", "erro", "passar", "turno",
	"carta", "compra", "unidade", "reforco", "equipar", "apoio", "cura",
	"golpe", "impacto", "morte", "ruptura", "cerco", "alerta",
	"vitoria", "derrota"]

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
	check(Sfx.get_child_count() >= Sfx.CANAIS_SFX, "canais criados")

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
	print("Durações de cada efeito")
	# O tampão de cada efeito, tal como é construído
	var esperado := {
		"clique": 0.08, "realce": 0.06, "erro": 0.18, "passar": 0.14,
		"carta": 0.24, "compra": 0.20, "unidade": 0.30, "reforco": 0.45,
		"golpe": 0.18, "impacto": 0.32, "morte": 0.60, "ruptura": 0.70,
		"cerco": 0.75, "alerta": 0.60, "vitoria": 1.50, "derrota": 1.50
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
	var primeiro: AudioStreamWAV = Sfx._cache.get("bgm_0")
	check(primeiro != null, "primeiro compasso gerado")
	if primeiro != null:
		check(pico(primeiro) > 0.01, "tem sinal")
		check(duracao(primeiro) > 1.5, "compasso longo: leva melodia, baixo e acorde")

	# Deixar correr um compasso para vir a nota seguinte
	await get_tree().create_timer(Sfx.BGM_INTERVALO + 0.2).timeout
	check(Sfx._bgm_passo >= 2, "avançou para a nota seguinte")

	check(Sfx._cache.get("bgm_1") != null, "segundo compasso gerado e guardado")
	check_eq(Sfx.BGM_MELODIA.size(), 16, "sequência de 16 compassos")

	Sfx.stop_music()
	check(not Sfx.is_music_playing(), "parou quando pedido")

func test_envelope_adsr() -> void:
	print("Envelope ADSR")
	# ataque 0.1, decaimento 0.2, sustentação 0.5, libertação 0.3
	var n := 1000
	check_near(Sfx._envelope(0, n, 0.1, 0.2, 0.5, 0.3), 0.0, 0.01, "começa em silêncio")
	check_near(Sfx._envelope(100, n, 0.1, 0.2, 0.5, 0.3), 1.0, 0.02, "no fim do ataque está no pico")
	check_near(Sfx._envelope(300, n, 0.1, 0.2, 0.5, 0.3), 0.5, 0.02, "desce até à sustentação")
	check_near(Sfx._envelope(500, n, 0.1, 0.2, 0.5, 0.3), 0.5, 0.02, "e mantém-se lá")
	check_near(Sfx._envelope(999, n, 0.1, 0.2, 0.5, 0.3), 0.0, 0.02, "acaba em silêncio")

	# Sem sustentação comporta-se como o envelope antigo
	check(Sfx._envelope(500, n, 0.05, 0.4, 0.0, 0.3) < 0.05, "sem sustentação, cai a zero")

func test_buses() -> void:
	print("Barramentos de áudio")
	var musica := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	check(musica > 0, "barramento Music existe")
	check(sfx > 0, "barramento SFX existe")
	check(AudioServer.get_bus_effect_count(sfx) > 0, "SFX tem reverberação")
	check(AudioServer.get_bus_volume_db(musica) < 0.0, "música fica atrás na mistura")

	# Os canais estão nos barramentos certos
	var em_sfx := 0
	var em_musica := 0
	for child in Sfx.get_children():
		if child is AudioStreamPlayer:
			if (child as AudioStreamPlayer).bus == "SFX":
				em_sfx += 1
			elif (child as AudioStreamPlayer).bus == "Music":
				em_musica += 1
	check_eq(em_sfx, Sfx.CANAIS_SFX, "%d canais de efeitos" % Sfx.CANAIS_SFX)
	check_eq(em_musica, Sfx.CANAIS_MUSICA, "%d canais de música" % Sfx.CANAIS_MUSICA)

	# Volumes separados: baixar a música não cala os efeitos
	Sfx.set_music_volume_db(-30.0)
	check(AudioServer.get_bus_volume_db(musica) < AudioServer.get_bus_volume_db(sfx),
		"música desceu sem levar os efeitos atrás")
	Sfx.set_music_volume_db(0.0)

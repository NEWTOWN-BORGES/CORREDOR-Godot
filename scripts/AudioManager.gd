extends Node
# Autoload: Sfx
#
# Som sintetizado — sem um único ficheiro de áudio. As ondas são geradas em
# memória para AudioStreamWAV, uma vez por efeito, e ficam guardadas.
#
# Três barramentos (Master, Music, SFX) com reverberação no SFX, para os
# golpes e o cerco terem cauda em vez de soarem secos.

const RATE := 22050
const CANAIS_SFX := 10
const CANAIS_MUSICA := 3

# Formas de onda
const SENO := "seno"
const TRIANGULO := "triangulo"
const SERRA := "serra"
const QUADRADA := "quadrada"

# --- Música ---------------------------------------------------------------
# Ré menor. A sequência tem 16 compassos: melodia por cima, baixo de quatro
# em quatro, e um acorde longo a cada oito — em vez de uma nota solta.
const BGM_INTERVALO := 0.65
const BGM_NOTAS := [146.83, 164.81, 196.00, 220.00, 246.94, 293.66, 329.63, 392.00]
const BGM_MELODIA := [5, 4, 2, 4, 5, 7, 5, 4, 2, 1, 0, 1, 2, 4, 2, 1]
const BGM_BAIXO := [146.83, 174.61, 130.81, 196.00]

var muted: bool = false
var volume_musica: float = 0.0   # em decibéis, 0 = como foi gerado
var volume_sfx: float = 0.0

var _cache: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_players: Array[AudioStreamPlayer] = []
var _proximo_sfx := 0
var _proximo_musica := 0

var _bgm_timer: Timer = null
var _bgm_passo: int = 0
var _bgm_a_tocar: bool = false

var _bus_musica := 0
var _bus_sfx := 0

func _ready() -> void:
	_setup_buses()

	for i in range(CANAIS_SFX):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)

	for i in range(CANAIS_MUSICA):
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_music_players.append(p)

	_bgm_timer = Timer.new()
	_bgm_timer.wait_time = BGM_INTERVALO
	_bgm_timer.timeout.connect(_bgm_tick)
	add_child(_bgm_timer)

# Barramentos próprios, para poder baixar a música sem calar os efeitos.
func _setup_buses() -> void:
	_bus_musica = _ensure_bus("Music")
	_bus_sfx = _ensure_bus("SFX")

	# Reverberação curta no SFX: dá cauda aos golpes sem os embaciar
	if AudioServer.get_bus_effect_count(_bus_sfx) == 0:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.42
		reverb.damping = 0.55
		reverb.wet = 0.18
		reverb.dry = 0.92
		AudioServer.add_bus_effect(_bus_sfx, reverb)

	# Música mais atrás na mistura
	AudioServer.set_bus_volume_db(_bus_musica, -7.0)

func _ensure_bus(nome: String) -> int:
	var idx := AudioServer.get_bus_index(nome)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, nome)
	AudioServer.set_bus_send(idx, "Master")
	return idx

func _exit_tree() -> void:
	stop_music()
	for p in _sfx_players + _music_players:
		p.stop()
		p.stream = null
	_cache.clear()

# ---------------------------------------------------------------- síntese

# Uma amostra da forma de onda, com a fase normalizada entre 0 e 1.
func _onda(tipo: String, fase: float) -> float:
	match tipo:
		TRIANGULO:
			return 4.0 * absf(fase - 0.5) - 1.0
		SERRA:
			return 2.0 * fase - 1.0
		QUADRADA:
			return 1.0 if fase < 0.5 else -1.0
		_:
			return sin(TAU * fase)

# Envelope ADSR. O anterior só subia e caía; com sustentação as notas longas
# param de soar como se estivessem sempre a morrer.
func _envelope(i: int, n: int, ataque: float, decaimento: float, sustentacao: float, libertacao: float) -> float:
	var t := float(i) / float(max(1, n))
	if t < ataque:
		return t / maxf(0.0001, ataque)
	if t < ataque + decaimento:
		var d: float = (t - ataque) / maxf(0.0001, decaimento)
		return lerpf(1.0, sustentacao, d)
	if t < 1.0 - libertacao:
		return sustentacao
	var r: float = (t - (1.0 - libertacao)) / maxf(0.0001, libertacao)
	return lerpf(sustentacao, 0.0, r * r)

# Escreve uma nota no tampão, somando ao que já lá está.
func _tom(buf: PackedFloat32Array, freq: float, dur: float, tipo: String,
		vol: float, end_freq: float = 0.0, delay: float = 0.0,
		ataque := 0.06, decaimento := 0.16, sustentacao := 0.65, libertacao := 0.45) -> void:
	var inicio := int(delay * RATE)
	var n := int(dur * RATE)
	var fase := 0.0

	for i in range(n):
		var idx := inicio + i
		if idx >= buf.size():
			break
		var t := float(i) / float(n)

		var f := freq
		if end_freq > 0.0:
			f = freq * pow(max(1.0, end_freq) / freq, t)
		fase = fmod(fase + f / float(RATE), 1.0)

		buf[idx] += _onda(tipo, fase) * vol * _envelope(i, n, ataque, decaimento, sustentacao, libertacao)

# Rajada de ruído com passa-baixo de um pólo.
func _ruido(buf: PackedFloat32Array, dur: float, vol: float,
		filtro_hz: float, delay: float = 0.0, curva := 2.0) -> void:
	var inicio := int(delay * RATE)
	var n := int(dur * RATE)
	if n <= 0:
		return

	var alpha: float = 1.0 - exp(-TAU * filtro_hz / float(RATE))
	var y := 0.0

	for i in range(n):
		var idx := inicio + i
		if idx >= buf.size():
			break
		var x := randf() * 2.0 - 1.0
		y += (x - y) * alpha
		var decaimento := pow(1.0 - float(i) / float(n), curva)
		buf[idx] += y * vol * decaimento

# Corpo metálico: várias parciais desafinadas, para o entrechocar de armas.
func _metal(buf: PackedFloat32Array, base: float, dur: float, vol: float, delay: float = 0.0) -> void:
	var parciais := [1.0, 2.76, 5.40, 8.93]
	for i in range(parciais.size()):
		var peso: float = vol / float(i + 2)
		_tom(buf, base * float(parciais[i]), dur, SENO, peso, 0.0, delay, 0.005, 0.3, 0.1, 0.65)

# Converte o tampão para 16 bits, com limitador suave para não estalar.
func _para_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in range(buf.size()):
		# tanh comprime os picos em vez de os cortar a direito
		var amostra: float = clampf(_saturar(buf[i]), -1.0, 1.0)
		bytes.encode_s16(i * 2, int(amostra * 32000.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream

func _saturar(x: float) -> float:
	if absf(x) < 0.7:
		return x
	var sinal := signf(x)
	var a := absf(x)
	return sinal * (0.7 + (1.0 - 0.7) * tanh((a - 0.7) / (1.0 - 0.7)))

func _buffer(dur: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(dur * RATE) + 1)
	buf.fill(0.0)
	return buf

# ---------------------------------------------------------------- efeitos

func _stream_de(nome: String) -> AudioStreamWAV:
	if _cache.has(nome):
		return _cache[nome]
	var stream := _construir(nome)
	_cache[nome] = stream
	return stream

func _construir(nome: String) -> AudioStreamWAV:
	match nome:
		# --- interface ---
		"clique":
			var b := _buffer(0.08)
			_tom(b, 700, 0.05, QUADRADA, 0.06, 0.0, 0.0, 0.02, 0.2, 0.3, 0.6)
			return _para_stream(b)
		"realce":
			# Toque muito curto ao passar o rato numa carta
			var b := _buffer(0.06)
			_tom(b, 1180, 0.035, SENO, 0.05, 1400, 0.0, 0.02, 0.2, 0.2, 0.7)
			return _para_stream(b)
		"erro":
			var b := _buffer(0.18)
			_tom(b, 160, 0.12, QUADRADA, 0.10)
			_tom(b, 120, 0.14, SERRA, 0.06, 90, 0.02)
			return _para_stream(b)
		"passar":
			var b := _buffer(0.14)
			_tom(b, 320, 0.09, QUADRADA, 0.08, 260)
			_ruido(b, 0.07, 0.04, 900, 0.01)
			return _para_stream(b)
		"turno":
			# Sino grave a marcar a mudança de turno
			var b := _buffer(0.9)
			_metal(b, 196.0, 0.8, 0.13)
			return _para_stream(b)

		# --- cartas ---
		"carta":
			var b := _buffer(0.24)
			_tom(b, 260, 0.16, TRIANGULO, 0.16, 480)
			_ruido(b, 0.09, 0.05, 2600, 0.0, 3.0)
			return _para_stream(b)
		"compra":
			# Roçar de carta a sair do baralho
			var b := _buffer(0.2)
			_ruido(b, 0.14, 0.10, 3200, 0.0, 1.4)
			_tom(b, 420, 0.10, TRIANGULO, 0.05, 620)
			return _para_stream(b)
		"unidade":
			var b := _buffer(0.3)
			_tom(b, 200, 0.14, TRIANGULO, 0.18, 340)
			_ruido(b, 0.10, 0.10, 700, 0.02)
			_metal(b, 320.0, 0.18, 0.05, 0.03)
			return _para_stream(b)
		"reforco":
			# Chegada de reforço: dois toques a subir
			var b := _buffer(0.45)
			_tom(b, 392, 0.16, TRIANGULO, 0.11, 0.0, 0.0)
			_tom(b, 523, 0.22, TRIANGULO, 0.12, 0.0, 0.13)
			return _para_stream(b)
		"equipar":
			var b := _buffer(0.35)
			_metal(b, 560.0, 0.3, 0.14)
			_ruido(b, 0.06, 0.06, 4000, 0.0, 3.0)
			return _para_stream(b)
		"apoio":
			var b := _buffer(0.42)
			var notas := [660.0, 880.0, 1100.0, 1320.0]
			for i in range(notas.size()):
				_tom(b, notas[i], 0.18, SENO, 0.13, 0.0, float(i) * 0.045, 0.05, 0.2, 0.5, 0.5)
			return _para_stream(b)
		"cura":
			var b := _buffer(0.5)
			var notas := [440.0, 554.0, 659.0, 880.0]
			for i in range(notas.size()):
				_tom(b, notas[i], 0.24, SENO, 0.14, 0.0, float(i) * 0.05, 0.08, 0.2, 0.6, 0.5)
			return _para_stream(b)

		# --- combate ---
		"golpe":
			var b := _buffer(0.18)
			_ruido(b, 0.10, 0.15, 2400)
			_tom(b, 350, 0.10, SERRA, 0.10, 150, 0.0, 0.01, 0.2, 0.3, 0.6)
			return _para_stream(b)
		"impacto":
			var b := _buffer(0.32)
			_tom(b, 160, 0.20, SERRA, 0.26, 50, 0.0, 0.005, 0.15, 0.35, 0.6)
			_ruido(b, 0.14, 0.20, 900)
			_metal(b, 240.0, 0.22, 0.08, 0.01)
			return _para_stream(b)
		"morte":
			var b := _buffer(0.6)
			_tom(b, 240, 0.45, SERRA, 0.22, 30, 0.0, 0.01, 0.25, 0.3, 0.6)
			_ruido(b, 0.28, 0.14, 500, 0.02, 1.2)
			return _para_stream(b)
		"ruptura":
			# Pressão a romper: subida rápida antes do embate
			var b := _buffer(0.7)
			_tom(b, 180, 0.28, SERRA, 0.14, 620, 0.0, 0.1, 0.2, 0.7, 0.3)
			_tom(b, 90, 0.42, SENO, 0.30, 40, 0.26)
			_ruido(b, 0.3, 0.20, 700, 0.26)
			return _para_stream(b)
		"cerco":
			var b := _buffer(0.75)
			_tom(b, 90, 0.55, SENO, 0.33, 30)
			_tom(b, 61, 0.6, TRIANGULO, 0.16, 28)
			_ruido(b, 0.4, 0.22, 400, 0.0, 1.3)
			return _para_stream(b)
		"alerta":
			# Torre em perigo: dois toques dissonantes
			var b := _buffer(0.6)
			_tom(b, 466, 0.22, TRIANGULO, 0.12)
			_tom(b, 440, 0.26, TRIANGULO, 0.12, 0.0, 0.22)
			return _para_stream(b)

		# --- fim de partida ---
		"vitoria":
			var b := _buffer(1.5)
			var notas := [523.0, 659.0, 784.0, 1046.0, 1318.0]
			for i in range(notas.size()):
				_tom(b, notas[i], 0.45, TRIANGULO, 0.22, 0.0, float(i) * 0.14, 0.04, 0.2, 0.6, 0.4)
			# acorde final sustentado
			for f in [523.0, 659.0, 784.0]:
				_tom(b, f, 0.7, SENO, 0.10, 0.0, 0.7, 0.06, 0.2, 0.7, 0.35)
			return _para_stream(b)
		"derrota":
			var b := _buffer(1.5)
			var notas := [392.0, 349.0, 293.0, 220.0, 164.0]
			for i in range(notas.size()):
				_tom(b, notas[i], 0.5, SERRA, 0.17, 0.0, float(i) * 0.16, 0.05, 0.25, 0.55, 0.45)
			_tom(b, 110.0, 0.8, TRIANGULO, 0.14, 0.0, 0.7)
			return _para_stream(b)
		_:
			return _para_stream(_buffer(0.01))

# ---------------------------------------------------------------- tocar

func play(nome: String) -> void:
	if muted or _sfx_players.is_empty():
		return
	var stream := _stream_de(nome)
	if stream == null:
		return
	var p := _sfx_players[_proximo_sfx]
	_proximo_sfx = (_proximo_sfx + 1) % _sfx_players.size()
	p.stream = stream
	p.play()

func clique() -> void: play("clique")
func realce() -> void: play("realce")
func carta() -> void: play("carta")
func compra() -> void: play("compra")
func unidade() -> void: play("unidade")
func reforco() -> void: play("reforco")
func equipar() -> void: play("equipar")
func apoio() -> void: play("apoio")
func golpe() -> void: play("golpe")
func impacto() -> void: play("impacto")
func morte() -> void: play("morte")
func ruptura() -> void: play("ruptura")
func cura() -> void: play("cura")
func cerco() -> void: play("cerco")
func alerta() -> void: play("alerta")
func passar() -> void: play("passar")
func turno() -> void: play("turno")
func erro() -> void: play("erro")
func vitoria() -> void: play("vitoria")
func derrota() -> void: play("derrota")

# ---------------------------------------------------------------- música

func start_music() -> void:
	if _bgm_a_tocar or muted:
		return
	_bgm_a_tocar = true
	_bgm_passo = 0
	_bgm_timer.start()
	_bgm_tick()

func stop_music() -> void:
	_bgm_a_tocar = false
	if _bgm_timer != null:
		_bgm_timer.stop()
	for p in _music_players:
		p.stop()

func is_music_playing() -> bool:
	return _bgm_a_tocar

# Cada compasso toca uma nota da melodia; de quatro em quatro entra o baixo,
# de oito em oito um acorde longo por baixo de tudo.
func _bgm_tick() -> void:
	if muted or not _bgm_a_tocar:
		return

	var passo := _bgm_passo % BGM_MELODIA.size()
	var chave := "bgm_%d" % passo

	if not _cache.has(chave):
		var b := _buffer(2.2)
		var nota: float = BGM_NOTAS[int(BGM_MELODIA[passo]) % BGM_NOTAS.size()]
		_tom(b, nota, 0.9, SENO, 0.030, 0.0, 0.0, 0.12, 0.25, 0.55, 0.45)
		# oitava acima muito ténue, dá brilho sem pesar
		_tom(b, nota * 2.0, 0.7, SENO, 0.010, 0.0, 0.05, 0.15, 0.3, 0.4, 0.5)

		if passo % 4 == 0:
			var baixo: float = BGM_BAIXO[(passo / 4) % BGM_BAIXO.size()]
			_tom(b, baixo / 2.0, 1.5, TRIANGULO, 0.040, 0.0, 0.0, 0.1, 0.3, 0.6, 0.4)

		if passo % 8 == 0:
			# Acorde longo por baixo, a segurar a harmonia
			var raiz: float = BGM_BAIXO[(passo / 8) % BGM_BAIXO.size()]
			for mult in [1.0, 1.2, 1.5]:
				_tom(b, raiz * mult, 2.0, SENO, 0.014, 0.0, 0.0, 0.25, 0.3, 0.7, 0.4)

		_cache[chave] = _para_stream(b)

	if not _music_players.is_empty():
		var p := _music_players[_proximo_musica]
		_proximo_musica = (_proximo_musica + 1) % _music_players.size()
		p.stream = _cache[chave]
		p.play()

	_bgm_passo += 1

# ---------------------------------------------------------------- volumes

func set_music_volume_db(db: float) -> void:
	volume_musica = db
	AudioServer.set_bus_volume_db(_bus_musica, db - 7.0)

func set_sfx_volume_db(db: float) -> void:
	volume_sfx = db
	AudioServer.set_bus_volume_db(_bus_sfx, db)

func set_muted(v: bool) -> void:
	muted = v
	if v:
		stop_music()
		for p in _sfx_players:
			p.stop()
	else:
		start_music()

func is_muted() -> bool:
	return muted

func toggle_muted() -> bool:
	set_muted(not muted)
	return muted

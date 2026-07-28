extends Node
# Autoload: Sfx
#
# Som sintetizado — tradução de js/sound.js. O web usa a Web Audio API e não
# traz um único ficheiro de áudio; aqui as ondas são geradas em memória para
# AudioStreamWAV, uma vez por efeito, e guardadas.
#
# O browser exigia um gesto do utilizador antes de tocar seja o que for; em
# Godot não há essa restrição, por isso o "unlock" do web não tem equivalente.

const RATE := 22050
const CANAIS_SIMULTANEOS := 8

# Formas de onda
const SENO := "seno"
const TRIANGULO := "triangulo"
const SERRA := "serra"
const QUADRADA := "quadrada"

# Compasso da música de fundo, em segundos, e as notas que percorre
const BGM_INTERVALO := 0.65
const BGM_NOTAS := [146.83, 164.81, 196.00, 220.00, 246.94, 293.66, 329.63, 392.00]

var muted: bool = false

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _proximo: int = 0

var _bgm_timer: Timer = null
var _bgm_passo: int = 0
var _bgm_a_tocar: bool = false

func _ready() -> void:
	for i in range(CANAIS_SIMULTANEOS):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

	_bgm_timer = Timer.new()
	_bgm_timer.wait_time = BGM_INTERVALO
	_bgm_timer.timeout.connect(_bgm_tick)
	add_child(_bgm_timer)

# Sem isto o Godot queixa-se de objectos por libertar à saída: as ondas em
# cache continuam presas aos canais que as tocaram.
func _exit_tree() -> void:
	stop_music()
	for p in _players:
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

# Escreve uma nota no tampão, somando ao que já lá está.
# Espelha tone() do web: rampa exponencial de frequência e envelope que sobe
# depressa e desce até ao silêncio.
func _tom(buf: PackedFloat32Array, freq: float, dur: float, tipo: String,
		vol: float, end_freq: float = 0.0, delay: float = 0.0) -> void:
	var inicio := int(delay * RATE)
	var n := int(dur * RATE)
	var ataque: float = max(1.0, min(0.02, dur * 0.3) * RATE)
	var fase := 0.0

	for i in range(n):
		var idx := inicio + i
		if idx >= buf.size():
			break
		var t := float(i) / float(n)

		# Frequência: rampa exponencial até end_freq, se houver
		var f := freq
		if end_freq > 0.0:
			f = freq * pow(max(1.0, end_freq) / freq, t)
		fase = fmod(fase + f / float(RATE), 1.0)

		# Envelope: sobe em `ataque` amostras, depois cai exponencialmente
		var env := 0.0
		if float(i) < ataque:
			env = float(i) / ataque
		else:
			var restante := float(n - i) / float(max(1, n - int(ataque)))
			env = pow(restante, 2.2)

		buf[idx] += _onda(tipo, fase) * vol * env

# Rajada de ruído com filtro passa-baixo, como noiseBurst() do web.
func _ruido(buf: PackedFloat32Array, dur: float, vol: float,
		filtro_hz: float, delay: float = 0.0) -> void:
	var inicio := int(delay * RATE)
	var n := int(dur * RATE)
	if n <= 0:
		return

	# Passa-baixo de um pólo
	var alpha: float = 1.0 - exp(-TAU * filtro_hz / float(RATE))
	var y := 0.0

	for i in range(n):
		var idx := inicio + i
		if idx >= buf.size():
			break
		var x := randf() * 2.0 - 1.0
		y += (x - y) * alpha
		# O web faz o ruído desvanecer linearmente ao longo da rajada
		var decaimento := 1.0 - float(i) / float(n)
		buf[idx] += y * vol * decaimento * decaimento

# Converte o tampão de floats para 16 bits e embrulha num AudioStreamWAV.
func _para_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in range(buf.size()):
		var amostra: float = clampf(buf[i], -1.0, 1.0)
		var v := int(amostra * 32767.0)
		bytes.encode_s16(i * 2, v)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream

func _buffer(dur: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(dur * RATE) + 1)
	buf.fill(0.0)
	return buf

# ---------------------------------------------------------------- efeitos

# Constrói o efeito à primeira vez que é pedido e guarda-o.
func _stream_de(nome: String) -> AudioStreamWAV:
	if _cache.has(nome):
		return _cache[nome]

	var stream := _construir(nome)
	_cache[nome] = stream
	return stream

func _construir(nome: String) -> AudioStreamWAV:
	match nome:
		"carta":
			var b := _buffer(0.2)
			_tom(b, 260, 0.16, TRIANGULO, 0.16, 480)
			return _para_stream(b)
		"unidade":
			var b := _buffer(0.2)
			_tom(b, 200, 0.14, TRIANGULO, 0.18, 340)
			_ruido(b, 0.08, 0.08, 700, 0.02)
			return _para_stream(b)
		"apoio":
			var b := _buffer(0.35)
			var notas := [660.0, 880.0, 1100.0, 1320.0]
			for i in range(notas.size()):
				_tom(b, notas[i], 0.16, SENO, 0.14, 0.0, float(i) * 0.045)
			return _para_stream(b)
		"golpe":
			var b := _buffer(0.15)
			_ruido(b, 0.10, 0.15, 2400)
			_tom(b, 350, 0.10, SERRA, 0.10, 150)
			return _para_stream(b)
		"impacto":
			var b := _buffer(0.25)
			_tom(b, 160, 0.20, SERRA, 0.28, 50)
			_ruido(b, 0.14, 0.22, 900)
			return _para_stream(b)
		"morte":
			var b := _buffer(0.5)
			_tom(b, 240, 0.45, SERRA, 0.24, 30)
			_ruido(b, 0.20, 0.15, 500)
			return _para_stream(b)
		"cura":
			var b := _buffer(0.4)
			var notas := [440.0, 554.0, 659.0, 880.0]
			for i in range(notas.size()):
				_tom(b, notas[i], 0.2, SENO, 0.16, 0.0, float(i) * 0.05)
			return _para_stream(b)
		"cerco":
			var b := _buffer(0.6)
			_tom(b, 90, 0.55, SENO, 0.35, 30)
			_ruido(b, 0.35, 0.25, 400)
			return _para_stream(b)
		"passar":
			var b := _buffer(0.12)
			_tom(b, 320, 0.09, QUADRADA, 0.08, 260)
			return _para_stream(b)
		"clique":
			var b := _buffer(0.08)
			_tom(b, 700, 0.05, QUADRADA, 0.06)
			return _para_stream(b)
		"erro":
			var b := _buffer(0.15)
			_tom(b, 160, 0.12, QUADRADA, 0.10)
			return _para_stream(b)
		"vitoria":
			var b := _buffer(1.1)
			var notas := [523.0, 659.0, 784.0, 1046.0, 1318.0]
			for i in range(notas.size()):
				_tom(b, notas[i], 0.35, TRIANGULO, 0.25, 0.0, float(i) * 0.14)
			return _para_stream(b)
		"derrota":
			var b := _buffer(1.1)
			var notas := [392.0, 349.0, 293.0, 220.0, 164.0]
			for i in range(notas.size()):
				_tom(b, notas[i], 0.4, SERRA, 0.20, 0.0, float(i) * 0.16)
			return _para_stream(b)
		_:
			return _para_stream(_buffer(0.01))

# ---------------------------------------------------------------- tocar

func play(nome: String) -> void:
	if muted or _players.is_empty():
		return
	var stream := _stream_de(nome)
	if stream == null:
		return
	# Canais à vez, para sons sobrepostos não se cortarem
	var p := _players[_proximo]
	_proximo = (_proximo + 1) % _players.size()
	p.stream = stream
	p.play()

func clique() -> void: play("clique")
func carta() -> void: play("carta")
func unidade() -> void: play("unidade")
func apoio() -> void: play("apoio")
func golpe() -> void: play("golpe")
func impacto() -> void: play("impacto")
func morte() -> void: play("morte")
func cura() -> void: play("cura")
func cerco() -> void: play("cerco")
func passar() -> void: play("passar")
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

func is_music_playing() -> bool:
	return _bgm_a_tocar

# Uma nota por compasso; de quatro em quatro junta a oitava abaixo, como no web.
func _bgm_tick() -> void:
	if muted or not _bgm_a_tocar:
		return

	var nota: float = BGM_NOTAS[_bgm_passo % BGM_NOTAS.size()]
	var chave := "bgm_%d" % (_bgm_passo % BGM_NOTAS.size())
	var grave := _bgm_passo % 4 == 0
	if grave:
		chave += "_grave"

	if not _cache.has(chave):
		var b := _buffer(1.3)
		_tom(b, nota, 0.7, SENO, 0.035)
		if grave:
			_tom(b, nota / 2.0, 1.2, TRIANGULO, 0.045)
		_cache[chave] = _para_stream(b)

	if not _players.is_empty():
		var p := _players[_proximo]
		_proximo = (_proximo + 1) % _players.size()
		p.stream = _cache[chave]
		p.play()

	_bgm_passo += 1

# ---------------------------------------------------------------- silêncio

func set_muted(v: bool) -> void:
	muted = v
	if v:
		stop_music()
		for p in _players:
			p.stop()
	else:
		start_music()

func is_muted() -> bool:
	return muted

func toggle_muted() -> bool:
	set_muted(not muted)
	return muted

extends Node
## Autoload `Sfx`: one call plays a named sound, one call switches the music.
##
## Lookup order for a sound `name`: `assets/audio/sfx/<name>.ogg|.wav|.mp3`
## (a real file dropped in by the human), else the SoundBank synth. Music is
## `assets/audio/music/<track>.ogg|.mp3` only: no synthetic music, silence
## is better. Gameplay code never touches AudioStreamPlayers directly, so
## replacing a sound is a file, not a code change.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const EXTENSIONS := ["ogg", "wav", "mp3"]
const POOL_SIZE := 12

var enabled := true
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_base_db := -8.0
var _music_volume := 0.8
var _music_track: StringName = &""
## Names played since the last `clear_log()` (tests read this).
var played: Array[StringName] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		_players.append(player)
	_music = AudioStreamPlayer.new()
	_music.volume_db = _music_base_db + linear_to_db(_music_volume)
	add_child(_music)


## Plays `name` once. `pitch` around 1.0 adds variety without more files.
func play(name: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	played.append(name)
	if not enabled:
		return
	var stream := get_stream(name)
	if stream == null:
		return
	var player := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## The stream for `name` (file or synth), cached. Null when unknown.
func get_stream(name: StringName) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var stream: AudioStream = _load_file(SFX_DIR, name)
	if stream == null:
		stream = SoundBank.build(name)
	_streams[name] = stream
	return stream


func has(name: StringName) -> bool:
	return get_stream(name) != null


## Switches the background track; `&""` stops it. Same track = no restart.
func play_music(track: StringName) -> void:
	if track == _music_track:
		return
	_music_track = track
	_music.stop()
	if track == &"" or not enabled:
		return
	var stream := _load_file(MUSIC_DIR, track)
	if stream == null:
		return
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.set(&"loop", true)
	_music.stream = stream
	_music.play()


func current_music() -> StringName:
	return _music_track


func clear_log() -> void:
	played.clear()


func _load_file(directory: String, name: StringName) -> AudioStream:
	for ext: String in EXTENSIONS:
		var path: String = directory + String(name) + "." + ext
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null


## Settings menu: 0..1 on top of the track's base level.
func set_music_volume(value: float) -> void:
	_music_volume = clampf(value, 0.0, 1.0)
	if _music:
		_music.volume_db = _music_base_db + linear_to_db(maxf(_music_volume, 0.0001))

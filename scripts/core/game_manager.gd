extends Node
## Autoload: global game services.
##
## Kept deliberately small. It owns things that are genuinely global (mouse
## capture, the list of active players) and nothing that belongs to a character,
## a camera or a level. Player state stays on the player, so local co-op /
## multiplayer stay possible later (see CLAUDE_CODE_MASTER_PROMPT.md section 29).

signal player_registered(player: Node)
signal player_unregistered(player: Node)
signal mouse_capture_changed(captured: bool)
signal pause_changed(paused: bool)

## Active player characters, in join order. Index 0 is player one.
var players: Array[Node] = []

var _mouse_captured := false
var is_paused := false


## The game is Italian regardless of the OS language. Strings live in
## translations/text.csv (keys with en/it columns); code and data use keys
## and call tr() at display time.
const LOCALE := "it"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	TranslationServer.set_locale(LOCALE)
	# Browsers only allow pointer lock from a user gesture: on the Web the
	# first click captures the mouse (see _unhandled_input), on desktop we
	# capture right away.
	if not OS.has_feature("web"):
		set_mouse_captured(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PAUSE):
		set_paused(not is_paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.TOGGLE_MOUSE_CAPTURE):
		set_mouse_captured(not _mouse_captured)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not _mouse_captured and not is_paused:
		set_mouse_captured(true)


## Pauses the whole tree (menus keep running: PROCESS_MODE_ALWAYS) and frees
## the mouse for them; resuming captures it again.
func set_paused(paused: bool) -> void:
	if paused == is_paused:
		return
	is_paused = paused
	get_tree().paused = paused
	set_mouse_captured(not paused)
	Sfx.play(&"ui", -6.0)
	pause_changed.emit(paused)


func set_mouse_captured(captured: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_mouse_captured = captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	mouse_capture_changed.emit(captured)


func is_mouse_captured() -> bool:
	return _mouse_captured


func register_player(player: Node) -> int:
	if player in players:
		return players.find(player)
	players.append(player)
	if not player.tree_exiting.is_connected(unregister_player):
		player.tree_exiting.connect(unregister_player.bind(player))
	player_registered.emit(player)
	return players.size() - 1


func unregister_player(player: Node) -> void:
	if player in players:
		players.erase(player)
		player_unregistered.emit(player)


func get_player(index: int = 0) -> Node:
	return players[index] if index < players.size() else null

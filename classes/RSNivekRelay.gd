extends Node
class_name RSNivekRelay

## Consumes the nivek overlay relay over a websocket and re-emits cheer events as
## the same RSTwitchEventData signal the rest of the app already listens to
## (see RSTwitcher.cheered). Cheers-only for now: redemption frames are received
## so the cursor advances, but NOT emitted here -- redemptions stay on the direct
## Twitch EventSub path (RSTwitcher). See ~/code/nivek cmd/core-api overlay relay.
##
## Why route cheers through nivek instead of straight from Twitch: durable replay.
## The server keeps a per-broadcaster ordered log; we persist the highest seq we
## have processed and send it as `since` on (re)connect, so a restart or dropped
## socket replays every missed cheer exactly once instead of losing it.

## Mirrors RSTwitcher.cheered so consumers can bind to either source.
signal cheered(data: RSTwitchEventData)

## Custom Power-up redemptions (paid with Bits). These have no twitcher
## equivalent -- the addon predates the event -- so they only come via nivek.
signal power_up_redeemed(data: RSTwitchEventData)

static var _log: TwitchLogger = TwitchLogger.new(&"RSNivekRelay")

# Wire protocol (matches cmd/core-api/endpoints/overlay/connect.go +
# internal/libraries/overlayrelay/const.go).
const _MSG_HELLO := "hello"
const _MSG_READY := "ready"
const _MSG_EVENT := "event"

const _KIND_CHEER := "cheer"
const _KIND_REDEMPTION := "redemption"
const _KIND_POWER_UP := "power_up"

# Persisted delivery cursor: the highest per-user seq we have handled. Kept in a
# tiny standalone file rather than settings.tres so a per-cheer write never races
# the app's own settings saves.
const _CURSOR_PATH := "user://nivek_relay_cursor.txt"

var _ws: WebsocketClient
var _last_seq: int = 0
var _ready_seen: bool = false


## True when the relay is configured. When false, RSMain.cheer_source() falls
## back to the direct-Twitch path so cheers keep working as before.
func is_enabled() -> bool:
	return not _url().is_empty() and not _token().is_empty()


func start() -> void:
	if not is_enabled():
		_log.i("nivek relay disabled (relay url or device token not set); cheers stay on the Twitch path")
		return

	_last_seq = _load_cursor()

	_ws = WebsocketClient.new()
	_ws.name = &"NivekWebsocket"
	_ws.connection_url = _url()
	add_child(_ws)
	_ws.connection_established.connect(_on_open)
	_ws.connection_closed.connect(_on_closed)
	_ws.message_received.connect(_on_message)
	_ws.open_connection()

	_log.i("nivek relay starting -> %s (resuming from seq %d)" % [_url(), _last_seq])


# Secrets resolution, most secure first:
#   1. OS environment variable (never touches disk in the project)
#   2. a gitignored `.env` file next to the project (see nivek_relay.env.example)
#   3. the settings resource field (saved under the app data dir, not the repo)
# This keeps the device token out of any tracked file. Matches how the twitcher
# addon keeps its OAuth token in a gitignored .tres.
const _ENV_FILE := "res://nivek_relay.env"
var _env_cache: Dictionary
var _env_loaded: bool = false


func _url() -> String:
	var v := _from_env("NIVEK_RELAY_URL")
	if not v.is_empty():
		return v
	return RS.settings.nivek_relay_url.strip_edges()


func _token() -> String:
	var v := _from_env("NIVEK_DEVICE_TOKEN")
	if not v.is_empty():
		return v
	return RS.settings.nivek_device_token.strip_edges()


func _from_env(key: String) -> String:
	var v := OS.get_environment(key).strip_edges()
	if not v.is_empty():
		return v
	if not _env_loaded:
		_env_cache = _parse_env_file(_ENV_FILE)
		_env_loaded = true
	return str(_env_cache.get(key, "")).strip_edges()


func _parse_env_file(path: String) -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_log.w("could not open %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		var k := line.substr(0, eq).strip_edges()
		var val := line.substr(eq + 1).strip_edges()
		# Strip a single pair of surrounding quotes if present.
		if val.length() >= 2 and ((val.begins_with("\"") and val.ends_with("\"")) or (val.begins_with("'") and val.ends_with("'"))):
			val = val.substr(1, val.length() - 2)
		out[k] = val
	f.close()
	return out


func _on_open() -> void:
	# The token authenticates in the first frame (not a header): the server keeps
	# it out of proxy/request logs. `since` asks for everything after our cursor.
	_ready_seen = false
	var hello := {
		"type": _MSG_HELLO,
		"token": _token(),
		"since": _last_seq,
	}
	var err := _ws.send_text(JSON.stringify(hello))
	if err != OK:
		_log.e("failed to send hello: %s" % error_string(err))
	else:
		_log.d("sent hello (since=%d)" % _last_seq)


func _on_closed() -> void:
	# WebsocketClient reconnects on its own with backoff; _on_open re-sends hello
	# from the (advanced) cursor, so this is informational.
	_log.i("nivek relay connection closed; will reconnect")


func _on_message(bytes: PackedByteArray) -> void:
	var text := bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_log.w("dropping non-object frame: %s" % text)
		return

	var frame: Dictionary = parsed
	match str(frame.get("type", "")):
		_MSG_READY:
			_ready_seen = true
			_log.i("nivek relay caught up (ready) at seq %d" % _last_seq)
		_MSG_EVENT:
			_handle_event(frame.get("event", {}))
		_:
			# pong or anything else: nothing to do (WebSocketPeer auto-pongs pings).
			pass


func _handle_event(event: Variant) -> void:
	if typeof(event) != TYPE_DICTIONARY:
		return
	var ev: Dictionary = event
	var seq := int(ev.get("seq", 0))
	var kind := str(ev.get("kind", ""))
	var payload: Variant = ev.get("data", {})

	match kind:
		_KIND_CHEER:
			# nivek's cheer payload {user_id,user_login,user_name,is_anonymous,
			# bits,message} lines up field-for-field with what the existing parser
			# reads for "channel.cheer", so consumers get an identical event shape
			# whether it came from Twitch directly or via the relay.
			if typeof(payload) == TYPE_DICTIONARY:
				cheered.emit(RSTwitchEventData.create_from_event_body("channel.cheer", payload))
		_KIND_REDEMPTION:
			# Left to the direct-Twitch path for now (see file header).
			pass
		_KIND_POWER_UP:
			# nivek's flat PowerUpPayload {power_up_id, power_up_title, bits,
			# user_*} maps onto RSTwitchEventData via the matching parser case.
			if typeof(payload) == TYPE_DICTIONARY:
				power_up_redeemed.emit(RSTwitchEventData.create_from_event_body("channel.custom_power_up_redemption.add", payload))
		_:
			_log.w("nivek relay: unknown event kind '%s' (seq %d)" % [kind, seq])

	# Advance the cursor for EVERY event we consume -- including the redemption
	# frames we ignore -- so a reconnect never replays them. Persist after handling
	# so a crash mid-emit re-delivers rather than skips.
	if seq > _last_seq:
		_last_seq = seq
		_persist_cursor()


func _load_cursor() -> int:
	if not FileAccess.file_exists(_CURSOR_PATH):
		return 0
	var f := FileAccess.open(_CURSOR_PATH, FileAccess.READ)
	if f == null:
		_log.w("could not open cursor file %s: %s" % [_CURSOR_PATH, error_string(FileAccess.get_open_error())])
		return 0
	var s := f.get_as_text().strip_edges()
	f.close()
	return int(s) if s.is_valid_int() else 0


func _persist_cursor() -> void:
	var f := FileAccess.open(_CURSOR_PATH, FileAccess.WRITE)
	if f == null:
		_log.w("could not write cursor file %s: %s" % [_CURSOR_PATH, error_string(FileAccess.get_open_error())])
		return
	f.store_string(str(_last_seq))
	f.close()

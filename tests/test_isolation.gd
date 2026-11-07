# Network isolation shared by headless tests that boot the real RS autoload
# (tests/laser_stress.gd, tests/isolation_check.gd). Same stubs as
# tests/smoke_all.gd:_stub_network.
#
# Timing: call stub_network() from the test scene's _ready. RSMain._ready loads
# settings synchronously, then RSMain.start_everything() awaits one frame before
# it starts Twitch and creates/starts the nivek relay. The main scene's _ready
# runs inside that gap, so the stubs land before any connection is attempted.
# stub_network() refuses if the relay already exists, because clearing config
# after the relay has started would not stop it.
#
# What this does NOT cover: nodes in rs_main.tscn (Twitcher add-on) run their
# _ready before the test does. They only act on tokens from user://auth.conf, so
# the throwaway user data dir set up by tests/run_smoke.* is still required;
# is_isolated() checks for it.
extends RefCounted

const RELAY_ENV_VARS := ["NIVEK_DEVICE_TOKEN", "NIVEK_RELAY_URL"]


## Disables the nivek relay and Twitch for this run. Returns "" on success, or
## why the stubs could not be applied in time.
static func stub_network(rs: Node) -> String:
	if rs.nivek_relay != null:
		return "nivek relay already created before the stubs were applied"
	for key in RELAY_ENV_VARS:
		OS.unset_environment(key)
	rs.settings.nivek_device_token = ""
	rs.settings.nivek_relay_url = ""
	rs.settings.auto_connect = false
	rs.settings.client_id = "" # RSSettings.is_twitcher_setup() -> false, RSTwitcher.start() aborts
	rs.settings.client_secret = ""
	# RSMain adds the relay as its own child before calling start(); pin its
	# nivek_relay.env cache empty at that point so res://nivek_relay.env in the
	# checkout is never read.
	rs.child_entered_tree.connect(func(node: Node) -> void:
		if node is RSNivekRelay:
			node._env_cache = {}
			node._env_loaded = true
	)
	return ""


## True when the user data dir is inside RSO_SMOKE_DATA_DIR, the throwaway dir
## set by tests/run_smoke.sh / tests/run_smoke.ps1.
static func is_isolated() -> bool:
	var expected := OS.get_environment("RSO_SMOKE_DATA_DIR").replace("\\", "/").trim_suffix("/")
	if expected.is_empty():
		return false
	var actual := OS.get_user_data_dir().replace("\\", "/")
	if OS.get_name() == "Windows":
		return actual.to_lower().begins_with(expected.to_lower())
	return actual.begins_with(expected)


## After RS.all_started: "" if the relay is inert and Twitch did not start,
## otherwise what is wrong.
static func check_network_inert(rs: Node) -> String:
	var relay: RSNivekRelay = rs.nivek_relay
	if relay == null:
		return "RS.nivek_relay was never created"
	if not (relay._env_loaded and relay._env_cache.is_empty()):
		return "relay env-file cache not pinned empty (res://nivek_relay.env could be used)"
	if relay.is_enabled():
		return "relay is enabled (url and token resolved)"
	if relay._ws != null:
		return "relay created a websocket"
	if rs.settings.is_twitcher_setup():
		return "Twitch settings still complete; RSTwitcher.start() would connect"
	return ""

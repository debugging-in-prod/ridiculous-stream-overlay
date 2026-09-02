extends Window
class_name RSWinConfig

@onready var ln_device_token: LineEdit = %ln_device_token
@onready var lb_relay_status: Label = %lb_relay_status
@onready var ck_chat_notifications: CheckButton = %ck_chat_notifications
@onready var ck_names_on_screen: CheckButton = %ck_names_on_screen


func _ready() -> void:
	close_requested.connect(hide)


## Populates the controls from the saved settings. Called by RSMain.start_everything()
## rather than from _ready(): child _ready() runs before RSMain._ready(), so at that
## point RS.settings is still the in-memory default and has not been loaded from disk.
func start() -> void:
	ck_chat_notifications.set_pressed_no_signal(RS.settings.chat_notifications_enabled)
	ck_names_on_screen.set_pressed_no_signal(RS.settings.names_on_screen_enabled)
	ln_device_token.text = RS.settings.nivek_device_token
	if RS.nivek_relay:
		RS.nivek_relay.status_changed.connect(refresh_relay_status)
	refresh_relay_status()


func toggle() -> void:
	if visible:
		hide()
	else:
		refresh_relay_status()
		popup_centered()


#region Device token
func _on_btn_apply_token_pressed() -> void:
	apply_device_token()


func _on_ln_device_token_text_submitted(_new_text: String) -> void:
	apply_device_token()


## Saves the token, reconnects the relay with it, and re-points the cheer
## consumers -- enabling the relay changes what RSMain.cheer_source() returns.
func apply_device_token() -> void:
	RS.settings.nivek_device_token = ln_device_token.text.strip_edges()
	# Written now rather than on the save-on-quit path: a token the user has just
	# pasted should survive a crash, and it is the one setting they cannot retype
	# from memory.
	RS.save_settings()
	if RS.nivek_relay:
		RS.nivek_relay.restart()
	RS.rebind_cheer_source()
	refresh_relay_status()


func refresh_relay_status() -> void:
	if not is_node_ready():
		return
	var relay: RSNivekRelay = RS.nivek_relay
	if relay == null:
		lb_relay_status.text = "Relay unavailable."
		return
	match relay.token_source():
		"unset":
			lb_relay_status.text = "No device token set. Bits and overlay commands will not reach this overlay."
		"env":
			lb_relay_status.text = "Using NIVEK_DEVICE_TOKEN from the environment, which overrides this field."
		"file":
			lb_relay_status.text = "Using the token in nivek_relay.env, which overrides this field."
		_:
			lb_relay_status.text = "Connected." if relay.is_ready() else "Connecting..."
#endregion


#region Overlay toggles
func _on_ck_chat_notifications_toggled(toggled_on: bool) -> void:
	RS.settings.chat_notifications_enabled = toggled_on


func _on_ck_names_on_screen_toggled(toggled_on: bool) -> void:
	RS.settings.names_on_screen_enabled = toggled_on


func _on_btn_debug_pressed() -> void:
	RS.debug_view.visible = !RS.debug_view.visible
#endregion

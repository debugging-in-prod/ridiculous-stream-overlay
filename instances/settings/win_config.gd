extends Window
class_name RSWinConfig

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


func toggle() -> void:
	if visible:
		hide()
	else:
		popup_centered()


func _on_ck_chat_notifications_toggled(toggled_on: bool) -> void:
	RS.settings.chat_notifications_enabled = toggled_on


func _on_ck_names_on_screen_toggled(toggled_on: bool) -> void:
	RS.settings.names_on_screen_enabled = toggled_on


func _on_btn_debug_pressed() -> void:
	RS.debug_view.visible = !RS.debug_view.visible

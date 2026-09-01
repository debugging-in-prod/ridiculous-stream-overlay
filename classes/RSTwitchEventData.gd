extends RefCounted
class_name RSTwitchEventData

var type: String

var user_id: int
var username: String     # from twitch API username is "user_login"
var display_name: String # from twitch API display_name is "user_name"
var followed_at: String
var from_broadcaster_user_id: int
var from_broadcaster_username: String     # from twitch API username is "user_login"
var from_broadcaster_display_name: String # from twitch API display_name is "user_name"
var viewers: int
var user_input: String
var status: String
var reward_title: String
var reward_cost: int
var reward_prompt: String
var is_anonymous: bool
var message: String
var bits: int
var tier: int
var is_gift: bool
var power_up_id: String
var power_up_title: String
var action: String
var args: PackedStringArray
var product_sku: String


static func create_from_event_body(_type: String, body: Dictionary) -> RSTwitchEventData:
	var data := RSTwitchEventData.new()
	data.type = _type
	if body.has("user_id"): data.user_id = body.user_id as int
	if body.has("user_login"): data.username = body.user_login
	if body.has("user_name"): data.display_name = body.user_name
	match _type:
		"channel.follow":
			data.followed_at = body.followed_at
		"channel.channel_points_custom_reward_redemption.add":
			data.user_input = body.user_input
			data.status = body.status
			data.reward_title = body.reward.title
			data.reward_cost = body.reward.cost as int
			data.reward_prompt = body.reward.prompt
		"channel.raid":
			data.from_broadcaster_user_id = body.from_broadcaster_user_id as int
			data.from_broadcaster_username = body.from_broadcaster_user_login
			data.from_broadcaster_display_name = body.from_broadcaster_user_name
			data.viewers = body.viewers as int
		"channel.cheer":
			data.is_anonymous = body.is_anonymous
			data.message = body.message
			data.bits = body.bits as int
		"nivek.command":
			# Not a Twitch event type -- a chat command peanutbudderbot matched and
			# forwarded over the relay, so the overlay never parses chat itself.
			# The payload is nivek's CommandPayload {action, args, user_*}.
			data.action = body.get("action", "")
			var raw_args: Variant = body.get("args", [])
			if typeof(raw_args) == TYPE_ARRAY:
				for a in raw_args:
					data.args.append(str(a))
		"channel.custom_power_up_redemption.add":
			# Fed from the nivek relay's flat PowerUpPayload, not a raw Twitch body.
			data.power_up_id = body.get("power_up_id", "")
			data.power_up_title = body.get("power_up_title", "")
			data.bits = int(body.get("bits", 0))
		"extension.bits":
			# Fed from the nivek relay's flat ExtensionPayload. Dispatch on
			# product_sku, the analogue of power_up_title / reward_title.
			data.product_sku = body.get("product_sku", "")
			data.bits = int(body.get("bits", 0))
		"channel.subscribe":
			data.tier = body.tier as int
			data.is_gift = body.is_gift
	return data

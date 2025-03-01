
extends Node

signal _www_chat_submitted
const _WWW_CHAT_SUBMITTED = "_www_chat_submitted"

const SAVE_FILE_PATH = "user://webwhisper_settings.sav"

const PLAYER_HUD_PATH = "/root/playerhud"
const LINE_EDIT_PATH = "main/in_game/gamechat/LineEdit"
const ENTITIES_PATH = "Viewport/main/entities"

const COMMAND_REGEX = "^\\/(\\w+)(?:\\s(.*))?$"
const COLOR_REGEX = ".*?\\[.*?color=#([0-9a-fA-F]*).*?\\](.*?)\\[.*?\\/color.*?\\].*?"

const DEFAULT_CHAT_COLOR = "FFEED5"

enum CACHE {
	PREV_TARGET_ID_STACK,
	USER_COLORS,
	LAST_SENDER
}

onready var debug_arr = []

onready var cache: Dictionary = {
	CACHE.PREV_TARGET_ID_STACK: [],
	CACHE.USER_COLORS: {},
	CACHE.LAST_SENDER: {}
}

# Suggestions generator/manager
onready var CURRENT_SUGG: Suggestions = Suggestions.new(cache, debug_arr)

# refrences to scene nodes
onready var player_hud: CanvasLayer = null
onready var line_edit: LineEdit = null
onready var entities: Node = null

# keeping regex compiled to speed it up
onready var command_regex: RegEx = RegEx.new()
onready var color_regex: RegEx = RegEx.new()

# settings
onready var SETTINGS: Settings = Settings.new(SAVE_FILE_PATH)

# private "static" variables used by specific functions
onready var _message_count_tracker_copy: Dictionary = {} # _message_flush() & get_last_sender_id()
onready var _update_command = Suggestions.OP.OFF # used by update_sugg(), _update_sugg_after_frame()
onready var _lobby_members_cache: Array = [] # used by lobby_members()
onready var _lobby_members_timeout = -10000  # used by lobby_members()


# -- classes -- #

# This probably shouldn't all be in one file but oh well!

class Settings extends Node:
	const SAVE_FILE_REGEX = "^\\s*([^\\s=]+)\\s*=\\s*\"([^\"]*)\"(.*)$"
	# %u is either your username or their username (depending on the context)
	# %m is the message you sent
	# these first 3 you can't change, they are used to tell if a message from another
	# client is a whisper
	const SEND_WHISPER_PREFIX = "<whisper from "
	const SEND_WHISPER_INFIX = ">: "
	const SEND_WHISPER_FORMAT = SEND_WHISPER_PREFIX + "%u" + SEND_WHISPER_INFIX + "%m"
	
	const DEFAULT_WHISPER_COLOR = "DD7C8AB1"
	const DEFAULT_RECEIPT_FORMAT = "<to %u>: %m"
	const DEFAULT_RECEIVE_FORMAT = SEND_WHISPER_FORMAT
	
	var whisper_color = DEFAULT_WHISPER_COLOR
	var receipt_format = DEFAULT_RECEIPT_FORMAT
	var receive_format = DEFAULT_RECEIVE_FORMAT
	var is_whisper_off = false
	
	var _www_saving = false
	var _save_file_path
	
	func _init(save_file_path):
		self._save_file_path = save_file_path
	
	func save():
		if _www_saving:
			return
		_www_saving = true
		call_deferred("_save_to_file")
	
	func _save_to_file():
		yield(get_tree().create_timer(0.25), "timeout")
		var new_save = ("""# WebWhisper options:

# /whispercolor must be a 6 digit hex RGB code or an 8 digit hex ARGB code.
# Default is \"""" + DEFAULT_WHISPER_COLOR + """"

whispercolor = "{whispercolor}"


# /sendwhisperformat will print in chat when you send a whisper, it should have a %u where 
# you want your username, and a %m where you want the message you sent them, but it technically
# doesn't need either, set it as = "" and you won't see any receipt.
# Default is \"""" + DEFAULT_RECEIPT_FORMAT + """"

sendwhisperformat = "{sendwhisperformat}"


# /getwhisperformat is the format you receive whispers in. It must have a %u where you want their 
# username, and a %m where you want their message.
# Default is \"""" + DEFAULT_RECEIVE_FORMAT + """"

getwhisperformat = "{getwhisperformat}"


# /whisperoff or /whisperon setting, must be = "True" to turn off whispers.
# Default is "False"

whisperoff = "{whisperoff}"
""").format({
		"whispercolor": whisper_color, 
		"sendwhisperformat": receipt_format,  
		"getwhisperformat": receive_format,  
		"whisperoff": str(is_whisper_off)  
		})
		
		print("Saving WebWhisper settings")
		var save = File.new()
		if save.open(_save_file_path, File.WRITE) == OK:
			save.store_string(new_save) 
			save.close()
			print("WebWhisper settings Save successful!")
		else:
			print("WebWhisper settings failed to open file.")
		
		_www_saving = false
	
	func load_save():
		var save_file_regex = RegEx.new()
		save_file_regex.compile(SAVE_FILE_REGEX)
		for i in range(3):
			yield(get_tree().create_timer(6), "timeout") # this doesn't need to run right on startup
			var success = _try_load_save(save_file_regex)
			while not success is bool:
				yield(get_tree().create_timer(0.2), "timeout")
			if success:
				break
	
	func _try_load_save(save_file_regex) -> bool:
		while _www_saving:
			yield(get_tree().create_timer(0.2), "timeout")
		
		var save = File.new()
		if not save.file_exists(_save_file_path) or save.open(_save_file_path, File.READ) != OK:
			print("WebWhisper settings failed to find file.")
			return false
			
		var new_settings = {}
		var code = ""
		while not save.eof_reached():
			var line = save.get_line()
			line = line.substr(0,line.find("#"))
			var result = save_file_regex.search(line)
			if result == null:
				continue
			new_settings[result.get_string(1)] = result.get_string(2) 
		save.close()
		
		var valid_settings = true
		var whisper_color = new_settings.get("whispercolor", null)
		if not (whisper_color != null and set_whisper_color(whisper_color, false)[0]):
			valid_settings = false
			print("Invalid WebWhisper save: whispercolor setting")
		var receipt_format = new_settings.get("sendwhisperformat", null)
		if not (receipt_format != null and set_receipt_format(receipt_format, false)[0]):
			valid_settings = false
			print("Invalid WebWhisper save: sendwhisperformat setting")
		var receive_format = new_settings.get("getwhisperformat", null)
		if not (receive_format != null and set_receive_format(receive_format, false)[0]):
			valid_settings = false
			print("Invalid WebWhisper save: getwhisperformat setting")
		var is_whisper_off = new_settings.get("whisperoff", null)
		set_is_whisper_off(is_whisper_off, false)
		if is_whisper_off == null:
			valid_settings = false
			print("Invalid WebWhisper save: whisperoff setting")
		
		print("WebWhisper settings loaded successfully!")
		if not valid_settings:
			print("Invalid save data, updating save")
			call_deferred("save")
		return true
	
	func set_whisper_color(new_color: String, do_save: bool = true) -> Array:
		var return_arr = [false, 
			("whispercolor must be a 6 or 8 digit RGB or ARGB hex code"
				+ ", or type just \"/whispercolor\" to reset to default")
		]
		new_color = new_color.to_upper().strip_edges().replace("#","")
		if new_color.empty():
			return_arr[0] = true
			return_arr[1] = ("whispercolor reset from [color=#" + self.whisper_color + "]" 
					+ self.whisper_color + "[/color] to [color=#" + DEFAULT_WHISPER_COLOR + "]Default[/color]")
			self.whisper_color = DEFAULT_WHISPER_COLOR
		else:
			if new_color.length() == 6:
				new_color = "FF" + new_color
			if new_color.length() == 8 and new_color.is_valid_hex_number():
				return_arr[0] = true
				return_arr[1] = ("whispercolor changed from [color=#" + self.whisper_color + "]" 
					+ self.whisper_color + "[/color] to [color=#" + new_color + "]" 
					+ new_color + "[/color]")
				self.whisper_color = new_color
		if return_arr[0] and do_save:
			self.save()
		return return_arr
	
	func set_receipt_format(new_format: String, do_save: bool = true) -> Array:
		var return_arr = [true, "Set sendwhisper format to \""]
		if new_format.replace(" ", "").empty():
			if self.receipt_format == DEFAULT_RECEIPT_FORMAT:
				self.receipt_format = ""
				return_arr[1] = "Turned off whisper receipts."
			else:
				self.receipt_format = DEFAULT_RECEIPT_FORMAT
				return_arr[1] = "Reset sendwhisper format to \"" + DEFAULT_RECEIPT_FORMAT + "\""
		else:
			self.receipt_format = new_format
			return_arr[1] += new_format + "\""
		if do_save:
			self.save()
		return return_arr
	
	func set_receive_format(new_format: String, do_save: bool = true) -> Array:
		var return_arr = [false, ("Must contain a \"%u\" for sender name "
				+ "and \"%m\" for message, e.g. default is:\n" + DEFAULT_RECEIVE_FORMAT)]
		if new_format.strip_edges().empty():
			return_arr[0] = true
			return_arr[1] = "Reset getwhisper format to \"" + DEFAULT_RECEIVE_FORMAT + "\""
			self.receive_format = DEFAULT_RECEIVE_FORMAT
		elif new_format.find("%u") != -1 and new_format.find("%m") != -1:
			return_arr[0] = true
			return_arr[1] = "Set getwhisper format to \"" + new_format + "\""
			self.receive_format = new_format
		
		if return_arr[0] and do_save:
			self.save()
		return return_arr
	
	func set_is_whisper_off(new_whisper_off, do_save: bool = true) -> bool:
		if new_whisper_off is String:
			if new_whisper_off == "True":
				new_whisper_off = true
			else:
				new_whisper_off = false
		if new_whisper_off is bool:
			var changed = self.is_whisper_off != new_whisper_off
			self.is_whisper_off = new_whisper_off
			if changed and do_save:
				self.save()
			return changed
		return false
	
	func reset():
		self.set_whisper_color(DEFAULT_WHISPER_COLOR, false)
		self.set_receipt_format(DEFAULT_RECEIPT_FORMAT, false)
		self.set_receive_format(DEFAULT_RECEIVE_FORMAT, false)
		self.set_is_whisper_off(false, false)
		self.save()


# preserves the state of the text entry field for chat, including cursor position and
# highlighted text. Has functions to compare and restore states.
class LineEditState:
	var line_edit: LineEdit
	var text: String
	var caret_position: int
	var selection_begin: int = -1
	var selection_end: int = -1
	
	func _init(line_edit: LineEdit):
		self.line_edit = line_edit
		self.text = line_edit.text
		self.caret_position = line_edit.caret_position
		if not line_edit.has_selection():
			return
		
		var sel_begin = line_edit.get("selection_begin")
		var sel_end = line_edit.get("selection_end")
		if sel_begin != null and sel_end != null:
			self.selection_begin = sel_begin
			self.selection_end = sel_end
	
	func equals(other: LineEditState):
		if (self.text == other.text 
				and self.caret_position == other.caret_position
				and self.selection_begin == other.selection_begin
				and self.selection_end == other.selection_end):
			return true
		return false
	
	func restore():
		line_edit.text = text
		line_edit.caret_position = caret_position
		line_edit.deselect()
		if selection_begin != -1:
			line_edit.select(selection_begin, selection_end)

# generates the possible autocomplete options for a given LineEditState, stores all of those
# options, and has functions to render/cycle between them, and check if the user has changed the
# LineEdit in ways that mean they accepted the suggestion.
# Suggestions.is_valid() is true when the user hasn't changed the LineEdit
class Suggestions extends Node:
	enum OP {
		OFF,
		REMOVE,
		UPDATE,
		REQUEST,
		UP,
		DOWN
	}
	
	var debug
	var valid: bool = false
	var exhausted: String = ""
	var users_index: int = 0
	
	var cache: Dictionary
	var line_edit: LineEdit
	var base_state: LineEditState
	var valid_state: LineEditState
	var typed_name: String
	var typed_name_begin: int
	var users: Array
	
	func _init(cache: Dictionary, debug = []):
		self.debug = debug
		#debug.append("Node created-----------------\n")
		self.cache = cache
	
	#func _enter_tree():
		#debug.append("Node entered tree-----------------\n")
	
	func create(base_state: LineEditState, pool: Array = []): 
		self.valid = false
		self.base_state = base_state
		self.line_edit = base_state.line_edit
		
		if line_edit.has_selection():
			return self.mark_invalid() # fail: did not search, somethings going on with selection
		
		var caret = base_state.caret_position
		var before_caret = base_state.text.substr(0, caret)
		
		if before_caret.begins_with("/w "):
			self.typed_name = before_caret.substr(3)
			caret = caret - 3
			self.typed_name_begin = 3
		elif before_caret.begins_with("/whisper "):
			self.typed_name = before_caret.substr(9)
			caret = caret - 9
			self.typed_name_begin = 9
		else: # fail: did not search, might have "/whis" typed for example
			if not before_caret.empty():
				before_caret = before_caret[0] if before_caret[0] != "/" else ""
			return self.mark_invalid(before_caret)
		
		self.exhausted = before_caret
		
		self.users = find_potential_usernames(self.typed_name, pool)
		
		if self.users.empty(): # fail: exhausted suggestions is NOT empty
			return  # return with exhaust containing line_edit.text up until the caret
		
		# success: exhausted suggestions before_caret is NOT empty
		self.valid = true
		self.render()
	
	# TODO this still needs to change the capitalization of already typed characters to prevent
	# cases of people with the same username but different capitalization causing conflict
	# TODO increase the allowed number of typed characters in line_edit proportional to the number
	# of typed characters when a suggestion is accepted. Will have to reset this somehow
	# Lets try to have a more explicit reject and accept behavior by intercepting every possible 
	# user action and categorizing them as accept/reject/neither (lol how?)
	func render(step: int = 0):
		self.users_index = (users_index + step + users.size()) % users.size()
		
		line_edit.text = base_state.text.substr(0,typed_name_begin)
		var sugg_name = users[users_index]["steam_name"]
		line_edit.text += sugg_name
		
		var caret = base_state.caret_position
		line_edit.text += base_state.text.substr(caret)
		
		line_edit.deselect()
		line_edit.select(caret, caret + (sugg_name.length() - typed_name.length()))
		line_edit.caret_position = caret
		self.valid_state = LineEditState.new(line_edit)
	
	func remove() -> bool:
		if valid and valid_state.text == line_edit.text:
			base_state.restore()
			self.mark_invalid("")
			return true
		self.mark_invalid()
		return false
	
	func mark_invalid(reset_exhausted = null):
		self.valid = false
		if reset_exhausted is String:
			self.exhausted = reset_exhausted
	
	func is_valid(current_state: LineEditState) -> bool:
		if !valid:
			return false
		if not valid_state.equals(current_state):
			self.mark_invalid("")
			return false
		return true
	
	
	func find_potential_usernames(username: String, pool: Array) -> Array:
		username = username.to_lower()
		var results = {}
		var id
		var pot_name
		for member in pool:
			id = member.get("steam_id", null)
			if id == null or id == Network.STEAM_ID:
				continue
			
			pot_name = member.get("steam_name", "")
			if pot_name.empty():
				continue
			
			if pot_name.to_lower().begins_with(username):
				results[id] = pot_name
		
		return sort_pot_targets(results)
	
	func sort_pot_targets(targets: Dictionary) -> Array:
		var sorted = []
		for id in targets.keys():
			sorted.append({"steam_id": id, "steam_name": targets[id]})
		
		sorted.sort_custom(self, "compare_by_steam_name")
		
		for prev_target_id in cache[CACHE.PREV_TARGET_ID_STACK]:
			if prev_target_id in targets:
				for index in range(sorted.size()):
					if sorted[index]["steam_id"] == prev_target_id:
						var dict = sorted[index]
						sorted.remove(index)
						sorted.append(dict)
						break
		sorted.invert()
		return sorted
	
	func compare_by_steam_name(a, b):
		return a["steam_name"].to_lower() > b["steam_name"].to_lower()
	
	# do_check() is used when a suggestion is invalid, it checks if the line_edit is in
	# an acceptable state to try to make another batch of suggestions.
	# exhausted is used to indicate what text a failed suggestion was exhausted on, so that no more
	# checks will be attempted on the same string until the LineEdit doesn't start with that string
	func do_check() -> bool:
		#debug.append("do_check\n")
		if (not exhausted.empty() and line_edit.text.begins_with(exhausted)) or valid:
			#debug.append("return false 1\n")
			return false
		
		if line_edit.text.begins_with("/r"):
			if line_edit.text.begins_with("/r ") or line_edit.text.begins_with("/reply "):
				line_edit.text = "/w "
				if not cache[CACHE.LAST_SENDER].get("steam_name", "").empty():
					line_edit.text = line_edit.text + cache[CACHE.LAST_SENDER]["steam_name"] + " "
				line_edit.caret_position = line_edit.text.length()
				self.mark_invalid(line_edit.text)
				#debug.append("return false 2\n")
				return false
		
		if (line_edit.caret_position != line_edit.text.length()
				and line_edit.text[line_edit.caret_position] != " "):
			#debug.append("return false 3\n")
			return false
		
		#debug.append("return true\n")
		return true
	
	#func _notification(what):
		#if what == NOTIFICATION_PREDELETE:
			# This runs just before the node is deleted/freed
			#on_node_deleted()
		#elif what == NOTIFICATION_UNPARENTED:
			# This runs when the node is removed from the scene tree
			#on_node_removed_from_tree()

	#func on_node_deleted():
		#debug.append("Node is about to be deleted/freed------------")

	#func on_node_removed_from_tree():
		#debug.append("Node has been removed from the scene tree------------")
	
	
	# debugging tool
	static func print_member_variables(obj: Object):
		# Get the list of properties for the object
		var properties = obj.get_property_list()
		
		# Iterate through the properties
		for prop in properties:
			var varname = prop["name"]
			var type = prop["type"]
			
			# Skip built-in properties (like script, metadata, etc.)
			if varname in ["script", "metadata"]:
				continue
			
			# Check if the property is a member variable (has a valid type)
			if type != TYPE_NIL:
				var value = obj.get(varname)
				print("Variable: %s, Type: %s, Value: %s" % [str(varname), str(type), str(value)])



#  -- virtual/engine functions -- #


func _ready():
	# checks if the message is a whisper any time chat updates
	if not self.is_connected("_chat_update", self, "_chat_update"):
		if Network.connect("_chat_update", self, "_chat_update") != OK:
			push_error("WWW _chat_update failed to connect")
	
	# signal is emited by _input() whenever enter is pressed while chat is open
	if not self.is_connected(_WWW_CHAT_SUBMITTED, self, _WWW_CHAT_SUBMITTED):
		if self.connect(_WWW_CHAT_SUBMITTED, self, _WWW_CHAT_SUBMITTED) != OK:
			push_error("WWW " + _WWW_CHAT_SUBMITTED + " failed to connect")

	var message_count_timer
	for mct in Network.get_children():
		if mct is Timer and mct.is_connected("timeout", Network, "_message_flush"):
			message_count_timer = mct
			break
	if not message_count_timer.is_connected("timeout", self, "_message_flush"):
		if message_count_timer.connect("timeout", self, "_message_flush") != OK:
			push_error("WWW message_count_timer failed to connect")
	
	command_regex.compile(COMMAND_REGEX)
	
	color_regex.compile(COLOR_REGEX)
	
	#add as child to tree to enable the use of timers
	add_child(CURRENT_SUGG)
	add_child(SETTINGS)
	SETTINGS.load_save()
	
	#debug(debug_arr)


# debugging 
func debug(debug_arr):
	while true:
		yield(get_tree().create_timer(5), "timeout")
		print(str(debug_arr))
		var is_sugg = is_instance_valid(CURRENT_SUGG)
		print("sugg valid: " + str(is_sugg))
		if is_sugg:
			print("sugg in tree: " + str(CURRENT_SUGG.is_inside_tree()))


# tried to make this as efficent as possible to reduce overhead.
# todo: maybe create a listener node that is removed from the tree until chat is opened?
func _input(event: InputEvent):
	if event is InputEventKey: # most common case, not a keyevent
		if not event.pressed: # second most common, not key down
			return
		
		if not is_instance_valid(line_edit) and not is_line_edit_loaded():
			return
		
		if not player_hud.get("using_chat"):
			if Input.is_action_just_pressed("chat_enter"):
				if player_hud.menu == player_hud.MENUS.DEFAULT:
					update_sugg()
			return # third most common, not using chat. returns after 4-6 checks
		
		# chat is open:
		
		# is chat being submitted?
		if (Input.is_action_just_pressed("chat_enter") 
				and player_hud.menu == player_hud.MENUS.DEFAULT):
			emit_signal(_WWW_CHAT_SUBMITTED)
			return update_sugg(Suggestions.OP.REMOVE)
		
		# if its a char input:
		if event.unicode > 0:
			update_sugg(Suggestions.OP.REMOVE)
			return update_sugg(Suggestions.OP.REQUEST)
		
		# we dont mess with modifier keys
		if event.shift or event.alt or event.control or event.meta or event.command:
			return update_sugg()
		
		# fix broken behavior
		if Input.is_action_just_pressed("menu_open"):
			Input.action_release("menu_open")
		if event.scancode == KEY_TAB:
			get_tree().set_input_as_handled()
		if not line_edit.has_focus():
			return update_sugg()
		
		# autocomplete suggestion handling
		match event.scancode:
			KEY_DOWN:
				line_edit.accept_event()
				return update_sugg(Suggestions.OP.UP)
			
			KEY_UP:
				line_edit.accept_event()
				return update_sugg(Suggestions.OP.DOWN)
			
			KEY_LEFT, KEY_DELETE, KEY_BACKSPACE:
				if update_sugg(Suggestions.OP.REMOVE):
					line_edit.accept_event()
				
			KEY_RIGHT:
				if line_edit.has_selection() or line_edit.caret_position == line_edit.text.length():
					return update_sugg(Suggestions.OP.REQUEST)
			KEY_TAB:
				if line_edit.has_selection():
					send_key(KEY_RIGHT)
					return
				return update_sugg(Suggestions.OP.REQUEST)
		
		return update_sugg()
	
	# check if hud buttons were clicked:
	if event is InputEventMouseButton and not event.pressed:
		return update_sugg()



# -- signal functions -- #


func _www_chat_submitted():
	var result = command_regex.search(line_edit.text)
	if result == null:
		return
	
	var command = result.get_string(1).to_lower()
	var body = result.get_string(2)
	
	match command: # "r" or "reply" aren't listed here because they activate before you hit enter
		"whisper", "w":
			send_whisper(body)
		
		"whispercolor":
			change_whisper_color(body)
		
		"sendwhisperformat":
			change_whisper_receipt_format(body)
		
		"getwhisperformat":
			change_whisper_receive_format(body)
		
		"whisperoff", "whispersoff", "woff":
			change_is_whisper_off(true)
		
		"whisperon", "whisperson", "won":
			change_is_whisper_off(false)
		
		"whisperhelp", "whisperh", "wh", "whelp", "w?", "whisper?":
			help()
		
		"whisperreset", "wreset":
			reset_settings()
		
		_: # if none of our commands run, return before editing the LineEdit
			return
	
	# if a non-defaut case ran, delete the message
	line_edit.text = ""



# find the most recent message and sender, cache the color associated with the sender, if it was a 
# recieved whisper: color the text and cache the sender as prev whisper sender.
func _chat_update():
	if not is_player_hud_loaded():
		return

	var this_collection = []
	if not player_hud.chat_local and not Network.GAMECHAT_COLLECTIONS.empty():
		this_collection = Network.GAMECHAT_COLLECTIONS
	elif not Network.LOCAL_GAMECHAT_COLLECTIONS.empty():
		this_collection = Network.LOCAL_GAMECHAT_COLLECTIONS
	
	var this_message = this_collection[-1]
	
	var sender_id = get_last_sender_id()
	
	if sender_id == null:
		return
	
	var username = get_steam_name(sender_id)
	
	cache_name_color(this_message.strip_edges(), sender_id, username)
	
	if not this_message.strip_edges().begins_with(SETTINGS.SEND_WHISPER_PREFIX):
		return
	
	# it was a whisper:
	cache[CACHE.LAST_SENDER]["steam_id"] = sender_id
	cache[CACHE.LAST_SENDER]["steam_name"] = username
	if SETTINGS.is_whisper_off:
		this_collection[-1] = ""
	else:
		this_collection[-1] = format_received_whisper(this_message)
	
	Network.GAMECHAT = ""
	for msg in Network.GAMECHAT_COLLECTIONS:
		Network.GAMECHAT = Network.GAMECHAT + msg

# helper function for _chat_update()
func format_received_whisper(whisper: String):
	var i = whisper.find(Settings.SEND_WHISPER_PREFIX) + Settings.SEND_WHISPER_PREFIX.length()
	var j = whisper.find_last("[/color]") + 8
	var username = whisper.substr(i,j)
	var message = whisper.substr(j  + Settings.SEND_WHISPER_INFIX.length())
	whisper = replace_escape(SETTINGS.receive_format, username, null, message)
	return bbc_colour_text(whisper, SETTINGS.whisper_color)

# enables get_last_sender_id() to see which lobby member sent the last packet
func _message_flush():
	_message_count_tracker_copy = Network.MESSAGE_COUNT_TRACKER.duplicate()


# -- command functions -- #

# see if the string starts with a lobby member's username
# and return their steam name, id, and the rest of the message
func parse_user_from_command(msg: String, pool: Array = []) -> Dictionary:
	if pool.empty():
		pool = lobby_members()
	msg = msg.strip_edges()
	
	var targets = {}
	var result = {"message" : "", "err_msg": "", "steam_id": null, "steam_name": null}
	var priority_found = false
	var username = ""
	
	if msg.empty():
		result["err_msg"] = "No username or message given."
		return result
	
	var msg_cpy = msg.left(34)
	if msg_cpy[0] == "[":
		var end_bracket = msg_cpy.find("]")
		while msg_cpy.find("]", end_bracket + 1) != -1:
			end_bracket = msg_cpy.find("]", end_bracket + 1)
		if end_bracket != -1:
			username = msg_cpy.substr(1, end_bracket - 1).strip_edges()
			priority_found = str_find_username(
					targets, username, msg.substr(end_bracket +1).strip_edges(), pool)
	
	if not priority_found:
		msg_cpy = msg.left(32).to_lower()
		var index = msg_cpy.find(" ")
		
		
		if index == -1 and not msg_cpy.empty():
			index = msg_cpy.length()
		
		while index != -1:
			username = msg_cpy.substr(0, index)
			
			str_find_username(targets, username, msg.substr(index).strip_edges(), pool)
			
			if index == msg_cpy.length():
				break
			
			index = msg_cpy.find(" ", index + 1)
			if index == -1:
				index = msg_cpy.length()
	
	if targets.empty():
		result["err_msg"] = "No users found."
		return result
	
	if targets.size() > 1:
		for key in targets.keys(): #TODO test this
			if priority_found:
				if not targets[key]["steam_name"] == username:
					targets.erase(key)
			elif not msg.begins_with(targets[key]["steam_name"]):
				targets.erase(key)
		if targets.size() > 1:
			result["err_msg"] = ("Multiple possible users found. Place brackets around "
					+ "the username and pay attention to capitalization.")
			return result
	
	result.merge(targets[targets.keys()[0]], true)
	return result


# helper function for parse command; find an exact non case sensitive username match for a string
func str_find_username(results: Dictionary, 
					   username: String, 
					   message: String = "", 
					   pool: Array = []) -> bool:
	var found = false
	for member in pool:
		var mem_name = member.get("steam_name", "")
		if mem_name.empty():
			continue
		if mem_name.to_lower() == username and username != "":
			found = true
			results[member["steam_id"]] = member.duplicate()
			results[member["steam_id"]]["message"] = message
	return found


# send a whisper
func send_whisper(msg: String):
	var whisper = parse_user_from_command(msg)
	var message = whisper.get("message", "")
	var err_msg = whisper.get("err_msg", "")
	
	if not err_msg.empty():
		client_message(err_msg, SETTINGS.whisper_color)
		help(false)
		return
	
	if message.empty():
		client_message("Type a message after the username.", SETTINGS.whisper_color)
		return
	
	var target = whisper.get("steam_name", null)
	var target_id = whisper.get("steam_id", null)
	
	var final_message = (SETTINGS.SEND_WHISPER_FORMAT).replace("%m", message)
	var message_origin = Vector3(0,0,0)
	
	var sender_color = get_player_chat_color()
	var target_color = get_player_chat_color(target_id)
	
	var packet = {
		"type": "message", 
		"message": final_message, 
		"color": sender_color, 
		"local": false, 
		"position": message_origin, 
		"zone": Network.MESSAGE_ZONE, 
		"zone_owner": PlayerData.player_saved_zone_owner
	}
	Network._send_P2P_Packet(packet, str(target_id), 2, Network.CHANNELS.GAME_STATE)
	
	# receipt:
	if not SETTINGS.receipt_format.strip_edges().empty():
		client_message(
				SETTINGS.receipt_format, SETTINGS.whisper_color, target, target_color, message)
	
	# add target to recent target stack
	cache_whisper_target(target_id)

func help(full_menu: bool = true):
	if full_menu:
		client_message(""""/w <username> <whisper message :3>"
 - (send whisper)
 - optional brackets around [username]
"/r"
 - (send reply)
 - autofills name from last sender
"/whisperon" or "/whisperoff"
 - (toggle getting whispers on or off)
"/whispercolor <ARGB hex>"
 - (change whisper color)""", SETTINGS.whisper_color)
		client_message(""""/getwhisperformat"
 - (change format of received whispers) 
 - type %u where the username goes
 - type %m where the message goes
"/sendwhisperformat"
 - (change format of sent whispers)
 - optional: use %u and %m
 - make it empty to turn of receipts""", SETTINGS.whisper_color)
	else:
		client_message("Type \"/whisperhelp\" or \"/wh\" for help.", SETTINGS.whisper_color)


# change the color of the whisper text
func change_whisper_color(color: String):
	client_message(SETTINGS.set_whisper_color(color)[1], SETTINGS.whisper_color)

func change_whisper_receive_format(format: String):
	client_message(SETTINGS.set_receive_format(format)[1], SETTINGS.whisper_color)

func change_whisper_receipt_format(format: String):
	client_message(SETTINGS.set_receipt_format(format)[1], SETTINGS.whisper_color)

func change_is_whisper_off(is_whisper_off: bool):
	var changed = SETTINGS.set_is_whisper_off(is_whisper_off)
	if is_whisper_off:
		if changed:
			client_message("Turned off receiving whispers, use /whisperon to turn them back on.", SETTINGS.whisper_color)
		else:
			client_message("Whispers already off, use /whisperon to turn them back on.", SETTINGS.whisper_color)
	else:
		if changed:
			client_message("Enabled receiving whispers, use /whisperoff to disable them.", SETTINGS.whisper_color)
		else:
			client_message("Whispers already on, use /whisperoff to disable receiving whispers.", SETTINGS.whisper_color)

func reset_settings():
	SETTINGS.reset()
	client_message("Whisper settings reset!", SETTINGS.whisper_color)

# -- suggestion functions -- #

# this is called by _input() and does call_deferred on update_sugg_after_frame(), this runs before
# the game processes the input, and update_sugg_after_frame() runs after.
# this way we can process inputs by intercepting them before the game processes them, or by seeing
# how they affect the LineEdit.
func update_sugg(command = Suggestions.OP.UPDATE) -> bool:
	if _update_command == Suggestions.OP.OFF:
		call_deferred("_update_sugg_after_frame")
	
	if command > _update_command:
		_update_command = command
	
	if command == Suggestions.OP.REMOVE:
		return CURRENT_SUGG.remove()
	return false

# runs on idle frame, so after the input has affected the line_edit
func _update_sugg_after_frame():
	var command = _update_command
	_update_command = Suggestions.OP.OFF
	
	if not is_line_edit_loaded():
		CURRENT_SUGG.mark_invalid("")
		return
	
	if (not player_hud.get("using_chat") or command == Suggestions.OP.OFF
			or command == Suggestions.OP.REMOVE):

		CURRENT_SUGG.mark_invalid("")
		return
	var current_state = LineEditState.new(line_edit)
	if CURRENT_SUGG.is_valid(current_state):
		if command <= Suggestions.OP.REQUEST:
			return
		match command:
			Suggestions.OP.UP:
				CURRENT_SUGG.render(-1)
			
			Suggestions.OP.DOWN:
				CURRENT_SUGG.render(1)
		
	elif command >= Suggestions.OP.REQUEST and CURRENT_SUGG.do_check():
		CURRENT_SUGG.create(current_state, lobby_members())



# -- caching functions -- #

func cache_whisper_target(steam_id: int):
	var prev_targets = cache[CACHE.PREV_TARGET_ID_STACK]
	for i in range(prev_targets.size()):
		if prev_targets[i] == steam_id:
			prev_targets.remove(i)
			break
	prev_targets.append(steam_id)
	if prev_targets.size() > 100:
		cache[CACHE.PREV_TARGET_ID_STACK] = prev_targets.slice(prev_targets.size() / 2)

# cache username colors from messages we recieve
func cache_name_color(msg: String, steam_id: int, username: String):
	var result = color_regex.search(msg)
	if result == null:
		return
	
	var color = result.get_string(1).strip_edges()
	if color == "":
		return
	
	if username.to_lower() != result.get_string(2).strip_edges().to_lower():
		return
	
	cache[CACHE.USER_COLORS][steam_id] = color



# -- util functions -- #


# functions to make sure things are loaded and updated before we use them:

func is_player_hud_loaded() -> bool:
	if is_instance_valid(player_hud):
		return true
	player_hud = get_node_or_null(PLAYER_HUD_PATH)
	if player_hud != null:
		return true
	return false

func is_line_edit_loaded() -> bool:
	if not is_player_hud_loaded():
		return false
	if is_instance_valid(line_edit):
		return true
	line_edit = player_hud.get_node_or_null(LINE_EDIT_PATH)
	if line_edit != null:
		CURRENT_SUGG.line_edit = line_edit
		return true
	return false

func is_entities_loaded() -> bool:
	if is_instance_valid(entities):
		return true
	entities = get_tree().current_scene.get_node_or_null(ENTITIES_PATH)
	if entities != null:
		return true
	return false

# acts as a wrapper around Network.LOBBY_MEMBERS, with the intent of preventing the no-name 
# bug from stopping whispers from working
func lobby_members() -> Array:
	var time = OS.get_ticks_msec()
	if time - _lobby_members_timeout < 10000:
		return _lobby_members_cache
	_lobby_members_timeout = time
	
	for network_entry in Network.LOBBY_MEMBERS:
		if network_entry.get("steam_name", "").empty() and network_entry.get("steam_id", 0) > 0:
			network_entry["steam_name"] = Steam.getFriendPersonaName(network_entry["steam_id"])
	_lobby_members_cache = []
	for network_entry in Network.LOBBY_MEMBERS:
		if not network_entry.get("steam_name", "").empty():
			_lobby_members_cache.append(network_entry)
	
	return _lobby_members_cache

func get_steam_name(steam_id: int = Network.STEAM_ID, pool = null) -> String:
	if pool == null:
		pool = lobby_members()
	for member in pool:
		if int(member.get("steam_id", -1)) == steam_id:
			return member.get("steam_name", "")
	return ""


# general util functions:

# send a key as if it was pressed, used to make tab behave like right arrow when there
# is an active suggestion
func send_key(scancode):
	var event = InputEventKey.new()
	event.scancode = scancode
	event.pressed = true
	Input.parse_input_event(event)

# a series of util functions to allow colored messages to appear client side 
func client_message(text: String,
					text_color = null,
					replace_name = null,
					name_color = null,
					replace_message = null,
					message_color = null,
					sender_id = Network.STEAM_ID,
					local: bool = false,
					use_safe_receive = null):
	text = replace_escape(text, replace_name, name_color, replace_message, message_color)
	text = bbc_colour_text(text, text_color)
	
	if use_safe_receive == false or (text.find("[") != -1 and use_safe_receive != true):
		while not text.empty():
			var chunk = text.left(512)
			text = text.substr(chunk.length())
			Network._update_chat(chunk, local)
	else:
		name_color = name_color if name_color != null else DEFAULT_CHAT_COLOR
		Network._recieve_safe_message(sender_id, name_color, text, local)

# helper function for client_message, also used to color recieved whispers.
# change the bbc color the text that doesnt already have a color code
# can also be used to validate that each color code has a corresponding [/color]
func bbc_colour_text(text: String, color = null):
	var uncolored = text
	while uncolored.find("[color=#") != -1:
		var i1 = uncolored.find("[color=#")
		var i2 = uncolored.find("[/color]")
		if i2 == -1:
			uncolored += "[/color]"
			text += "[/color]" # found a color code without a [/color], so the 
			continue           # og text needs an extra [/color]!
		uncolored = uncolored.substr(0,i1) + uncolored.substr(i2+8)
	
	if uncolored.strip_edges().empty() or color == null:
		return text
	
	return "[color=#" + str(color) + "]" + text + "[/color]"


# helper function for client_message
# Replace %u with a username and %m with a message, with color codes around if given
func replace_escape(text: String, 
					username = null,
					username_color = null,
					message = null,
					message_color = null) -> String:
	if username is String:
		if username_color is String:
			username = "[color=#" + username_color + "]" + username + "[/color]"
		text = text.replace("%u", username)
	if message is String:
		if message_color is String:
			message = "[color=#" + message_color + "]" + message + "[/color]"
		text = text.replace("%m", message)
	return text

# find a player's username color, for use in the whisper receipt.
# 	We cache the colors that are sent to us in chat messages and 
# prefer to use those, for the case that people have mods installed that make their chat name color
# different from their pcolor, or in the case that they have fur color mods that we dont have
# downloaded, we won't be able to load up the file if we dont have the mod installed.
# 	However, if we send a whisper to someone in our lobby BEFORE they send any messages, there will 
# be nothing in the color cache, so we look at their player cosmetics and use their primary color
# this works only if we have the file for that pcolor, and uses ffeed5 as a fallback. If we have 
# the same mod installed (assuming it works like Lure) this should work.
# There is a slight hicup in the case that they change their cosmetics and we whisper them before 
# they send a new message, but I think its more important to prioritize the color codes their chat 
# packets contain than their pcolor
func get_player_chat_color(steam_id: int = Network.STEAM_ID):
	var color = cache[CACHE.USER_COLORS].get(steam_id, null)
	if color == null:
		color = get_color_from_resource(get_player_pcolor(steam_id))
	
	return color

# helper function for get_player_chat_color(), gets the file name of their pcolor
func get_player_pcolor(steam_id: int = Network.STEAM_ID,
					   default: String = PlayerData.FALLBACK_COSM["primary_color"]) -> String:
	if steam_id == Network.STEAM_ID:
		return PlayerData.cosmetics_equipped["primary_color"]
	
	var player = find_player_entity(steam_id)
	if player == null:
		return default
	
	return player.cosmetic_data.get("primary_color", default)

# find a player entity, used to find primary fur colors of people who haven't sent a chat yet, and
# therefore won't have a cached username color
func find_player_entity(steam_id: int = Network.STEAM_ID) -> Node:
	if is_entities_loaded():
		for node in entities.get_children():
			if node is Actor and node.actor_type == "player" and node.owner_id == steam_id:
				return node
	return null

# helper function for get_player_chat_color(), tries to load the file name of their pcolor
func get_color_from_resource(pcolor: String,
							 mod: Color = Color(0.95, 0.9, 0.9), 
							 default = DEFAULT_CHAT_COLOR) -> String:
	var color = Globals.cosmetic_data.get(pcolor, null)
	if color != null:
		color = color.get("file", null)
		if color != null:
			return str((color.main_color * Color(0.95, 0.9, 0.9)).to_html())
	
	return default

# this works hand in hand with _message_flush() to check which lobby member sent
# the most recent message packet by seeing who's MESSAGE_COUNT_TRACKER changed
func get_last_sender_id(allow_client = true):
	for key in Network.MESSAGE_COUNT_TRACKER.keys():
		if _message_count_tracker_copy.get(key, -1) != Network.MESSAGE_COUNT_TRACKER[key]:
			if key == Network.STEAM_ID and not allow_client:
				continue
			return key
	return null

@tool
extends EditorPlugin
## KinemIQ Bridge for Godot 4 - animations from KinemIQ Studio (https://kinemiq.app/studio/) straight into this project.
##
## Install: put the folder addons/kinemiq_bridge into your project (next to project.godot), then
## Project > Project Settings > Plugins > KinemIQ Bridge > Enable.
## Use: in KinemIQ Studio press Export > Send to Godot. The animation arrives as res://kinemiq/<name>.glb (character +
## animation, imported by Godot like any glTF: drag it into a scene, its AnimationPlayer plays it). The same animation
## sent again updates the same file.
## Network: listens on 127.0.0.1:8768 only (this computer, never the internet); only https://kinemiq.app and a local
## studio may send. Sends nothing anywhere, no analytics. Turn it off by disabling the plugin.
## Version 1.0.0 (KinemIQ, https://kinemiq.app)

const VERSION := "1.0.0"
const ORIGINS := ["https://kinemiq.app", "https://www.kinemiq.app"]
const MAX_BODY := 64 * 1024 * 1024
const FOLDER := "res://kinemiq"

var port := 8768
var server: TCPServer
var conns: Array = []
var dock: VBoxContainer
var status_label: Label
var last_label: Label
var pending := ""


func _enter_tree() -> void:
	var p := OS.get_environment("KQ_GODOT_PORT") # (the tests' own port - never the user's)
	if p.is_valid_int() and int(p) > 1024:
		port = int(p)
	dock = _make_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	server = TCPServer.new()
	if server.listen(port, "127.0.0.1") != OK:
		server = null
		_status("Port %d is taken by another program - close it, then disable and enable this plugin." % port)
	else:
		_status("Ready. In KinemIQ Studio: Export > Send to Godot.")
	set_process(true)


func _exit_tree() -> void:
	if server:
		server.stop()
	for c in conns:
		c["peer"].disconnect_from_host()
	conns.clear()
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()


func _make_dock() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = "KinemIQ"
	var t := Label.new()
	t.text = "KinemIQ Bridge " + VERSION
	t.add_theme_font_size_override("font_size", 15)
	v.add_child(t)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status_label)
	last_label = Label.new()
	last_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	last_label.modulate = Color(0.75, 0.78, 0.85)
	v.add_child(last_label)
	var b := Button.new()
	b.text = "Open KinemIQ Studio"
	b.pressed.connect(func(): OS.shell_open("https://kinemiq.app/studio/"))
	v.add_child(b)
	return v


func _status(t: String) -> void:
	if status_label:
		status_label.text = t
	print("[KinemIQ] ", t)


func _process(_d: float) -> void:
	if server and server.is_connection_available():
		conns.append({"peer": server.take_connection(), "buf": PackedByteArray(), "t": Time.get_ticks_msec()})
	for c in conns.duplicate():
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			conns.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var r := peer.get_partial_data(n)
			if r[0] == OK:
				var buf: PackedByteArray = c["buf"]
				buf.append_array(r[1])
				c["buf"] = buf
		if _try_handle(c):
			conns.erase(c)
		elif Time.get_ticks_msec() - int(c["t"]) > 30000:
			peer.disconnect_from_host()
			conns.erase(c)
	# a received file: once Godot imported it, show it in the FileSystem dock
	if pending != "":
		var fs := EditorInterface.get_resource_filesystem()
		if not fs.is_scanning() and ResourceLoader.exists(pending):
			EditorInterface.select_file(pending)
			pending = ""


func _allowed(origin: String) -> bool:
	if origin == "":
		return true # (not a web page: a local tool)
	return origin in ORIGINS or origin.begins_with("http://127.0.0.1:") or origin.begins_with("http://localhost:")


## one request in the connection's buffer: false = not complete yet
func _try_handle(c: Dictionary) -> bool:
	var buf: PackedByteArray = c["buf"]
	var head := buf.slice(0, mini(buf.size(), 16384)).get_string_from_ascii()
	var end := head.find("\r\n\r\n")
	if end < 0:
		if buf.size() >= 16384:
			_reply(c["peer"], 400, "{\"error\":\"Bad request.\"}", "")
			return true
		return false
	var lines := head.substr(0, end).split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		_reply(c["peer"], 400, "{\"error\":\"Bad request.\"}", "")
		return true
	var method := first[0]
	var path := first[1].split("?")[0].trim_suffix("/")
	var h := {}
	for i in range(1, lines.size()):
		var k := lines[i].find(":")
		if k > 0:
			h[lines[i].substr(0, k).strip_edges().to_lower()] = lines[i].substr(k + 1).strip_edges()
	var length := int(h.get("content-length", "0"))
	if length > MAX_BODY:
		_reply(c["peer"], 413, "{\"error\":\"Too large.\"}", "")
		return true
	if buf.size() < end + 4 + length:
		return false
	var origin: String = h.get("origin", "")
	var host: String = str(h.get("host", "")).split(":")[0]
	if not (host == "127.0.0.1" or host == "localhost") or not _allowed(origin):
		_reply(c["peer"], 403, "{\"error\":\"This page may not send to Godot.\"}", "")
		return true
	var allow := origin if origin != "" else ""
	if method == "OPTIONS":
		# the browser's preflight - also its local-network permission (Private Network Access)
		_reply(c["peer"], 204, "", allow, "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, X-Name, X-Fps\r\nAccess-Control-Allow-Private-Network: true\r\nAccess-Control-Max-Age: 600\r\n")
		return true
	var project := str(ProjectSettings.get_setting("application/config/name", "Godot project")).replace("\"", "'")
	if method == "GET" and path == "/kinemiq/ping":
		_reply(c["peer"], 200, JSON.stringify({"ok": true, "app": "godot", "bridge": VERSION, "project": project}), allow)
		return true
	if method == "POST" and path == "/api/godot/push":
		var body := buf.slice(end + 4, end + 4 + length)
		if body.size() < 12 or body.slice(0, 4).get_string_from_ascii() != "glTF":
			_reply(c["peer"], 400, "{\"error\":\"Not a KinemIQ animation (GLB).\"}", allow)
			return true
		var file := _save(str(h.get("x-name", "")).uri_decode(), body)
		if file == "":
			_reply(c["peer"], 500, "{\"error\":\"Could not write the file into the project.\"}", allow)
			return true
		_reply(c["peer"], 200, JSON.stringify({"ok": true, "file": file, "bridge": VERSION, "project": project}), allow)
		return true
	_reply(c["peer"], 404, "{\"error\":\"Unknown.\"}", allow)
	return true


## the GLB into res://kinemiq/<name>.glb - the same name again overwrites (updates) it - and Godot imports it
func _save(name: String, body: PackedByteArray) -> String:
	var safe := RegEx.create_from_string("[^A-Za-z0-9_\\-]+").sub(name.strip_edges(), "_", true).strip_edges().trim_prefix("_").trim_suffix("_")
	if safe == "":
		safe = "kinemiq_animation"
	safe = safe.substr(0, 80)
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var path := FOLDER + "/" + safe + ".glb"
	var existed := FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(body)
	f.close()
	var fs := EditorInterface.get_resource_filesystem()
	if existed:
		fs.update_file(path)
		fs.reimport_files(PackedStringArray([path]))
	else:
		fs.scan()
	pending = path
	last_label.text = "Last: " + path + "  ·  " + Time.get_time_string_from_system().substr(0, 5)
	_status("✓ Animation arrived: " + path + " - drag it into a scene (its AnimationPlayer plays it).")
	DisplayServer.window_request_attention() # (Godot blinks in the taskbar)
	return path


func _reply(peer: StreamPeerTCP, code: int, body: String, origin: String, extra := "") -> void:
	var names := {200: "OK", 204: "No Content", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 413: "Payload Too Large", 500: "Internal Server Error"}
	var b := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Length: %d\r\nConnection: close\r\n" % [code, names.get(code, "OK"), b.size()]
	if b.size() > 0:
		head += "Content-Type: application/json\r\n"
	if origin != "":
		head += "Access-Control-Allow-Origin: %s\r\nVary: Origin\r\n" % origin
	head += extra + "\r\n"
	peer.put_data(head.to_utf8_buffer())
	if b.size() > 0:
		peer.put_data(b)
	peer.disconnect_from_host()

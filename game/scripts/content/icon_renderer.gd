class_name IconRenderer
extends Node
## Ikony przedmiotów jako małe figury 3D: modele z ItemModel renderowane po kilkadziesiąt naraz w ukrytym
## SubViewport (siatka komórek, kamera ortogonalna, światło z góry z lewej). Gotowy obrazek trafia do
## tej samej ImageTexture, którą rejestr już oddał interfejsowi, więc sloty odświeżają się same.
## Bez okna (serwer dedykowany, testy bez grafiki) zostają ikony 2D.

const PX := 64          # rozmiar ikony
const GRID := 8         # komórek w rzędzie (64 ikony na jeden render)

static var _node: IconRenderer = null
static var _queue: Array = []   # [rejestr, klucz, tekstura]

var vp: SubViewport
var cam: Camera3D
var holder: Node3D
var busy := false


## Czy przedmiot dostaje ikonę 3D: przedmioty z modelem z klocków (nie bloki, nie obrazki z paczek zasobów).
static func wants(reg: Registry, key: String) -> bool:
	if DisplayServer.get_name() == "headless" or Engine.get_main_loop() == null:
		return false
	var it: Dictionary = reg.items.get(key, {})
	if int(it.get("block", -1)) > 0:
		return false
	var icon: Variant = it.get("icon")
	if icon is String and str(icon).begins_with("user://resourcepacks") and not it.get("data", {}).has("model"):
		return false   # ikona z paczki zasobów ma pierwszeństwo
	var kind := str(ItemModel.spec(reg, key).kind)
	return kind == "tool" or kind == "item"


static func request(reg: Registry, key: String, tex: ImageTexture) -> void:
	# do czasu renderu: obrazek 2D w rozmiarze docelowym (slot nie zmieni rozmiaru po podmianie)
	var img := tex.get_image()
	if img and img.get_width() != PX:
		img.resize(PX, PX, Image.INTERPOLATE_NEAREST)
		tex.set_image(img)
	_queue.append([reg, key, tex])
	if _node == null or not is_instance_valid(_node):
		_node = IconRenderer.new()
		_node.name = "IconRenderer"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_node)


func _ready() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(PX * GRID, PX * GRID)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.64, 0.7)
	env.environment.ambient_light_energy = 1.0
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 0.85
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = GRID
	cam.position = Vector3(GRID * 0.5, -GRID * 0.5, 10)
	cam.near = 0.1
	cam.far = 30.0
	vp.add_child(cam)
	holder = Node3D.new()
	vp.add_child(holder)


func _process(_delta: float) -> void:
	if busy or _queue.is_empty():
		return
	_render_batch()


func _render_batch() -> void:
	busy = true
	var batch := _queue.slice(0, GRID * GRID)
	_queue = _queue.slice(GRID * GRID)
	for c in holder.get_children():
		c.queue_free()
	for i in batch.size():
		var reg: Registry = batch[i][0]
		var key: String = batch[i][1]
		var node := ItemModel.build(reg, key)
		var cell := Node3D.new()
		cell.position = Vector3((i % GRID) + 0.5, -float(i / GRID) - 0.5, 0)
		holder.add_child(cell)
		var pose := Node3D.new()
		cell.add_child(pose)
		pose.add_child(node)
		# narzędzia po skosie (rękojeść w lewym dolnym rogu), inne przedmioty lekko obrócone
		if str(node.get_meta("kind", "")) == "tool":
			pose.rotation_degrees = Vector3(0, 0, -45)
			cell.rotation_degrees = Vector3(18, -24, 0)
		else:
			cell.rotation_degrees = Vector3(22, -32, 0)
		# dopasowanie do komórki: środek pudełka w środku komórki (obrót komórki kręci wokół niego),
		# najdłuższy bok 0.84 komórki
		var aabb := _bounds(cell)
		if aabb.size.length() > 0.0001:
			var s := 0.84 / maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z * 0.6))
			pose.scale = Vector3.ONE * s
			pose.position = -aabb.get_center() * s
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var sheet := vp.get_texture().get_image()
	if sheet:
		sheet.convert(Image.FORMAT_RGBA8)
		for i in batch.size():
			var tex: ImageTexture = batch[i][2]
			var img := sheet.get_region(Rect2i((i % GRID) * PX, (i / GRID) * PX, PX, PX))
			if not img.is_invisible():
				tex.set_image(img)
	busy = false


## Pudełko obejmujące wszystkie siatki pod komórką, w układzie komórki.
static func _bounds(cell: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := cell.global_transform.affine_inverse()
	for mi in cell.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := (inv * m.global_transform) * m.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

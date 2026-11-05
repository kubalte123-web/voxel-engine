class_name ModPack
## Paczki modów do pobierania z serwera: lista plików moda, odcisk (skrót zawartości) i bezpieczne
## rozpakowanie u klienta. Odcisk liczy obrazy PNG z pikseli (a nie bajtów pliku), więc ten sam mod
## wbudowany w wyeksportowaną grę (gdzie PNG są zaimportowane) i ten sam mod z folderu mają ten sam odcisk.

const CACHE := "user://server_mods"
const MAX_TOTAL := 64 * 1024 * 1024     # górny limit pobierania z jednego serwera
const MAX_FILE := 16 * 1024 * 1024
const MAX_FILES := 2000
const ALLOWED := ["lua", "json", "png", "txt", "md", "ogg", "wav", "mp3", "glb", "gltf", "bin", "cfg"]

static var _fp_cache := {}   # ścieżka moda -> odcisk


## Pliki moda: ścieżka względna -> bajty. W wyeksportowanej grze obrazy odtwarzamy z zaimportowanych tekstur.
static func files(mod_path: String) -> Dictionary:
	var out := {}
	_collect(mod_path, "", out)
	return out


static func _collect(root: String, rel: String, out: Dictionary) -> void:
	var dir := root.path_join(rel)
	var seen := {}
	for f in DirAccess.get_files_at(dir):
		var name := f
		if f.ends_with(".import") or f.ends_with(".remap"):
			name = f.get_basename()
		if seen.has(name) or name.ends_with(".uid"):
			continue
		seen[name] = true
		if not ALLOWED.has(name.get_extension().to_lower()):
			continue
		var path := dir.path_join(name)
		var bytes := PackedByteArray()
		if FileAccess.file_exists(path):
			bytes = FileAccess.get_file_as_bytes(path)
		if bytes.is_empty() and name.get_extension().to_lower() == "png" and ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex:
				var img := tex.get_image()
				if img.is_compressed():
					img.decompress()
				bytes = img.save_png_to_buffer()
		if not bytes.is_empty():
			out[rel.path_join(name) if rel != "" else name] = bytes
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_collect(root, rel.path_join(d) if rel != "" else d, out)


## Odcisk moda: SHA-256 po posortowanych plikach (ścieżka + zawartość; PNG jako piksele RGBA).
static func fingerprint(mod_path: String) -> String:
	if _fp_cache.has(mod_path):
		return _fp_cache[mod_path]
	var fs := files(mod_path)
	var keys := fs.keys()
	keys.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for k in keys:
		ctx.update(str(k).to_utf8_buffer())
		var b: PackedByteArray = fs[k]
		if str(k).get_extension().to_lower() == "png":
			var img := Image.new()
			if img.load_png_from_buffer(b) == OK:
				img.convert(Image.FORMAT_RGBA8)
				b = img.get_data()
		ctx.update(b)
	var fp := ctx.finish().hex_encode().left(24)
	_fp_cache[mod_path] = fp
	return fp


static func clear_cache() -> void:
	_fp_cache.clear()


## Paczka do wysłania: skompresowany słownik plików.
static func pack(mod_path: String) -> PackedByteArray:
	var raw := var_to_bytes(files(mod_path))
	var z := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(z)
	return out


## Folder pobranego moda w pamięci podręcznej: user://server_mods/<id>@<odcisk>.
static func cache_dir(id: String, fp: String) -> String:
	return CACHE.path_join("%s@%s" % [id, fp])


static func is_cached(id: String, fp: String) -> bool:
	return FileAccess.file_exists(cache_dir(id, fp).path_join("mod.json"))


## Rozpakowanie u klienta. Zwraca "" albo opis błędu. Ścieżki są sprawdzane (bez „..”, tylko dozwolone pliki).
static func unpack(id: String, fp: String, data: PackedByteArray) -> String:
	if data.size() < 4:
		return "pusta paczka"
	var raw_size := data.decode_u32(0)
	if raw_size > MAX_TOTAL:
		return "paczka za duża"
	var raw := data.slice(4).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	var fs: Variant = bytes_to_var(raw)   # bez obiektów: bytes_to_var nie tworzy instancji
	if not fs is Dictionary or fs.size() > MAX_FILES:
		return "zła paczka"
	var dir := cache_dir(id, fp)
	var tmp := dir + ".part"
	_rm(tmp)
	for k in fs:
		var rel := str(k).replace("\\", "/")
		var b: Variant = fs[k]
		if not b is PackedByteArray or b.size() > MAX_FILE:
			return "zły plik w paczce"
		if rel.is_empty() or rel.begins_with("/") or ".." in rel.split("/") or ":" in rel:
			return "niedozwolona ścieżka: " + rel
		if not ALLOWED.has(rel.get_extension().to_lower()):
			return "niedozwolony plik: " + rel
		var path := tmp.path_join(rel)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return "nie można zapisać " + rel
		f.store_buffer(b)
		f.close()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(tmp.path_join("mod.json")))
	if not manifest is Dictionary or str(manifest.get("id", "")) != id:
		_rm(tmp)
		return "paczka nie zawiera moda " + id
	_rm(dir)
	DirAccess.rename_absolute(tmp, dir)
	return ""


static func _rm(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_rm(path.path_join(d))
	DirAccess.remove_absolute(path)

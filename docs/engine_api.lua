---@meta
-- Definicje API silnika dla podpowiedzi w edytorze (wygenerowane: tools/build_api_defs.py).
-- Opis: docs/MODDING.md. Pozycje: wektor albo tabela {x =, y =, z =}.

---@class engine
engine = {}

---@class engine.mod
engine.mod = {}

function engine.log(...) end

--- zdarzenia
---@param name any
---@param fn any
---@param priority any
function engine.on(name, fn, priority) end

---@param name any
---@param data any
function engine.emit(name, data) end

---@class engine.hooks
engine.hooks = {}

---@param name any
---@param fn any
---@param priority any
function engine.hooks.before(name, fn, priority) end

---@param name any
---@param fn any
---@param priority any
function engine.hooks.after(name, fn, priority) end

--- biblioteki: mod udostępnia tabelę, inne mody ją pobierają (wymagają go w mod.json)
---@param t any
function engine.export(t) end

--- biblioteka innego moda albo nil, gdy mod jest wyłączony (w mod.json: "after": [id])
---@param id any
function engine.optional(id) end

---@param id any
function engine.require(id) end

---@class engine.settings
engine.settings = {}

---@param key any
function engine.settings.get(key) end

---@class engine.storage
engine.storage = {}

---@param key any
---@param default any
function engine.storage.get(key, default) end

---@param key any
---@param value any
function engine.storage.set(key, value) end

---@class engine.blocks
engine.blocks = {}

---@param key any
---@param def any
function engine.blocks.register(key, def) end

--- definicja bloku (tabela); w content.lua można ją zmieniać
---@param key any
function engine.blocks.get(key) end

---@param key any
function engine.blocks.id(key) end

---@param id any
function engine.blocks.key(id) end

---@param id any
function engine.blocks.name(id) end

function engine.blocks.list() end

--- stany: tabela stanu bloku w świecie, zmiana stanu (inny wariant tego samego bloku)
---@param pos any
function engine.blocks.state(pos) end

---@param pos any
---@param changes any
function engine.blocks.set_state(pos, changes) end

---@param block any
---@param changes any
function engine.blocks.with_state(block, changes) end

---@param block any
function engine.blocks.base(block) end

--- dane bloku: znikają razem z blokiem (zdarzenie block.removed)
---@param pos any
function engine.blocks.data(pos) end

---@param pos any
---@param key any
---@param value any
function engine.blocks.set_data(pos, key, value) end

---@param pos any
function engine.blocks.clear_data(pos) end

--- kontener przypisany do bloku (skrzynia): po zniszczeniu bloku przedmioty wypadają
---@param pos any
---@param size any
function engine.blocks.container(pos, size) end

--- aktualizacje: fn(ctx) z ctx.reason = "random" | "scheduled" | "neighbor"
---@param keys any
---@param fn any
function engine.blocks.on_update(keys, fn) end

--- model bloku: wygląd (anim, emitters, colors, hide) i jednorazowa animacja; widzą wszyscy gracze
---@param pos any
---@param look any
function engine.blocks.look(pos, look) end

---@param pos any
function engine.blocks.get_look(pos) end

---@param pos any
---@param name any
function engine.blocks.animate(pos, name) end

---@param pos any
---@param seconds any
---@param tag any
function engine.blocks.schedule(pos, seconds, tag) end

---@class engine.items
engine.items = {}

---@param key any
---@param def any
function engine.items.register(key, def) end

---@param key any
function engine.items.def(key) end

---@param key any
function engine.items.name(key) end

---@param key any
function engine.items.block_of(key) end

--- per_player = true: każdy gracz ma własną kopię (ekwipunek); funkcje działają na kopii bieżącego gracza
---@param id any
---@param size any
---@param persist any
---@param per_player any
function engine.items.container(id, size, persist, per_player) end

---@param id any
function engine.items.size(id) end

---@param id any
---@param index any
function engine.items.get(id, index) end

---@param id any
---@param index any
---@param slot any
function engine.items.set(id, index, slot) end

---@param key any
function engine.items.max_stack(key) end

--- dane egzemplarza w miejscu kontenera (np. amunicja broni); stosy z różnymi danymi się nie łączą
---@param id any
---@param index any
function engine.items.data(id, index) end

---@param id any
---@param index any
---@param key any
---@param value any
function engine.items.set_data(id, index, key, value) end

--- opis dynamiczny: fn(slot) zwraca listę linii; liczony na serwerze przy każdej zmianie miejsca
---@param key any
---@param fn any
function engine.items.tooltip(key, fn) end

---@class engine.worldgen
engine.worldgen = {}

---@param t any
function engine.worldgen.config(t) end

---@param key any
---@param def any
function engine.worldgen.biome(key, def) end

---@param key any
function engine.worldgen.get_biome(key) end

---@param key any
function engine.worldgen.remove_biome(key) end

function engine.worldgen.biomes() end

---@param biome any
---@param feature any
function engine.worldgen.add_feature(biome, feature) end

---@param biome any
---@param plant any
function engine.worldgen.add_plant(biome, plant) end

---@param key any
---@param def any
function engine.worldgen.structure(key, def) end

---@param key any
---@param def any
function engine.worldgen.ore(key, def) end

---@class engine.sounds
engine.sounds = {}

---@param name any
---@param def any
function engine.sounds.register(name, def) end

---@param name any
function engine.sounds.get(name) end

---@class engine.sound
engine.sound = {}

---@param name any
---@param opts any
function engine.sound.play(name, opts) end

---@param id any
function engine.sound.stop(id) end

---@class engine.particles
engine.particles = {}

---@param name any
---@param def any
function engine.particles.register(name, def) end

---@param name any
function engine.particles.get(name) end

---@param name any
---@param pos any
---@param opts any
function engine.particles.spawn(name, pos, opts) end

---@class engine.projectiles
engine.projectiles = {}

---@param type any
---@param def any
function engine.projectiles.register(type, def) end

---@param type any
function engine.projectiles.get(type) end

--- opts: position, direction (albo velocity), speed, owner (domyślnie bieżący gracz), data
---@param type any
---@param opts any
function engine.projectiles.spawn(type, opts) end

---@param id any
function engine.projectiles.remove(id) end

---@param type any
---@param fn any
function engine.projectiles.on_hit(type, fn) end

---@class engine.effects
engine.effects = {}

---@param name any
---@param def any
function engine.effects.register(name, def) end

---@param name any
function engine.effects.def(name) end

---@param name any
---@param seconds any
---@param strength any
function engine.effects.add(name, seconds, strength) end

---@param name any
function engine.effects.remove(name) end

---@param name any
function engine.effects.get(name) end

function engine.effects.list() end

---@class engine.animation
engine.animation = {}

--- {length = 1.0, loop = false, tracks = {arm_right = {{0, {0,0,0}}, {0.5, {-90,0,0}}}, ...}}
---@param name any
---@param def any
function engine.animation.register(name, def) end

--- zamiana wbudowanego stanu ("idle", "walk", "jump") na własną animację; nil przywraca
---@param state any
---@param name any
function engine.animation.override(state, name) end

---@class engine.entities
engine.entities = {}

--- rodzaj stworzenia: części modelu, AI, łup, pojawianie się (opis w docs/MODDING.md)
---@param type any
---@param def any
function engine.entities.register(type, def) end

---@param type any
function engine.entities.def(type) end

---@param type any
---@param pos any
---@param data any
---@param scale any
function engine.entities.spawn(type, pos, data, scale) end

---@param id any
function engine.entities.remove(id) end

---@param id any
function engine.entities.exists(id) end

---@param id any
function engine.entities.type(id) end

---@param id any
function engine.entities.position(id) end

---@param id any
function engine.entities.health(id) end

---@param id any
function engine.entities.state(id) end

---@param id any
function engine.entities.scale(id) end

---@param type any
---@param radius any
function engine.entities.list(type, radius) end

---@param id any
---@param pos any
function engine.entities.teleport(id, pos) end

---@param id any
---@param pos any
function engine.entities.move_to(id, pos) end

---@param id any
---@param s any
function engine.entities.set_scale(id, s) end

---@param id any
---@param amount any
---@param cause any
function engine.entities.damage(id, amount, cause) end

---@param id any
---@param name any
function engine.entities.animate(id, name) end

---@param id any
---@param tag any
---@param on any
function engine.entities.show(id, tag, on) end

---@param id any
---@param tag any
---@param color any
function engine.entities.color(id, tag, color) end

---@param id any
function engine.entities.data(id) end

---@param id any
---@param key any
---@param value any
function engine.entities.set_data(id, key, value) end

--- mózg: fn(ctx) co ai.think sekund (domyślnie 1) dla każdego stworzenia tego rodzaju na serwerze;
--- ctx: id, type, state, pos, health, max_health, data, target, rider, player, player_distance, on_floor
---@param types any
---@param fn any
function engine.entities.on_think(types, fn) end

--- stan: "idle", "wander", "flee", "follow", "chase" albo własna nazwa (stoi przez `seconds`)
---@param id any
---@param state any
---@param seconds any
function engine.entities.set_state(id, state, seconds) end

---@param id any
---@param player any
function engine.entities.attack(id, player) end

---@param id any
function engine.entities.target(id) end

---@param id any
---@param pos any
function engine.entities.look_at(id, pos) end

---@param id any
---@param v any
function engine.entities.push(id, v) end

---@param id any
function engine.entities.velocity(id) end

--- jazda (pole ride w definicji): gracz domyślnie bieżący
---@param id any
---@param player any
function engine.entities.mount(id, player) end

---@param player any
function engine.entities.dismount(player) end

---@param id any
function engine.entities.rider(id) end

--- najbliższy gracz w promieniu: {id, distance, position} albo nil
---@param pos any
---@param radius any
function engine.entities.nearest_player(pos, radius) end

--- przedmiot leżący na ziemi; gracz podnosi go, podchodząc (hak item.pickup)
---@param item any
---@param count any
---@param pos any
function engine.entities.drop(item, count, pos) end

---@class engine.commands
engine.commands = {}

---@param name any
---@param def any
function engine.commands.register(name, def) end

---@class engine.chat
engine.chat = {}

---@param text any
---@param opts any
function engine.chat.send(text, opts) end

---@class engine.world
engine.world = {}

---@param pos any
function engine.world.get_block(pos) end

--- promień od punktu w kierunku: {position, normal, place_pos, point, distance, block, key} albo nil
---@param from any
---@param dir any
---@param dist any
---@param opts any
function engine.world.raycast(from, dir, dist, opts) end

---@param pos any
---@param id any
function engine.world.set_block(pos, id) end

---@param pos any
function engine.world.biome(pos) end

---@param pos any
function engine.world.biome_key(pos) end

---@param x any
---@param z any
function engine.world.height(x, z) end

function engine.world.time() end

--- światło: {sky, block} w skali 0..15 i day (0 noc .. 1 dzień)
---@param pos any
function engine.world.light(pos) end

---@param h any
function engine.world.set_time(h) end

---@class engine.players
engine.players = {}

function engine.players.list() end

--- rola gracza: "player" | "moderator" | "admin" (gospodarz gry jest administratorem)
---@param id any
function engine.players.role(id) end

---@param id_or_account any
---@param role any
function engine.players.set_role(id_or_account, role) end

--- wywołuje fn(gracz) w imieniu każdego zalogowanego gracza (np. głód co sekundę)
---@param fn any
function engine.players.each(fn) end

--- logowanie: przyjęcie gracza na konto (zwraca nil albo opis błędu) i wyrzucenie z serwera
---@param id any
---@param account any
function engine.players.accept(id, account) end

---@param id any
---@param reason any
function engine.players.kick(id, reason) end

---@param id any
---@param fn any
function engine.as_player(id, fn) end

function engine.is_multiplayer() end

---@param text any
function engine.hash(text) end

---@class engine.player
engine.player = {}

function engine.player.id() end

function engine.player.name() end

function engine.player.is_host() end

---@class engine.player.storage
engine.player.storage = {}

---@param key any
---@param default any
function engine.player.storage.get(key, default) end

---@param key any
---@param value any
function engine.player.storage.set(key, value) end

function engine.player.position() end

---@param pos any
function engine.player.teleport(pos) end

function engine.player.velocity() end

---@param v any
function engine.player.push(v) end

---@param stat any
---@param value any
function engine.player.set(stat, value) end

---@param stat any
function engine.player.get(stat) end

function engine.player.health() end

function engine.player.max_health() end

---@param v any
function engine.player.set_health(v) end

---@param amount any
---@param cause any
function engine.player.damage(amount, cause) end

---@param amount any
function engine.player.heal(amount) end

---@param name any
function engine.player.animate(name) end

function engine.player.stop_animation() end

--- kolory części postaci: {tunic = "#aa3333", scarf = Color(...)} (klucze w docs/MODDING.md)
---@param t any
function engine.player.colors(t) end

--- blok, w który celuje gracz: {pos, normal, block}; with_liquids = true uwzględnia ciecze
---@param with_liquids any
function engine.player.target(with_liquids) end

--- statystyki: base = wartość bez modyfikatorów; modify dokłada modyfikator od źródła (add, mul)
---@param stat any
function engine.player.base(stat) end

---@param stat any
---@param source any
---@param m any
function engine.player.modify(stat, source, m) end

---@param stat any
---@param source any
function engine.player.unmodify(stat, source) end

function engine.player.eye_position() end

function engine.player.look_direction() end

---@param dist any
---@param opts any
function engine.player.raycast(dist, opts) end

function engine.player.in_liquid() end

function engine.player.eyes_in_liquid() end

function engine.player.selected_item() end

---@class engine.camera
engine.camera = {}

---@param key any
---@param value any
function engine.camera.set(key, value) end

---@param key any
function engine.camera.get(key) end

---@param m any
function engine.camera.mode(m) end

---@class engine.hotbar
engine.hotbar = {}

---@param container any
---@param first any
---@param count any
function engine.hotbar.bind(container, first, count) end

function engine.hotbar.unbind() end

function engine.hotbar.selected() end

---@class engine.ui
engine.ui = {}

--- okno opisane danymi: {id, title, sections = {{type="character"|"slots"|"text"|"button"|"input"|"progress", ...}}}
--- przycisk dostaje tabelę wartości pól "input": on_press(fields), np. fields.login
---@param spec any
function engine.ui.window(spec) end

---@param id any
function engine.ui.close(id) end

---@param id any
function engine.ui.is_open(id) end

---@param text any
function engine.ui.notify(text) end

--- pasek na ekranie gry: {id, label, value, max, color}
---@param spec any
function engine.ui.bar(spec) end

--- napis na ekranie gry: {id, text, color}
---@param spec any
function engine.ui.text(spec) end

---@param id any
function engine.ui.remove(id) end

--- przedmiot trzymany kursorem w oknie: {item, count} albo {}
function engine.ui.held() end

---@param v any
function engine.ui.set_held(v) end

---@class engine.input
engine.input = {}

--- {id, key = "E", label = "Plecak", on_press = function() ... end}
---@param spec any
function engine.input.bind(spec) end

---@param a any
---@param b any
function engine.random(a, b) end


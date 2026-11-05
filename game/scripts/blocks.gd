class_name Blocks
## Skrót do bieżącego rejestru bloków. Silnik zna tylko powietrze (id 0);
## wszystkie inne bloki rejestrują mody (podstawowe są w modzie "base").

const AIR := 0
const OPAQUE := Registry.OPAQUE
const CROSS := Registry.CROSS
const SOLID := Registry.SOLID
const LIQUID := Registry.LIQUID
const THIN := Registry.THIN
const MODEL := Registry.MODEL
const BOXES := Registry.BOXES

## Kolejność bloków w światach zapisanych przed rejestrem (etapy 1–3), gdy world.json nie ma palety.
const LEGACY_KEYS := ["air", "grass", "dirt", "stone", "planks", "sand", "log", "leaves",
	"snow", "cactus", "tall_grass", "flower_red", "flower_yellow"]

static var reg: Registry = Registry.new()


static func id(key: String) -> int:
	return reg.id_of(key)


static func key(block: int) -> String:
	return reg.block_key(block)


static func name(block: int) -> String:
	return reg.block_name(block)


static func props(block: int) -> int:
	return reg.props[block] if block >= 0 and block < reg.props.size() else 0


static func count() -> int:
	return reg.count()

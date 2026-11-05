-- Przetrwanie: jedzenie. Jabłka wypadają z liści (szansa 8%), chleb to przykład przedmiotu bez bloku.
engine.items.register("apple", { name = "Jabłko", icon = { pattern = "food", color = "#d23a2a", color2 = "#a02418" }, food = 4 })
engine.items.register("bread", { name = "Chleb", icon = { pattern = "food", color = "#c8964e", color2 = "#a0703a" }, food = 6 })

local leaves = engine.blocks.get("leaves")
leaves.drops = { { item = "apple", count = 1, chance = 0.08 } }

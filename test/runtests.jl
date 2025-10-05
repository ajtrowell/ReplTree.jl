using Test
using REPLTrees

@testset "json_pointer_segments" begin
    @test json_pointer_segments("") == String[]
    @test json_pointer_segments("/foo") == ["foo"]
    @test json_pointer_segments("/foo/bar") == ["foo", "bar"]
    @test json_pointer_segments("/foo//bar") == ["foo", "", "bar"]
    @test json_pointer_segments("/~0") == ["~"]
    @test json_pointer_segments("/~1") == ["/"]
    @test json_pointer_segments("/~01") == ["~1"]
    @test_throws ArgumentError json_pointer_segments("foo")
end

@testset "example_cat_registry" begin
    registry = example_cat_registry()

    @test registry isa Dict{String, Function}

    expected_keys = Set([
        "/name",
        "/appearance/color",
        "/appearance/eye-color",
        "/stats/age",
        "/stats/is-indoor",
        "/behavior/favorite-toy",
        "/behavior/nap-length-minutes",
        "/commands/move/stay",
        "/commands/move/come",
        "/commands/sound/speak",
        "/commands/sound/hiss",
        "/commands/sound/purr",
    ])

    @test Set(keys(registry)) == expected_keys
    @test !haskey(registry, "/appearance")

    @test registry["/name"]() == "Whiskers"
    @test registry["/appearance/color"]() == "tabby"
    @test registry["/appearance/eye-color"]() == "green"
    @test registry["/stats/age"]() == 4
    @test registry["/stats/is-indoor"]()
    @test registry["/behavior/favorite-toy"]() == "feather wand"
    @test registry["/behavior/nap-length-minutes"]() == 25

    for (pointer, leaf_fn) in registry
        @test pointer isa String
        @test leaf_fn isa Function
        @test !isempty(json_pointer_segments(pointer))
    end

    branches = registry_branches(registry)
    @test Set(branches) == Set([
        "/appearance",
        "/behavior",
        "/stats",
        "/commands",
        "/commands/move",
        "/commands/sound",
    ])
end

@testset "registry_branches" begin
    registry = Dict(
        "/a/b/c" => () -> 1,
        "/a/d" => () -> 2,
        "/e" => () -> 3,
        "/f//g" => () -> 4,
        "/foo~1bar/baz" => () -> 5,
        "/tilde~0branch/sub" => () -> 6,
    )

    expected = Set([
        "/a",
        "/a/b",
        "/f",
        "/f/",
        "/foo~1bar",
        "/tilde~0branch",
    ])

    @test Set(registry_branches(registry)) == expected
end

@testset "validate_registry" begin
    valid_registry = Dict(
        "/appearance/color" => () -> "tabby",
        "/appearance/pattern" => () -> "striped",
    )

    @test validate_registry(valid_registry) === nothing

    invalid_registry = Dict(
        "/appearance" => () -> "pretty",
        "/appearance/color" => () -> "tabby",
    )

    @test_throws ArgumentError validate_registry(invalid_registry)
end

@testset "registry_to_namedtuples" begin
    registry = example_cat_registry()
    hierarchy = registry_to_namedtuples(registry)

    @test hierarchy isa NamedTuple
    @test Set(propertynames(hierarchy)) == Set([:name, :appearance, :stats, :behavior, :commands])

    @test hierarchy.name isa NamedTuple
    @test propertynames(hierarchy.name) == (:pointer, :leaf)
    @test hierarchy.name.pointer == "/name"
    @test hierarchy.name.leaf() == "Whiskers"

    appearance = hierarchy.appearance
    @test appearance isa NamedTuple
    @test Set(propertynames(appearance)) == Set([:color, :eye_color])
    @test appearance.color.pointer == "/appearance/color"
    @test appearance.color.leaf() == "tabby"
    @test appearance.eye_color.pointer == "/appearance/eye-color"
    @test appearance.eye_color.leaf() == "green"

    commands = hierarchy.commands
    @test commands isa NamedTuple
    @test Set(propertynames(commands)) == Set([:move, :sound])
    @test commands.move isa NamedTuple
    @test commands.move.stay.leaf() == "Don't move"
    @test commands.move.come.leaf() == "Here kitty kitty"
    @test commands.sound.speak.leaf() == "Meow"
    @test commands.sound.purr.leaf() == "Purr"

    stats = hierarchy.stats
    @test Set(propertynames(stats)) == Set([:age, :is_indoor])
    @test stats.is_indoor.pointer == "/stats/is-indoor"
    @test stats.is_indoor.leaf() == true

    behavior = hierarchy.behavior
    @test Set(propertynames(behavior)) == Set([:favorite_toy, :nap_length_minutes])
    @test behavior.favorite_toy.pointer == "/behavior/favorite-toy"
    @test behavior.nap_length_minutes.pointer == "/behavior/nap-length-minutes"
end

@testset "namedtuples_to_registry" begin
    registry = example_cat_registry()
    hierarchy = registry_to_namedtuples(registry)
    regenerated = namedtuples_to_registry(hierarchy)

    @test regenerated isa Dict{String, Function}
    @test Set(keys(regenerated)) == Set(keys(registry))

    for pointer in keys(registry)
        @test regenerated[pointer]() == registry[pointer]()
    end

    invalid_hierarchy = (appearance = (; pointer = "/appearance", leaf = () -> "pretty", color = (; pointer = "/appearance/color", leaf = () -> "tabby")),)
    @test_throws ArgumentError namedtuples_to_registry(invalid_hierarchy)

    root_leaf = (; pointer = "", leaf = () -> "root")
    @test_throws ArgumentError namedtuples_to_registry(root_leaf)
end

@testset "menu_rendering" begin
    registry = example_cat_registry()
    menu = registry_to_menu(registry)

    @test menu isa MenuBranch
    @test menu.pointer == ""
    @test Set(propertynames(menu)) == Set([:name, :appearance, :stats, :behavior, :commands])

    stats_branch = menu.stats
    @test stats_branch isa MenuBranch
    @test stats_branch.pointer == "/stats"
    @test Set(propertynames(stats_branch)) == Set([:age, :is_indoor])

    indoor_leaf = stats_branch.is_indoor
    @test indoor_leaf isa Function
    @test REPLTrees.child_pointer(stats_branch, :is_indoor) == "/stats/is-indoor"
    @test indoor_leaf()

    sound_branch = menu.commands.sound
    @test sound_branch isa MenuBranch
    @test sound_branch.pointer == "/commands/sound"
    @test sound_branch.purr() == "Purr"
    @test sound_branch.hiss() == "Hiss!"

    appearance_branch = menu.appearance
    @test appearance_branch.color() == "tabby"
    @test appearance_branch.eye_color() == "green"

    branch_display = sprint(show, stats_branch)
    @test occursin("MenuBranch(/stats; choices=[age(), is-indoor()])", branch_display)

    regenerated = menu_to_registry(menu)
    @test Set(keys(regenerated)) == Set(keys(registry))

    for pointer in keys(registry)
        @test regenerated[pointer]() == registry[pointer]()
    end

    config = Dict(:volume => 10)
    config_branch = MenuBranch("/settings", [:config], Dict(:config => config), Dict(:config => "config"))
    config_display = sprint(show, config_branch)
    @test occursin("choices=[config]", config_display)
    @test_throws ArgumentError menu_to_registry(config_branch)
end

@testset "example_kitchen_registry" begin
    registry = example_kitchen_registry()

    @test registry["/name"]() == "My Kitchen"
    @test registry["/config_value"] isa REPLTrees.KitchenConfig

    menu = registry_to_menu(registry)
    @test menu isa MenuBranch

    config_value = menu.config_value
    @test config_value === registry["/config_value"]
    @test REPLTrees.child_pointer(menu, :config_value) == "/config_value"

    show_config_leaf = menu.show_config
    @test show_config_leaf isa Function
    @test REPLTrees.is_leaf_callable(show_config_leaf)

    branch_display = sprint(show, menu)
    @test occursin("config_value", branch_display)
    @test !occursin("config_value()", branch_display)

    cook_branch = menu.stove.cook
    cook_display = sprint(show, cook_branch)
    @test occursin("add()", cook_display)
    @test occursin("remove()", cook_display)

    kitchen = menu.config_value
    @test kitchen isa REPLTrees.KitchenConfig
    @test isempty(kitchen.stove)
    @test kitchen.items_cooked == 0

    redirect_stdout(devnull) do
        cook_branch.add("Soup")
    end
    @test kitchen.items_cooked == 1
    @test kitchen.stove == ["Soup"]

    removed = cook_branch.remove()
    @test removed == "Soup"
    @test isempty(kitchen.stove)

    removed_again = cook_branch.remove()
    @test removed_again === false
    @test isempty(kitchen.stove)

    @test_throws ArgumentError menu_to_registry(menu)
end

@testset "example_dishwasher_registry" begin
    registry = example_dishwasher_registry()

    @test registry["/name"]() == "Dishwasher"
    config = registry["/config"]
    @test config isa REPLTrees.DishwasherConfig
    @test config.running == false
    @test isempty(config.queue)

    @test registry["/load/remove"]() === nothing

    registry["/load/add"]("Plate")
    registry["/load/add"]("Cup")
    @test length(config.queue) == 2

    menu = registry_to_menu(registry)
    @test menu.load.add("Bowl") == 3
    @test length(config.queue) == 3

    summary = menu.status.summary()
    @test occursin("3 item", summary)

    @test !menu.status.running()
    @test menu.cycle.start()
    @test menu.status.running()

    cycles = menu.cycle.finish()
    @test cycles == 1
    @test !menu.status.running()
    @test isempty(config.queue)

    removal = registry["/load/remove"]()
    @test removal === nothing
end

@testset "merge_registry" begin
    base = Dict(
        "/kitchen/name" => () -> "Kitchen",
    )
    additions = Dict(
        "/info" => () -> "Details",
        "/config" => Dict(:a => 1),
    )

    merged = merge_registry(base, "/appliances/dishwasher", additions)
    @test haskey(merged, "/kitchen/name")
    @test haskey(merged, "/appliances/dishwasher/info")
    @test merged["/appliances/dishwasher/config"] == Dict(:a => 1)
    @test !haskey(base, "/appliances/dishwasher/info")

    mutable_base = Dict{String, Any}(
        "/root/value" => () -> 1,
    )
    merge_registry!(mutable_base, "/branch", Dict("/leaf" => () -> 2))
    @test mutable_base["/branch/leaf"]() == 2

    @test_throws ArgumentError merge_registry!(Dict{String, Any}(
        "/dup" => () -> 1,
    ), "/dup", Dict("/other" => () -> 2))

    @test_throws ArgumentError merge_registry(
        Dict("/a/b" => () -> 1),
        "/a",
        Dict("/b" => () -> 2),
    )
end

@testset "example_kitchen_combo_registry" begin
    registry = example_kitchen_combo_registry()

    @test registry["/config_value"] isa REPLTrees.KitchenConfig
    @test registry["/appliances/dishwasher/name"]() == "Dishwasher"

    menu = registry_to_menu(registry)
    appliances = menu.appliances
    @test appliances isa MenuBranch
    dishwasher = appliances.dishwasher
    @test dishwasher isa MenuBranch

    @test dishwasher.name() == "Dishwasher"
    @test menu.config_value isa REPLTrees.KitchenConfig
end

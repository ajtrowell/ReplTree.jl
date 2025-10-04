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
    @test indoor_leaf isa MenuLeaf
    @test indoor_leaf.pointer == "/stats/is-indoor"
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
    @test occursin("MenuBranch(/stats; choices=[age, is-indoor])", branch_display)

    leaf_display = sprint(show, indoor_leaf)
    @test occursin("MenuLeaf(/stats/is-indoor)", leaf_display)

    regenerated = menu_to_registry(menu)
    @test Set(keys(regenerated)) == Set(keys(registry))

    for pointer in keys(registry)
        @test regenerated[pointer]() == registry[pointer]()
    end
end

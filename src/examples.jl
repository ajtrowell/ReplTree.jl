"""
    example_cat_registry() -> Dict{String, Function}

Return a dictionary describing leaf values for a sample cat registry.

Keys are JSON Pointer strings identifying the leaves, and values are
zero-argument callables producing the associated leaf data. Branches are
not represented in the dictionary.
"""
function example_cat_registry()
    registry = Dict{String, Function}(
        "/name" => () -> "Whiskers",
        "/appearance/color" => () -> "tabby",
        "/appearance/eye-color" => () -> "green",
        "/stats/age" => () -> 4,
        "/stats/is-indoor" => () -> true,
        "/behavior/favorite-toy" => () -> "feather wand",
        "/behavior/nap-length-minutes" => () -> 25,
        "/commands/move/stay" => () -> "Don't move",
        "/commands/move/come" => () -> "Here kitty kitty",
        "/commands/sound/speak" => () -> "Meow",
        "/commands/sound/hiss" => () -> "Hiss!",
        "/commands/sound/purr" => () -> "Purr",
    )
    validate_registry(registry)
    return registry
end

"""
    Example mutable Struct KitchenConfig

Demonstrates how configuration data can be represented as part of a
registry.
"""
@kwdef mutable struct KitchenConfig
    stove_elements::Integer = 4
    oven_bays::Integer = 1
    items_cooked::Integer = 0
    stove::Vector{Any} = Any[]
end

"""
    example_kitchen_registry() -> Dict{String, Any}

Return a dictionary describing leaf values for a sample kitchen registry.

Keys are JSON Pointer strings identifying the leaves.
Values may be any type. Expected types are callables which may be
closures on other data, or mutable / referenced data. Branches are not
represented in the dictionary.
"""
function example_kitchen_registry()
    config = KitchenConfig(stove_elements=4, oven_bays=2)

    registry = Dict{String, Any}(
        "/name" => () -> "My Kitchen",
        "/config" => config,
        "/stove/cook/remove" => () -> begin
            if !isempty(config.stove)
                return pop!(config.stove)
            end
            return false
        end,
        "/stove/cook/add" => food -> begin
            if length(config.stove) < config.stove_elements
                push!(config.stove, food)
                config.items_cooked += 1
                println("Added $food to stove, Cooking item number: $(config.items_cooked)")
                return true
            else
                println("Stove full, can't add $food")
                return false
            end
        end,
    )
    validate_registry(registry)
    return registry
end

"""
    Example mutable Struct DishwasherConfig

Configuration backing the dishwasher registry example.
"""
@kwdef mutable struct DishwasherConfig
    racks::Integer = 2
    queue::Vector{String} = String[]
    running::Bool = false
    completed_cycles::Integer = 0
end

@kwdef struct CallableType
    name = "Functor Example"
end

(ct::CallableType)() = "Return String from Call"

"""
    example_dishwasher_registry() -> Dict{String, Any}

Registry describing a dishwasher with mutable configuration and
callables for control operations.
"""
function example_dishwasher_registry()
    config = DishwasherConfig()

    registry = Dict{String, Any}(
        "/name" => () -> "Dishwasher",
        "/config" => config,
        "/branch/callableType" => CallableType(), # Functor example
        "/status/running" => () -> config.running,
        "/status/queue" => () -> copy(config.queue),
        "/status/summary" => () -> begin
            state = config.running ? "running" : "idle"
            "Dishwasher is $state with $(length(config.queue)) item(s) queued"
        end,
        "/load/add" => item -> begin
            push!(config.queue, item)
            return length(config.queue)
        end,
        "/load/remove" => () -> begin
            isempty(config.queue) && return nothing
            return popfirst!(config.queue)
        end,
        "/cycle/start" => () -> begin
            if config.running
                return false
            end
            config.running = true
            return true
        end,
        "/cycle/finish" => () -> begin
            if !config.running
                return false
            end
            config.running = false
            config.completed_cycles += 1
            empty!(config.queue)
            return config.completed_cycles
        end,
    )
    validate_registry(registry)
    return registry
end

"""
    example_kitchen_combo_registry() -> Dict{String, Any}

Combine the kitchen registry with a dishwasher registry under the
`/appliances/dishwasher` branch.
"""
function example_kitchen_combo_registry()
    kitchen = example_kitchen_registry()
    dishwasher = example_dishwasher_registry()
    return merge_registry(kitchen, "/appliances/dishwasher", dishwasher)
end

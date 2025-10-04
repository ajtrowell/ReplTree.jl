module REPLTrees

export json_pointer_segments,
       registry_branches,
       validate_registry,
       example_cat_registry,
       example_kitchen_registry,
       registry_to_namedtuples,
       namedtuples_to_registry,
       MenuBranch,
       MenuLeaf,
       registry_to_menu,
       menu_to_registry

"""
    json_pointer_segments(pointer::AbstractString) -> Vector{String}

Split a JSON Pointer string into unescaped path segments.

Implements the escape sequences from RFC 6901, converting `~1` to `/`
and `~0` to `~`. Returns an empty vector for the empty pointer `""`.
"""
function json_pointer_segments(pointer::AbstractString)
    pointer == "" && return String[]

    startswith(pointer, "/") || throw(ArgumentError("JSON pointer must begin with '/'"))

    raw_segments = split(pointer[2:end], "/", keepempty=true)
    return [String(replace(segment, "~0" => "~", "~1" => "/")) for segment in raw_segments]
end

const LEAF_FIELD = :leaf
const POINTER_FIELD = :pointer

escape_json_pointer_segment(segment::AbstractString) = replace(replace(String(segment), "~" => "~0"), "/" => "~1")

function pointer_from_segments(segments::AbstractVector{<:AbstractString})
    isempty(segments) && return ""
    escaped = map(escape_json_pointer_segment, segments)
    return "/" * join(escaped, "/")
end

function sanitize_symbol(segment::AbstractString, used::Set{Symbol})
    sanitized = String(segment)
    sanitized = replace(sanitized, r"[^A-Za-z0-9_]" => "_")
    isempty(sanitized) && (sanitized = "_")
    Base.isidentifier(sanitized) || (sanitized = "_" * sanitized)

    candidate = Symbol(sanitized)
    counter = 2
    while candidate in used
        candidate = Symbol(sanitized * "_" * string(counter))
        counter += 1
    end

    return candidate
end

"""
    registry_branches(registry::AbstractDict{<:AbstractString}) -> Vector{String}

Return the distinct JSON Pointer prefixes that represent branches leading
to leaves in the registry. Branches themselves are not leaves (i.e.,
they are strict prefixes).
"""
function registry_branches(registry::AbstractDict{<:AbstractString})
    branches = Set{String}()

    for pointer in keys(registry)
        segments = json_pointer_segments(pointer)
        for i in 1:length(segments)-1
            prefix = pointer_from_segments(segments[1:i])
            push!(branches, prefix)
        end
    end

    return sort!(collect(branches))
end

"""
    validate_registry(registry::AbstractDict{<:AbstractString})

Ensure that no registry leaf pointer is also used as a branch. Throws an
`ArgumentError` when a conflict is found.
"""
function validate_registry(registry::AbstractDict{<:AbstractString})
    branch_list = registry_branches(registry)
    leaf_set = Set(keys(registry))

    for branch in branch_list
        if branch in leaf_set
            throw(ArgumentError("Registry pointer '$branch' cannot be both a leaf and a branch"))
        end
    end

    return nothing
end

function build_registry_tree(registry::AbstractDict{<:AbstractString, <:Function})
    tree = Dict{String, Any}()

    for (pointer, leaf_fn) in registry
        segments = json_pointer_segments(pointer)
        isempty(segments) && throw(ArgumentError("Registry cannot contain root leaf pointer"))
        leaf_fn isa Function || throw(ArgumentError("Leaf for pointer '$pointer' must be callable"))

        node = tree
        for (idx, segment) in enumerate(segments)
            if idx == length(segments)
                haskey(node, segment) && throw(ArgumentError("Duplicate registry pointer '$pointer'"))
                node[segment] = leaf_fn
            else
                child = get!(node, segment) do
                    Dict{String, Any}()
                end

                child isa Dict || throw(ArgumentError("Registry pointer '$pointer' conflicts with existing leaf"))
                node = child
            end
        end
    end

    return tree
end

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
    stove_elements_in_use::Integer = 0
    oven_bays::Integer = 1
    oven_bays_in_use::Integer = 0
    items_cooked::Integer = 0
end

"""
    example_kitchen_registry() -> Dict{String, Any}

Return a dictionary describing leaf values for a sample kitchen registry.

Keys are JSON Pointer strings identifying the leaves. 
Values may be Any type. 
Expected types are callables which may be closures on other data, 
or mutable / referenced data. 
Branches are not represented in the dictionary.
"""
function example_kitchen_registry()

    config = KitchenConfig(stove_elements=4, oven_bays=2);


    registry = Dict{String, Any}(
        "/name" => () -> "My Kitchen",
        "/show_config" => () -> show(config),
        "/return_config" => () -> (return config),
        "/config_value" => config,
        "/stove/cook" => () -> begin
            config.items_cooked+=1;
            "Cooking item number: $(config.items_cooked)"; end,
    )
    validate_registry(registry)
    return registry
end


"""
    registry_to_namedtuples(registry::AbstractDict{<:AbstractString, <:Function}) -> NamedTuple

Convert a registry of JSON Pointer leaf callables into a nested hierarchy
of NamedTuples. Branch nodes are NamedTuples whose fields correspond to
child segment names. Leaf nodes are NamedTuples with a single field
`:leaf` holding the callable.
"""
function registry_to_namedtuples(registry::AbstractDict{<:AbstractString, <:Function})
    validate_registry(registry)
    tree = build_registry_tree(registry)
    return tree_to_namedtuple(tree, String[])
end

function tree_to_namedtuple(tree::Dict{String, Any}, path::Vector{String})
    sorted_segments = sort!(collect(keys(tree)))
    used = Set{Symbol}()
    name_syms = Symbol[]
    values = Any[]

    for segment in sorted_segments
        child = tree[segment]
        sym = sanitize_symbol(segment, used)
        push!(used, sym)
        push!(name_syms, sym)
        child_path = copy(path)
        push!(child_path, segment)
        if child isa Dict{String, Any}
            push!(values, tree_to_namedtuple(child, child_path))
        elseif child isa Dict
            push!(values, tree_to_namedtuple(Dict{String, Any}(child), child_path))
        else
            child isa Function || throw(ArgumentError("Unexpected leaf type for segment '$segment'"))
            pointer = pointer_from_segments(child_path)
            push!(values, NamedTuple{(POINTER_FIELD, LEAF_FIELD)}((pointer, child)))
        end
    end

    names_tuple = Tuple(name_syms)
    values_tuple = Tuple(values)
    return NamedTuple{names_tuple}(values_tuple)
end

"""
    namedtuples_to_registry(hierarchy::NamedTuple) -> Dict{String, Function}

Convert a hierarchy of branch and leaf NamedTuples back into a registry
dictionary keyed by JSON Pointers. Leaf nodes must be NamedTuples with a
single field `:leaf` containing a callable.
"""
function namedtuples_to_registry(hierarchy::NamedTuple)
    registry = Dict{String, Function}()
    collect_namedtuple_registry!(registry, hierarchy)
    validate_registry(registry)
    return registry
end

function collect_namedtuple_registry!(registry::Dict{String, Function}, node::NamedTuple)
    props = propertynames(node)

    if props == (POINTER_FIELD, LEAF_FIELD)
        pointer = getfield(node, POINTER_FIELD)
        pointer isa AbstractString || throw(ArgumentError("Leaf pointers must be strings"))
        pointer = String(pointer)
        pointer == "" && throw(ArgumentError("Leaf pointers cannot be empty"))
        startswith(pointer, "/") || throw(ArgumentError("Leaf pointer '$pointer' must begin with '/'"))
        leaf_fn = getfield(node, LEAF_FIELD)
        leaf_fn isa Function || throw(ArgumentError("Leaf at pointer '$pointer' must be callable"))
        registry[pointer] = leaf_fn
        return
    end

    if POINTER_FIELD in props || LEAF_FIELD in props
        throw(ArgumentError("Node containing both metadata and branches is invalid"))
    end

    for name in props
        child = getfield(node, name)
        child isa NamedTuple || throw(ArgumentError("Branch children must be NamedTuples"))
        collect_namedtuple_registry!(registry, child)
    end
end

struct MenuLeaf{V}
    pointer::String
    value::V
end

is_leaf_callable(leaf::MenuLeaf) = leaf.value isa Function

function (leaf::MenuLeaf)(args...; kwargs...)
    val = leaf.value
    if val isa Function
        return val(args...; kwargs...)
    elseif isempty(args) && isempty(kwargs)
        return val
    else
        throw(ArgumentError("Leaf at pointer '$(leaf.pointer)' is not callable"))
    end
end

Base.show(io::IO, leaf::MenuLeaf) = print(io, "MenuLeaf(", leaf.pointer, ")")

struct MenuBranch
    pointer::String
    order::Vector{Symbol}
    children::Dict{Symbol, Any}
    segment_lookup::Dict{Symbol, String}
end

const MenuNode = Union{MenuBranch, MenuLeaf}

function Base.propertynames(branch::MenuBranch, private::Bool=false)
    if private
        return (fieldnames(MenuBranch)...,)
    end
    return Tuple(branch.order)
end

function Base.getproperty(branch::MenuBranch, name::Symbol)
    if name === :pointer || name === :order || name === :children || name === :segment_lookup
        return getfield(branch, name)
    end
    if haskey(branch.children, name)
        return branch.children[name]
    end
    return getfield(branch, name)
end

function Base.show(io::IO, branch::MenuBranch)
    pointer = isempty(branch.pointer) ? "/" : branch.pointer
    choices = map(branch.order) do sym
        label = branch.segment_lookup[sym]
        child = branch.children[sym]
        if child isa MenuLeaf && is_leaf_callable(child)
            return string(label, "()")
        else
            return label
        end
    end
    print(io, "MenuBranch(", pointer, "; choices=[", join(choices, ", "), "])")
end

"""
    registry_to_menu(registry::AbstractDict{<:AbstractString, <:Function}) -> MenuBranch

Render a registry of JSON Pointer callables into a hierarchy of
`MenuBranch` and `MenuLeaf` nodes optimised for REPL exploration.
"""
function registry_to_menu(registry::AbstractDict{<:AbstractString, <:Function})
    validate_registry(registry)
    tree = build_registry_tree(registry)
    return tree_to_menu_branch(tree, String[])
end

function tree_to_menu_branch(tree::Dict{String, Any}, path::Vector{String})
    branch_pointer = pointer_from_segments(path)
    sorted_segments = sort!(collect(keys(tree)))
    reserved = Set(fieldnames(MenuBranch))
    used = copy(reserved)
    order = Symbol[]
    children = Dict{Symbol, Any}()
    segment_lookup = Dict{Symbol, String}()

    for segment in sorted_segments
        sym = sanitize_symbol(segment, used)
        push!(used, sym)
        push!(order, sym)
        segment_lookup[sym] = segment
        child = tree[segment]
        child_path = copy(path)
        push!(child_path, segment)
        if child isa Dict{String, Any}
            children[sym] = tree_to_menu_branch(child, child_path)
        elseif child isa Dict
            children[sym] = tree_to_menu_branch(Dict{String, Any}(child), child_path)
        else
            child isa Function || throw(ArgumentError("Leaf for pointer '$(pointer_from_segments(child_path))' must be callable"))
            children[sym] = MenuLeaf(pointer_from_segments(child_path), child)
        end
    end

    return MenuBranch(branch_pointer, order, children, segment_lookup)
end

"""
    menu_to_registry(menu::MenuBranch) -> Dict{String, Function}

Collapse a `MenuBranch` hierarchy back into the flat registry mapping
JSON Pointer strings to callables.
"""
function menu_to_registry(menu::MenuBranch)
    registry = Dict{String, Function}()
    collect_menu_registry!(registry, menu)
    validate_registry(registry)
    return registry
end

function collect_menu_registry!(registry::Dict{String, Function}, leaf::MenuLeaf)
    val = leaf.value
    is_leaf_callable(leaf) || throw(ArgumentError("Leaf at pointer '$(leaf.pointer)' must be callable"))
    registry[leaf.pointer] = val
end

function collect_menu_registry!(registry::Dict{String, Function}, branch::MenuBranch)
    for name in branch.order
        child = branch.children[name]
        collect_menu_registry!(registry, child)
    end
end

end # module

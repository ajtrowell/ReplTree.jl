module REPLTrees

export json_pointer_segments,
       registry_branches,
       validate_registry,
       example_cat_registry,
       registry_to_namedtuples,
       namedtuples_to_registry

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
    registry_to_namedtuples(registry::AbstractDict{<:AbstractString, <:Function}) -> NamedTuple

Convert a registry of JSON Pointer leaf callables into a nested hierarchy
of NamedTuples. Branch nodes are NamedTuples whose fields correspond to
child segment names. Leaf nodes are NamedTuples with a single field
`:leaf` holding the callable.
"""
function registry_to_namedtuples(registry::AbstractDict{<:AbstractString, <:Function})
    validate_registry(registry)

    tree = Dict{String, Any}()

    for (pointer, leaf_fn) in registry
        segments = json_pointer_segments(pointer)
        isempty(segments) && throw(ArgumentError("Registry cannot contain root leaf pointer"))

        node = tree
        for (idx, segment) in enumerate(segments)
            if idx == length(segments)
                haskey(node, segment) && throw(ArgumentError("Duplicate registry pointer '$pointer'"))
                leaf_fn isa Function || throw(ArgumentError("Leaf for pointer '$pointer' must be callable"))
                node[segment] = NamedTuple{(POINTER_FIELD, LEAF_FIELD)}((pointer, leaf_fn))
            else
                child = get!(node, segment) do
                    Dict{String, Any}()
                end

                child isa Dict || throw(ArgumentError("Registry pointer '$pointer' conflicts with existing leaf"))
                node = child
            end
        end
    end

    return tree_to_namedtuple(tree)
end

function tree_to_namedtuple(tree::Dict{String, Any})
    segments = sort!(collect(keys(tree)))
    used = Set{Symbol}()
    name_syms = Symbol[]
    values = Any[]

    for segment in segments
        child = tree[segment]
        sym = sanitize_symbol(segment, used)
        push!(used, sym)
        push!(name_syms, sym)
        if child isa Dict{String, Any}
            push!(values, tree_to_namedtuple(child))
        elseif child isa Dict
            push!(values, tree_to_namedtuple(Dict{String, Any}(child)))
        else
            child isa NamedTuple || throw(ArgumentError("Unexpected node type for segment '$segment'"))
            push!(values, child)
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

end # module

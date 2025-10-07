"""
    registry_to_namedtuples(registry::AbstractDict{<:AbstractString, <:Function}) -> NamedTuple

Convert a registry of JSON Pointer leaf callables into a nested hierarchy
of NamedTuples. Branch nodes are NamedTuples whose fields correspond to
child segment names. Leaf nodes are NamedTuples with a single field
`:leaf` holding the callable.
"""
function registry_to_namedtuples(registry::AbstractDict{<:AbstractString, <:Function})
    validate_registry(registry)
    tree = build_registry_tree(registry; require_callable=true)
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

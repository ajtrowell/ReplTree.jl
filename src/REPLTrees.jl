module REPLTrees

export json_pointer_segments, example_cat_registry, registry_branches, validate_registry

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
            prefix = "/" * join(segments[1:i], "/")
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
    )
    validate_registry(registry)
    return registry
end

end # module

module REPLTrees

export json_pointer_segments, example_cat_registry

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
    example_cat_registry() -> Dict{String, Function}

Return a dictionary describing leaf values for a sample cat registry.

Keys are JSON Pointer strings identifying the leaves, and values are
zero-argument callables producing the associated leaf data. Branches are
not represented in the dictionary.
"""
function example_cat_registry()
    return Dict{String, Function}(
        "/name" => () -> "Whiskers",
        "/appearance/color" => () -> "tabby",
        "/appearance/eye-color" => () -> "green",
        "/stats/age" => () -> 4,
        "/stats/is-indoor" => () -> true,
        "/behavior/favorite-toy" => () -> "feather wand",
        "/behavior/nap-length-minutes" => () -> 25,
    )
end

end # module

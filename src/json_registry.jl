using JSON3

"""
    generate_registry_from_json(json_data, callback::Function) -> Dict{String, Any}

Traverse `json_data`, collect every scalar leaf, and return a registry
mapping JSON Pointer strings to the result of `callback(pointer)`.

`json_data` should be a `JSON3.Object` or `JSON3.Array`. Branch pointers
are constructed according to RFC 6901, with array indices encoded as
zero-based decimal strings.

Throws an `ArgumentError` when the root value is a scalar, since
registries cannot contain a root leaf pointer.
"""
function generate_registry_from_json(json_data::Union{JSON3.Object, JSON3.Array}, callback::Function)::Dict{String, Any}
    registry = Dict{String, Any}()
    collect_json_leaves!(registry, json_data, callback, String[])
    return registry
end

function generate_registry_from_json(json_data, ::Function)
    throw(ArgumentError("json_data must be a JSON3.Object or JSON3.Array"))
end

function collect_json_leaves!(registry::Dict{String, Any}, node::JSON3.Object, callback::Function, segments::Vector{String})
    for (key, value) in pairs(node)
        push!(segments, string(key))
        collect_json_leaves!(registry, value, callback, segments)
        pop!(segments)
    end
    return registry
end

function collect_json_leaves!(registry::Dict{String, Any}, node::JSON3.Array, callback::Function, segments::Vector{String})
    index = 0
    for value in node
        push!(segments, string(index))
        collect_json_leaves!(registry, value, callback, segments)
        pop!(segments)
        index += 1
    end
    return registry
end

function collect_json_leaves!(registry::Dict{String, Any}, node, callback::Function, segments::Vector{String})
    pointer = pointer_from_segments(segments)
    pointer == "" && throw(ArgumentError("JSON root value must be an object or array"))
    registry[pointer] = callback(pointer)
    return registry
end

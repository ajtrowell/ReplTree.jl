module ReplTree

export json_pointer_segments,
       registry_branches,
       validate_registry,
       example_cat_registry,
       example_kitchen_registry,
       example_dishwasher_registry,
       example_kitchen_combo_registry,
       MenuBranch,
       registry_to_menu,
       menu_to_registry,
       merge_registry,
       merge_registry!,
       view_struct,
       child_pointer


include("utilities.jl")

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

function build_registry_tree(registry::AbstractDict{<:AbstractString}; require_callable::Bool=true)
    tree = Dict{String, Any}()

    for (pointer, leaf_value) in registry
        segments = json_pointer_segments(pointer)
        isempty(segments) && throw(ArgumentError("Registry cannot contain root leaf pointer"))
        if require_callable && !(leaf_value isa Function)
            throw(ArgumentError("Leaf for pointer '$pointer' must be callable"))
        end

        node = tree
        for (idx, segment) in enumerate(segments)
            if idx == length(segments)
                haskey(node, segment) && throw(ArgumentError("Duplicate registry pointer '$pointer'"))
                node[segment] = leaf_value
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

function prefixed_registry(branch_pointer::AbstractString, registry::AbstractDict{<:AbstractString})
    branch_segments = branch_pointer == "" ? String[] : json_pointer_segments(branch_pointer)
    result = Dict{String, Any}()

    for (pointer, value) in registry
        leaf_segments = pointer == "" ? String[] : json_pointer_segments(pointer)
        combined_segments = String[]
        append!(combined_segments, branch_segments)
        append!(combined_segments, leaf_segments)
        combined_pointer = pointer_from_segments(combined_segments)
        result[combined_pointer] = value
    end

    return result
end

"""
merge_registry(base, branch_pointer, additions)

Return a new registry or menu with `additions` merged under the
`branch_pointer` path of `base`. The original `base` is left unchanged.
"""
function merge_registry end

function merge_registry(base::AbstractDict{<:AbstractString}, branch_pointer::AbstractString,
                        additions::AbstractDict{<:AbstractString})
    branch_pointer = normalize_branch_pointer(branch_pointer)
    merged = Dict{String, Any}()
    for (pointer, value) in base
        merged[String(pointer)] = value
    end
    merge_registry!(merged, branch_pointer, additions)
    return merged
end

merge_registry(base::AbstractDict{<:AbstractString}, additions::AbstractDict{<:AbstractString}) =
    merge_registry(base, "/", additions)


"""
merge_registry!(base, branch_pointer, additions)

Mutate `base` by merging `additions` under `branch_pointer`. Throws when
conflicts with existing leaves are detected.
"""
function merge_registry! end

function merge_registry!(base::Dict{String, Any}, branch_pointer::AbstractString,
                         additions::AbstractDict{<:AbstractString})
    branch_pointer = normalize_branch_pointer(branch_pointer)
    branch_pointer == "" || startswith(branch_pointer, "/") ||
        throw(ArgumentError("Branch pointer must be empty or begin with '/'"))

    if branch_pointer != "" && haskey(base, branch_pointer)
        throw(ArgumentError("Cannot merge into pointer '$branch_pointer' because it is already a leaf"))
    end

    prefixed = prefixed_registry(branch_pointer, additions)

    for pointer in keys(prefixed)
        if haskey(base, pointer)
            throw(ArgumentError("Registry already contains pointer '$pointer'"))
        end
    end

    candidate = Dict{String, Any}(base)
    for (pointer, value) in prefixed
        candidate[pointer] = value
    end
    validate_registry(candidate)

    for (pointer, value) in prefixed
        base[pointer] = value
    end

    return base
end

merge_registry!(base::Dict{String, Any}, additions::AbstractDict{<:AbstractString}) =
    merge_registry!(base, "/", additions)


include("namedtuple_conversions.jl")

"""
    MenuBranch

Represents a branch node in the REPL menu hierarchy.

- `pointer`: Absolute JSON Pointer string for the branch.
- `order`: Symbols used to expose ordered field access in the REPL (for
  tab completion and display).
- `children`: Mapping from sanitized symbols to child nodes (either
  nested `MenuBranch`es or raw leaf values).
- `segment_lookup`: Mapping from sanitized symbols back to their original
  JSON Pointer path segments.
"""
mutable struct MenuBranch
    pointer::String
    order::Vector{Symbol}
    children::Dict{Symbol, Any}
    segment_lookup::Dict{Symbol, String}
end

is_leaf_callable(value) = value isa Function

"""
    child_pointer(branch::MenuBranch, name::Symbol) -> String

Return the absolute JSON Pointer string for the child identified by
`name` within `branch`.
"""
function child_pointer(branch::MenuBranch, name::Symbol)
    haskey(branch.segment_lookup, name) || throw(KeyError(name))
    segments = branch.pointer == "" ? String[] : copy(json_pointer_segments(branch.pointer))
    push!(segments, branch.segment_lookup[name])
    return pointer_from_segments(segments)
end

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
        if child isa MenuBranch
            return string(label, ".")
        elseif is_leaf_callable(child)
            return string(label, "()")
        else
            return label
        end
    end
    print(io, "MenuBranch(", pointer, "; choices=[", join(choices, ", "), "])")
end

"""
    registry_to_menu(registry::AbstractDict{<:AbstractString}) -> MenuBranch

Render a registry of JSON Pointer callables into a hierarchy of
`MenuBranch` nodes with raw leaf values optimised for REPL exploration.
"""
function registry_to_menu(registry::AbstractDict{<:AbstractString})
    validate_registry(registry)
    tree = build_registry_tree(registry; require_callable=false)
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
            children[sym] = child
        end
    end

    return MenuBranch(branch_pointer, order, children, segment_lookup)
end

"""
    menu_to_registry(menu::MenuBranch) -> Dict{String, Any}

Collapse a `MenuBranch` hierarchy back into the flat registry mapping
JSON Pointer strings to the underlying leaf values.
"""
function menu_to_registry(menu::MenuBranch)
    registry = menu_to_any_registry(menu)
    validate_registry(registry)
    return registry
end

function menu_to_any_registry(menu::MenuBranch)
    registry = Dict{String, Any}()
    collect_menu_values!(registry, menu)
    return registry
end

function collect_menu_values!(registry::Dict{String, Any}, branch::MenuBranch)
    for name in branch.order
        child = branch.children[name]
        if child isa MenuBranch
            collect_menu_values!(registry, child)
        else
            pointer = child_pointer(branch, name)
            registry[pointer] = child
        end
    end
end

function relative_menu_registry(branch::MenuBranch)
    absolute = menu_to_registry(branch)
    branch.pointer == "" && return absolute

    prefix_segments = json_pointer_segments(branch.pointer)
    relative = Dict{String, Any}()

    for (pointer, value) in absolute
        segments = json_pointer_segments(pointer)
        length(segments) > length(prefix_segments) ||
            throw(ArgumentError("Leaf pointer '$pointer' is not a descendant of branch pointer '$(branch.pointer)'"))

        if segments[1:length(prefix_segments)] != prefix_segments
            throw(ArgumentError("Leaf pointer '$pointer' is not a descendant of branch pointer '$(branch.pointer)'"))
        end

        relative_segments = segments[length(prefix_segments)+1:end]
        isempty(relative_segments) &&
            throw(ArgumentError("Leaf pointer '$pointer' cannot match branch pointer '$(branch.pointer)'"))

        relative_pointer = pointer_from_segments(relative_segments)
        relative[relative_pointer] = value
    end

    return relative
end

function merge_registry(menu::MenuBranch, branch_pointer::AbstractString,
                        additions::AbstractDict{<:AbstractString})
    branch_pointer = normalize_branch_pointer(branch_pointer)
    base_registry = menu_to_any_registry(menu)
    merged_registry = merge_registry(base_registry, branch_pointer, additions)
    return registry_to_menu(merged_registry)
end

function merge_registry(menu::MenuBranch, branch_pointer::AbstractString,
                        additions::MenuBranch)
    additions_registry = relative_menu_registry(additions)
    return merge_registry(menu, branch_pointer, additions_registry)
end

merge_registry(menu::MenuBranch, additions::AbstractDict{<:AbstractString}) =
    merge_registry(menu, "/", additions)

merge_registry(menu::MenuBranch, additions::MenuBranch) =
    merge_registry(menu, "/", additions)

function merge_registry!(menu::MenuBranch, branch_pointer::AbstractString,
                         additions::AbstractDict{<:AbstractString})
    branch_pointer = normalize_branch_pointer(branch_pointer)
    base_registry = menu_to_any_registry(menu)
    merge_registry!(base_registry, branch_pointer, additions)
    merged_menu = registry_to_menu(base_registry)
    menu.pointer = merged_menu.pointer
    menu.order = merged_menu.order
    menu.children = merged_menu.children
    menu.segment_lookup = merged_menu.segment_lookup
    return menu
end

merge_registry!(menu::MenuBranch, additions::AbstractDict{<:AbstractString}) =
    merge_registry!(menu, "/", additions)

function merge_registry!(menu::MenuBranch, branch_pointer::AbstractString,
                         additions::MenuBranch)
    additions_registry = relative_menu_registry(additions)
    return merge_registry!(menu, branch_pointer, additions_registry)
end

merge_registry!(menu::MenuBranch, additions::MenuBranch) =
    merge_registry!(menu, "/", additions)

normalize_branch_pointer(pointer::AbstractString) = pointer == "/" ? "" : pointer

include("examples.jl")

end # module

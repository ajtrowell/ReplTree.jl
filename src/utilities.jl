
"""
    Display field names and values of given struct
"""
view_struct  = (dw) -> foreach(name -> println("$(name) = $(getfield(dw, name))"), fieldnames(typeof(dw)))


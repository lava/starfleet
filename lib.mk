head = $(firstword $(1))
tail = $(wordlist 2,$(words $(1)),$(1))

define newline


endef

# index-of(x, lst): Returns the (1-based) index of x in lst
#  - If x occurs multiple times, returns the index of the first occurence 
index-of = $(words \
    $(if $(findstring $(1),$(firstword $(2))),\
	     x,\
	     x $(call index-of,$(1),$(call tail,$(2)))))


# _each-with-index(lst, acc, body)
_each-with-index = $(if $(1), \
 	$(subst __index__,$(words $(2)), $(subst __value__,$(call head,$(1)), $(3)))$(newline) \
 	$(call _each-with-index,$(call tail,$(1)),x $(2),$(3)))

# each-with-index(lst, body)
#  - Insert one copy of body, with the keywords __index__ and __value__
#    replaced by by the indices and values of the elements of lst 
each-with-index = $(call _each-with-index,$(1),x,$(2))


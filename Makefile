.PHONY: all syntax-check

LUAC?=luac

all: syntax-check

syntax-check:
	$(LUAC) -p $$(find . -name \*.lua) 

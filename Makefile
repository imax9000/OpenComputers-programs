.PHONY: all syntax-check upload

LUAC?=luac

all: upload

syntax-check:
	$(LUAC) -p $$(find . -name \*.lua) 

upload: syntax-check
	gist --update https://gist.github.com/a7ad2eeb75feba5e368717b828296323 \
		$$(find . -name \*.lua)

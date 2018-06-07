SRC  := $(wildcard iso-*.adoc)
DOC  := $(patsubst %.adoc,%.doc,$(SRC))
XML  := $(patsubst %.adoc,%.xml,$(SRC))
HTML := $(patsubst %.adoc,%.html,$(SRC))

SHELL := /bin/bash

all: $(HTML) $(XML) $(DOC)

clean:
	rm -f $(HTML) $(DOC) $(XML) Gemfile Gemfile.lock

clean-html:
	rm -f $(HTML)

bundle:	Gemfile Gemfile.lock
	bundle

Gemfile Gemfile.lock:
	ln -s ../common/$@ .

%.xml %.html %.doc:	%.adoc | bundle
	bundle exec metanorma -t iso $^

html: clean-html $(HTML)

open:
	open $(HTML)

.PHONY: bundle all open

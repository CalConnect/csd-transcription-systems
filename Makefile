#!make
SHELL := /bin/bash
# Ensure the xml2rfc cache directory exists locally
IGNORE := $(shell mkdir -p $(HOME)/.cache/xml2rfc)

SRC := $(shell yq r metanorma.yml metanorma.source.files | cut -d ' ' -f 2 | tr -s '\n' ' ')

ifeq ($(SRC),null)
SRC :=
endif
ifeq ($(SRC),ll)
SRC :=
endif

ifeq ($(SRC),)
BUILT := $(shell yq r metanorma.yml metanorma.source.built_targets | cut -d ':' -f 1 | tr -s '\n' ' ')

ifeq ($(BUILT),null)
SRC :=
endif
ifeq ($(BUILT),ll)
SRC :=
endif

ifeq ($(BUILT),)
SRC := $(filter-out README.adoc, $(wildcard sources/*.adoc))
else
XML := $(patsubst sources/%,documents/%,$(BUILT))
endif
endif

CSV_SRC      := $(wildcard sources/data/*.csv)
DERIVED_YAML := $(patsubst %.csv,%.yaml,$(CSV_SRC))

SUPPLEMENTARY_SRC := $(DERIVED_YAML)

FORMATS := $(shell yq r metanorma.yml metanorma.formats | tr -d '[:space:]' | tr -s '-' ' ')
ifeq ($(FORMATS),)
FORMAT_MARKER := mn-output-
FORMATS := $(shell grep "$(FORMAT_MARKER)" $(SRC) | cut -f 2 -d " " | tr "," "\\n" | sort | uniq | tr "\\n" " ")
endif

XML  ?= $(patsubst sources/%,documents/%,$(patsubst %.adoc,%.xml,$(SRC)))
HTML := $(patsubst %.xml,%.html,$(XML))

ifdef METANORMA_DOCKER
  PREFIX_CMD := echo "Running via docker..."; docker run -v "$$(pwd)":/metanorma/ $(METANORMA_DOCKER)
else
  PREFIX_CMD := echo "Running locally..."; bundle exec
endif

_OUT_FILES := $(foreach FORMAT,$(FORMATS),$(shell echo $(FORMAT) | tr '[:lower:]' '[:upper:]'))
OUT_FILES  := $(foreach F,$(_OUT_FILES),$($F))

define print_vars
	$(info "src $(SRC)")
	$(info "xml $(XML)")
	$(info "formats $(FORMATS)")
endef

all: documents.html
	$(call print_vars)

scripts/csv2yaml:
	git clone https://github.com/riboseinc/csv2yaml
	mkdir -p $@
	cp -a csv2yaml/exe/* $@/

%.yaml: %.csv |	scripts/csv2yaml
	scripts/csv2yaml/structured_csv_to_yaml.rb $^

documents:
	mkdir -p $@

documents/%.html: documents/%.xml $(SUPPLEMENTARY_SRC) | documents
	${PREFIX_CMD} metanorma $<

documents/%.xml: sources/%.xml $(SUPPLEMENTARY_SRC) | documents
	mkdir -p $(dir $@)
	mv $< $@

# Build canonical XML output
# If XML file is provided, copy it over
# Otherwise, build the xml using adoc
sources/%.xml: | bundle
	BUILT_TARGET="$(shell yq r metanorma.yml metanorma.source.built_targets[$@])"; \
	if [ "$$BUILT_TARGET" = "" ] || [ "$$BUILT_TARGET" = "null" ]; then \
		BUILT_TARGET=$@; \
		$(PREFIX_CMD) metanorma -x xml "$${BUILT_TARGET//xml/adoc}"; \
	else \
		if [ -f "$$BUILT_TARGET" ] && [ "$${BUILT_TARGET##*.}" == "xml" ]; then \
			cp "$$BUILT_TARGET" $@; \
		else \
			$(PREFIX_CMD) metanorma -x xml $$BUILT_TARGET; \
			cp "$${BUILT_TARGET//adoc/xml}" $@; \
		fi \
	fi

documents.rxl: $(XML) $(HTML)
	${PREFIX_CMD} relaton concatenate \
	  -t "$(shell yq r metanorma.yml relaton.collection.name)" \
		-g "$(shell yq r metanorma.yml relaton.collection.organization)" \
		documents $@

documents.html: documents.rxl
	$(PREFIX_CMD) relaton xml2html documents.rxl

%.adoc:

define FORMAT_TASKS
OUT_FILES-$(FORMAT) := $($(shell echo $(FORMAT) | tr '[:lower:]' '[:upper:]'))

open-$(FORMAT):
	open $$(OUT_FILES-$(FORMAT))

clean-$(FORMAT):
	rm -f $$(OUT_FILES-$(FORMAT))

$(FORMAT): clean-$(FORMAT) $$(OUT_FILES-$(FORMAT))

.PHONY: clean-$(FORMAT)

endef

$(foreach FORMAT,$(FORMATS),$(eval $(FORMAT_TASKS)))

open: open-html

clean:
	rm -rf documents documents.{html,rxl} published *_images $(OUT_FILES)

bundle:
ifndef METANORMA_DOCKER
	bundle install --jobs 4 --retry 3
endif
	$(call print_vars)

.PHONY: bundle all open clean

#
# Watch-related jobs
#

.PHONY: watch serve watch-serve

NODE_BINS          := onchange live-serve run-p
NODE_BIN_DIR       := node_modules/.bin
NODE_PACKAGE_PATHS := $(foreach PACKAGE_NAME,$(NODE_BINS),$(NODE_BIN_DIR)/$(PACKAGE_NAME))

$(NODE_PACKAGE_PATHS): package.json
	npm i

watch: $(NODE_BIN_DIR)/onchange
	make all
	$< $(ALL_SRC) -- make all

define WATCH_TASKS
watch-$(FORMAT): $(NODE_BIN_DIR)/onchange
	make $(FORMAT)
	$$< $$(SRC_$(FORMAT)) -- make $(FORMAT)

.PHONY: watch-$(FORMAT)
endef

$(foreach FORMAT,$(FORMATS),$(eval $(WATCH_TASKS)))

serve: $(NODE_BIN_DIR)/live-server revealjs-css reveal.js
	export PORT=$${PORT:-8123} ; \
	port=$${PORT} ; \
	for html in $(HTML); do \
		$< --entry-file=$$html --port=$${port} --ignore="*.html,*.xml,Makefile,Gemfile.*,package.*.json" --wait=1000 & \
		port=$$(( port++ )) ;\
	done

watch-serve: $(NODE_BIN_DIR)/run-p
	$< watch serve

#
# Deploy jobs
#

publish: published

published: documents.html
	mkdir -p $@ && \
	cp -a documents $@/ && \
	cp $< $@/index.html;

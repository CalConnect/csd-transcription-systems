#!make
SHELL := /bin/bash
# Ensure the xml2rfc cache directory exists locally
IGNORE := $(shell mkdir -p $(HOME)/.cache/xml2rfc)

# Detect number of cores (e.g. for bundle install)
ifeq ($(OS),Windows_NT)
	CORES := $(shell nproc --all)
else
	UNAME_S := $(shell uname -s)

	ifeq ($(UNAME_S),Linux)
		CORES := $(shell grep -c '^$' /proc/cpuinfo)
	endif

	ifeq ($(UNAME_S),Darwin)
		CORES := $(shell sysctl -n hw.ncpu)
	endif

	ifeq ($(UNAME_S),FreeBSD)
		CORES := $(shell sysctl -n hw.ncpu)
	endif
endif

TEMP_BUILD_DIR := temp_build

SRC := $(shell yq e .metanorma.source.files metanorma.yml | cut -d ' ' -f 2 | tr -s '\n' ' ')

ifeq ($(SRC),null)
SRC :=
endif
ifeq ($(SRC),ll)
SRC :=
endif

SRC := $(filter-out README.adoc, $(wildcard sources/*.adoc))

ALL_ADOC_SRC := $(wildcard sources/sections*/*.adoc)
CSV_SRC      := $(wildcard sources/data/*.csv)
DERIVED_YAML := $(patsubst %.csv,%.yaml,$(CSV_SRC))

SUPPLEMENTARY_SRC := $(ALL_ADOC_SRC) $(DERIVED_YAML)

FORMAT_MARKER := mn-output-
FORMATS := $(shell grep "$(FORMAT_MARKER)" $(SRC) | cut -f 2 -d " " | tr "," "\\n" | sort | uniq | tr "\\n" " ")

HTML  ?= $(patsubst sources/%,documents/%,$(patsubst %.adoc,%.html,$(SRC)))

_OUT_FILES := $(foreach FORMAT,$(FORMATS),$(shell echo $(FORMAT) | tr '[:lower:]' '[:upper:]'))
OUT_FILES  := $(foreach F,$(_OUT_FILES),$($F))

OUT_DIR := site

define print_vars
	$(info "DERIVED_YAML $(DERIVED_YAML)")
	$(info "src $(SRC)")
	$(info "formats $(FORMATS)")
endef

.PHONY: all
all: documents.html debug

.PHONY: debug
debug:
	$(call print_vars)

scripts/csv2yaml:
	if [[ -d $(TEMP_BUILD_DIR)/csv2yaml ]]; then \
		pushd $(TEMP_BUILD_DIR)/csv2yaml && git fetch && git reset --hard origin/master && popd; \
	else \
		git clone --depth 1 https://github.com/riboseinc/csv2yaml $(TEMP_BUILD_DIR)/csv2yaml; \
	fi
	mkdir -p $@
	cp -a $(TEMP_BUILD_DIR)/csv2yaml/exe/* $@/

%.yaml: %.csv |	scripts/csv2yaml
	scripts/csv2yaml/structured_csv_to_yaml.rb $^
	sed -i.bkup -e $$'1 i\\\n# This is a generated file.  Do not edit it!' $@
	sed -i.bkup -e $$'2 i\\\n# Edit the corresponding csv file \($^\) instead.' $@
	sed -i.bkup -e $$'3 i\\\n# This file is generated by https://github.com/riboseinc/csv2yaml' $@
	sed -i.bkup -e $$'4 i\\\n# Please check in this file.' $@

documents:
	mkdir -p $@

documents.html: metanorma.yml $(SUPPLEMENTARY_SRC) | documents
	metanorma site generate . -c metanorma.yml

define FORMAT_TASKS
OUT_FILES-$(FORMAT) := $($(shell echo $(FORMAT) | tr '[:lower:]' '[:upper:]'))

.PHONY: open-$(FORMAT)
open-$(FORMAT):
	open $$(OUT_FILES-$(FORMAT))

.PHONY: clean-$(FORMAT)
clean-$(FORMAT):
	rm -f $$(OUT_FILES-$(FORMAT))

.PHONY: $(FORMAT)
$(FORMAT): clean-$(FORMAT) $$(OUT_FILES-$(FORMAT))

endef

$(foreach FORMAT,$(FORMATS),$(eval $(FORMAT_TASKS)))

.PHONY: open
open: open-html

.PHONY: clean
clean:
	rm -rf documents documents.{html,rxl} $(OUT_DIR) *_images $(OUT_FILES)

.PHONY: test
test:
	scripts/run_tests

#
# Watch-related jobs
#

NODE_BINS          := onchange live-serve run-p
NODE_BIN_DIR       := node_modules/.bin
NODE_PACKAGE_PATHS := $(foreach PACKAGE_NAME,$(NODE_BINS),$(NODE_BIN_DIR)/$(PACKAGE_NAME))

$(NODE_PACKAGE_PATHS): package.json
	npm i

.PHONY: watch
watch: $(NODE_BIN_DIR)/onchange
	make all
	$< $(ALL_SRC) -- make all

define WATCH_TASKS
.PHONY: watch-$(FORMAT)
watch-$(FORMAT): $(NODE_BIN_DIR)/onchange
	make $(FORMAT)
	$$< $$(SRC_$(FORMAT)) -- make $(FORMAT)

endef

$(foreach FORMAT,$(FORMATS),$(eval $(WATCH_TASKS)))

.PHONY: serve
serve: $(NODE_BIN_DIR)/live-server revealjs-css reveal.js
	export PORT=$${PORT:-8123} ; \
	port=$${PORT} ; \
	for html in $(HTML); do \
		$< --entry-file=$$html --port=$${port} --ignore="*.html,*.xml,Makefile,Gemfile.*,package.*.json" --wait=1000 & \
		port=$$(( port++ )) ;\
	done

.PHONY: watch-serve
watch-serve: $(NODE_BIN_DIR)/run-p
	$< watch serve

#
# Deploy jobs
#

.PHONY: publish
publish: $(OUT_DIR)

$(OUT_DIR): documents.html
	mkdir -p $@ && \
	cp -a documents $@/ && \
	cp $< $@/index.html;

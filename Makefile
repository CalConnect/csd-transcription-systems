#!make
SHELL := /bin/bash
# Ensure the xml2rfc cache directory exists locally
IGNORE := $(shell mkdir -p $(HOME)/.cache/xml2rfc)

TEMP_BUILD_DIR := temp_build

SRC := $(shell yq e .metanorma.source.files metanorma.yml | cut -d ' ' -f 2 | tr -s '\n' ' ')

ifeq ($(SRC),null)
SRC :=
endif
ifeq ($(SRC),ll)
SRC :=
endif

ifeq ($(SRC),)
BUILT := $(shell yq e .metanorma.source.built_targets metanorma.yml | cut -d ':' -f 1 | tr -s '\n' ' ')

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

ALL_ADOC_SRC := $(wildcard sources/sections*/*.adoc)
CSV_SRC      := $(wildcard sources/data/*.csv)
DERIVED_YAML := $(patsubst %.csv,%.yaml,$(CSV_SRC))

SUPPLEMENTARY_SRC := $(ALL_ADOC_SRC) $(DERIVED_YAML)

FORMATS := $(shell yq e .metanorma.formats metanorma.yml | tr -d '[:space:]' | tr -s '-' ' ')
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
	$(info "DERIVED_YAML $(DERIVED_YAML)")
	$(info "src $(SRC)")
	$(info "xml $(XML)")
	$(info "formats $(FORMATS)")
endef

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

documents/%.html: documents/%.xml $(SUPPLEMENTARY_SRC) | documents
	${PREFIX_CMD} metanorma $<

documents/%.xml: sources/%.xml $(SUPPLEMENTARY_SRC) | documents
	mkdir -p $(dir $@)
	mv $< $@

# Build canonical XML output
# If XML file is provided, copy it over
# Otherwise, build the xml using adoc
sources/%.xml: | bundle
	BUILT_TARGET="$(shell yq e .metanorma.source.built_targets[$@] metanorma.yml)"; \
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
	  -t "$(shell yq e .relaton.collection.name metanorma.yml)" \
		-g "$(shell yq e .relaton.collection.organization metanorma.yml)" \
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

run-bundle:
ifndef METANORMA_DOCKER
	bundle install --jobs 4 --retry 3
endif

bundle: run-bundle debug

.PHONY: bundle all open clean


.PHONY: test
test:
	scripts/run_tests


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

.PHONY: hack-update-metanorma
hack-update-metanorma:
	for u in "https://github.com/metanorma/metanorma-iso" \
		"https://github.com/metanorma/metanorma-standoc" \
		"https://github.com/metanorma/isodoc"; \
	do \
		reponame="$${u##*/}"; \
		if [[ -d "$(TEMP_BUILD_DIR)/$$reponame" ]]; then \
			pushd "$(TEMP_BUILD_DIR)/$$reponame" && git fetch && git reset --hard origin/master && popd; \
		else \
			git clone --depth 1 "$$u" "$(TEMP_BUILD_DIR)/$$reponame"; \
		fi && \
		pushd "$(TEMP_BUILD_DIR)/$$reponame" && \
		gem build "$${reponame}" && \
		gem install *gem; \
		set -- *gem; \
		gemversion="$${1%.gem}" ; \
		gemversion="$${gemversion#$${reponame}-}" ; \
		echo reponame is $${reponame} ; \
		echo gemversion is "$${gemversion}" ; \
		sed -i.bkup -e 's/\('"$${reponame}"'\) ([0-9].*)/\1 ('"$${gemversion}"')/g' /setup/Gemfile.lock ; \
		popd ; \
	done

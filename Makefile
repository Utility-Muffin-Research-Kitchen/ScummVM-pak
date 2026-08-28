# ScummVM content pak for Leaf.
#
# A clean clone of this repository plus Docker, make, and python3 is the whole
# toolchain. Nothing here reaches outside the repository: no sibling checkouts,
# no UMRK workspace layout, no locally built images. If a target of yours needs
# a path starting with ../, it does not belong in this file.
#
#   make core           build the pinned ScummVM libretro core (long; cached)
#   make package-mlp1   assemble build/package/ScummVM.pak
#   make dist-pakrat    zip it into build/dist/ScummVM.mlp1.pak.zip
#   make dist-source    GPLv3 corresponding-source archive for the shipped core
#   make validate       check pak.json against the content-pak contract
#   make check          validate + package + validate the packaged tree
#   make clean          remove build/ (keeps the cached source clone)
#   make distclean      remove build/ entirely, including the source clone

SHELL := /bin/bash
REPO_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
BUILD ?= $(REPO_ROOT)/build
PACKAGE := $(BUILD)/package/ScummVM.pak
DIST := $(BUILD)/dist
ARTIFACT := $(DIST)/ScummVM.mlp1.pak.zip

# The contract this pak is validated against: content-paks-v1, its schema, and
# its reference validator.
#
# It lives in `leaf-contracts`, which is public precisely so that a contract
# a third party is judged against is one they can read. CI pins a SHA; a local
# clone is fine for development. Nothing here needs UMRK credentials.
CONTRACT_REPO ?= https://github.com/Utility-Muffin-Research-Kitchen/leaf-contracts.git
CONTRACT_REF ?= main
CONTRACT_DIR ?= $(BUILD)/contract

.PHONY: all core verify-core package-mlp1 dist-pakrat dist-source validate check clean distclean help

all: dist-pakrat

help:
	@sed -n '1,14p' $(lastword $(MAKEFILE_LIST))

core:
	@"$(REPO_ROOT)/core/build-core.sh"

verify-core:
	@FORCE=0 "$(REPO_ROOT)/core/build-core.sh"

# The .info file ships from the pinned source tree rather than being written by
# hand: RetroArch reads it, and a hand-copied one drifts from the core it
# describes.
package-mlp1: core
	@rm -rf "$(PACKAGE)"
	@mkdir -p "$(PACKAGE)/cores" "$(PACKAGE)/info" "$(PACKAGE)/art"
	@cp "$(REPO_ROOT)/pak/pak.json" "$(PACKAGE)/pak.json"
	@cp "$(REPO_ROOT)/pak/art/SCUMMVM.png" "$(PACKAGE)/art/SCUMMVM.png"
	@cp "$(BUILD)/core/scummvm_libretro.so" "$(PACKAGE)/cores/scummvm_libretro.so"
	@python3 "$(REPO_ROOT)/scripts/make-core-info.py" \
		--source "$(BUILD)/scummvm-src" \
		--lock "$(REPO_ROOT)/core/core.lock.json" \
		--out "$(PACKAGE)/info/scummvm_libretro.info"
	@cp "$(REPO_ROOT)/LICENSES/CORE-LICENSE.txt" "$(PACKAGE)/LICENSE-CORE.txt"
	@cp "$(REPO_ROOT)/pak/art/LICENSE-ASSETS.md" "$(PACKAGE)/art/LICENSE-ASSETS.md"
	@echo "packaged $(PACKAGE)"
	@echo "note: no launch.sh -- this is a pure content pak and is not listed in Apps."

dist-pakrat: package-mlp1
	@mkdir -p "$(DIST)"
	@rm -f "$(ARTIFACT)"
	@cd "$(BUILD)/package" && zip -q -r -X "$(ARTIFACT)" "ScummVM.pak"
	@python3 -c "import hashlib,sys;p=sys.argv[1];print('sha256', hashlib.sha256(open(p,'rb').read()).hexdigest())" "$(ARTIFACT)"
	@echo "wrote $(ARTIFACT)"

# GPLv3 corresponding source for the exact binary this repo ships. Publish the
# archive next to the artifact; a written offer is weaker than the source.
dist-source:
	@mkdir -p "$(DIST)"
	@python3 "$(REPO_ROOT)/scripts/make-source-archive.py" \
		--lock "$(REPO_ROOT)/core/core.lock.json" \
		--source "$(BUILD)/scummvm-src" \
		--output "$(DIST)/scummvm-corresponding-source.tar.gz"
	@cp "$(REPO_ROOT)/core/core.lock.json" "$(DIST)/core.lock.json"
	@python3 -c "import hashlib,sys;p=sys.argv[1];print('sha256', hashlib.sha256(open(p,'rb').read()).hexdigest())" \
		"$(DIST)/scummvm-corresponding-source.tar.gz"
	@echo "wrote $(DIST)/scummvm-corresponding-source.tar.gz"
	@echo "includes the exact ScummVM, libretro-deps, and libretro-common commits"

$(CONTRACT_DIR):
	@mkdir -p "$(BUILD)"
	@echo "fetching contract $(CONTRACT_REF) from $(CONTRACT_REPO)"
	@git clone -q --depth 1 --branch "$(CONTRACT_REF)" "$(CONTRACT_REPO)" "$(CONTRACT_DIR)" \
		|| (rm -rf "$(CONTRACT_DIR)"; \
		    echo ""; \
		    echo "could not fetch the content-pak contract." >&2; \
		    echo "" >&2; \
		    echo "  It lives in the public leaf-contracts repository. If you have" >&2; \
		    echo "  a local clone, point at it:" >&2; \
		    echo "" >&2; \
		    echo "      make validate CONTRACT_DIR=/path/to/leaf-contracts" >&2; \
		    echo "" >&2; \
		    echo "  Otherwise check your network. Every other target in this" >&2; \
		    echo "  repository is self-contained and still works offline:" >&2; \
		    echo "      make core / package-mlp1 / dist-pakrat / dist-source" >&2; \
		    echo "" >&2; \
		    exit 1)

validate: | $(CONTRACT_DIR)
	@python3 "$(REPO_ROOT)/scripts/validate-pak.py" \
		--contract "$(CONTRACT_DIR)" --pak "$(REPO_ROOT)/pak"

check: validate package-mlp1
	@python3 "$(REPO_ROOT)/scripts/validate-pak.py" \
		--contract "$(CONTRACT_DIR)" --pak "$(PACKAGE)" --packaged

clean:
	@rm -rf "$(BUILD)/package" "$(BUILD)/dist" "$(BUILD)/contract"

distclean:
	@rm -rf "$(BUILD)"

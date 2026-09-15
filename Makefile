# ScummVM content pak for Leaf.
#
# A clean clone of this repository plus Docker, make, and python3 is the whole
# toolchain. Nothing here reaches outside the repository: no sibling checkouts,
# no UMRK workspace layout, no locally built images. If a target of yours needs
# a path starting with ../, it does not belong in this file.
#
#   make core           build the pinned ScummVM libretro core (long; cached)
#   make standalone     build the pinned standalone ScummVM and its codecs (long; cached)
#   make package-mlp1   assemble build/package/ScummVM.pak
#   make dist-pakrat    zip it into build/dist/ScummVM.mlp1.pak.zip
#   make dist-source    GPL corresponding-source archives for both shipped binaries
#   make validate       check pak.json against the content-pak contract
#   make test-wrapper   check the standalone launch wrapper (no build needed)
#   make check          validate + test-wrapper + package + validate the packaged tree
#   make clean          remove build/ outputs (keeps the cached sources and builds)
#   make distclean      remove build/ entirely, including the source clones

SHELL := /bin/bash
REPO_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
BUILD ?= $(REPO_ROOT)/build
PACKAGE := $(BUILD)/package/ScummVM.pak
DIST := $(BUILD)/dist
ARTIFACT := $(DIST)/ScummVM.mlp1.pak.zip
STANDALONE_PKG := $(PACKAGE)/emulators/scummvm-standalone

# The contract this pak is validated against: content-paks-v1, its schema, and
# its reference validator.
#
# It lives in `leaf-contracts`, which is public precisely so that a contract
# a third party is judged against is one they can read. CI pins a SHA; a local
# clone is fine for development. Nothing here needs UMRK credentials.
CONTRACT_REPO ?= https://github.com/Utility-Muffin-Research-Kitchen/leaf-contracts.git
CONTRACT_REF ?= 8150e52b6026d6111da078ee6c9901d11b5d5ccc
CONTRACT_DIR ?= $(BUILD)/contract

.PHONY: all core verify-core standalone verify-standalone package-mlp1 dist-pakrat dist-source validate test-wrapper check clean distclean help

all: dist-pakrat

help:
	@sed -n '1,17p' $(lastword $(MAKEFILE_LIST))

core:
	@"$(REPO_ROOT)/core/build-core.sh"

verify-core:
	@FORCE=0 "$(REPO_ROOT)/core/build-core.sh"

standalone:
	@"$(REPO_ROOT)/standalone/build-standalone.sh"

verify-standalone:
	@FORCE=0 "$(REPO_ROOT)/standalone/build-standalone.sh"

# The core's own upstream target supplies its data and .info file. The Leaf
# patch lets ScummVM read those immutable assets beside the core while keeping
# user-owned scummvm.ini in BIOS/.
#
# The standalone lane ships the unpatched ScummVM executable, its upstream
# `make install` data, and the licence notices for it and its static codecs.
# It bundles no shared libraries: everything it links is on the device.
package-mlp1: core standalone
	@rm -rf "$(PACKAGE)"
	@mkdir -p "$(PACKAGE)/cores" "$(PACKAGE)/info" "$(PACKAGE)/art"
	@cp "$(REPO_ROOT)/pak/pak.json" "$(PACKAGE)/pak.json"
	@cp "$(REPO_ROOT)/pak/art/SCUMMVM.png" "$(PACKAGE)/art/SCUMMVM.png"
	@cp "$(REPO_ROOT)/pak/art/SCUMMVM-photo.png" "$(PACKAGE)/art/SCUMMVM-photo.png"
	@cp "$(REPO_ROOT)/pak/art/SCUMMVM-grid.png" "$(PACKAGE)/art/SCUMMVM-grid.png"
	@cp "$(REPO_ROOT)/pak/art/GRID-ICON-SOURCE.md" "$(PACKAGE)/art/GRID-ICON-SOURCE.md"
	@cp "$(REPO_ROOT)/pak/art/SCUMMVM-wordmark.png" "$(PACKAGE)/art/SCUMMVM-wordmark.png"
	@cp "$(REPO_ROOT)/pak/art/WORDMARK-SOURCE.md" "$(PACKAGE)/art/WORDMARK-SOURCE.md"
	@cp "$(BUILD)/core/scummvm_libretro.so" "$(PACKAGE)/cores/scummvm_libretro.so"
	@cd "$(PACKAGE)/cores" && unzip -q "$(BUILD)/core/scummvm.zip"
	@cp "$(BUILD)/core/scummvm_libretro.info" "$(PACKAGE)/info/scummvm_libretro.info"
	@mkdir -p "$(STANDALONE_PKG)/bin" "$(STANDALONE_PKG)/defaults"
	@cp "$(REPO_ROOT)/pak/emulators/scummvm-standalone/launch-game.sh" "$(STANDALONE_PKG)/launch-game.sh"
	@cp "$(REPO_ROOT)/pak/emulators/scummvm-standalone/defaults/scummvm.ini" "$(STANDALONE_PKG)/defaults/scummvm.ini"
	@cp "$(BUILD)/standalone/scummvm" "$(STANDALONE_PKG)/bin/scummvm"
	@chmod 755 "$(STANDALONE_PKG)/launch-game.sh" "$(STANDALONE_PKG)/bin/scummvm"
	@cp -R "$(BUILD)/standalone/share" "$(STANDALONE_PKG)/share"
	@cp -R "$(BUILD)/standalone/licenses" "$(STANDALONE_PKG)/licenses"
	@cp "$(REPO_ROOT)/LICENSES/CORE-LICENSE.txt" "$(PACKAGE)/LICENSE-CORE.txt"
	@cp "$(REPO_ROOT)/LICENSES/STANDALONE-LICENSE.txt" "$(PACKAGE)/LICENSE-STANDALONE.txt"
	@cp "$(REPO_ROOT)/pak/art/LICENSE-ASSETS.md" "$(PACKAGE)/art/LICENSE-ASSETS.md"
	@echo "packaged $(PACKAGE)"
	@echo "note: no launch.sh -- this is a pure content pak and is not listed in Apps."

dist-pakrat: package-mlp1
	@mkdir -p "$(DIST)"
	@rm -f "$(ARTIFACT)"
	@cd "$(BUILD)/package" && zip -q -r -X "$(ARTIFACT)" "ScummVM.pak"
	@python3 -c "import hashlib,sys;p=sys.argv[1];print('sha256', hashlib.sha256(open(p,'rb').read()).hexdigest())" "$(ARTIFACT)"
	@echo "wrote $(ARTIFACT)"

# GPL corresponding source for the exact binaries this repo ships. Publish the
# archives next to the artifact; a written offer is weaker than the source.
dist-source:
	@mkdir -p "$(DIST)"
	@python3 "$(REPO_ROOT)/scripts/make-source-archive.py" \
		--lock "$(REPO_ROOT)/core/core.lock.json" \
		--source "$(BUILD)/scummvm-src" \
		--output "$(DIST)/scummvm-corresponding-source.tar.gz" \
		--lock-name leaf-core.lock.json
	@python3 "$(REPO_ROOT)/scripts/make-source-archive.py" \
		--lock "$(REPO_ROOT)/standalone/standalone.lock.json" \
		--source "$(BUILD)/scummvm-standalone-src" \
		--output "$(DIST)/scummvm-standalone-corresponding-source.tar.gz" \
		--lock-name leaf-standalone.lock.json \
		--source-prefix "scummvm-standalone" \
		--downloads "$(BUILD)/downloads"
	@cp "$(REPO_ROOT)/core/core.lock.json" "$(DIST)/core.lock.json"
	@cp "$(REPO_ROOT)/standalone/standalone.lock.json" "$(DIST)/standalone.lock.json"
	@python3 -c "import hashlib,sys;p=sys.argv[1];print('sha256', hashlib.sha256(open(p,'rb').read()).hexdigest())" \
		"$(DIST)/scummvm-corresponding-source.tar.gz"
	@python3 -c "import hashlib,sys;p=sys.argv[1];print('sha256', hashlib.sha256(open(p,'rb').read()).hexdigest())" \
		"$(DIST)/scummvm-standalone-corresponding-source.tar.gz"
	@echo "wrote $(DIST)/scummvm-corresponding-source.tar.gz"
	@echo "wrote $(DIST)/scummvm-standalone-corresponding-source.tar.gz"
	@echo "core archive includes the exact ScummVM, libretro-deps, and libretro-common commits"
	@echo "standalone archive includes ScummVM, the codec sources and patches, and the build scripts"

$(CONTRACT_DIR):
	@mkdir -p "$(BUILD)"
	@echo "fetching contract $(CONTRACT_REF) from $(CONTRACT_REPO)"
	@(git init -q "$(CONTRACT_DIR)" && \
	  git -C "$(CONTRACT_DIR)" fetch -q --depth 1 "$(CONTRACT_REPO)" "$(CONTRACT_REF)" && \
	  git -C "$(CONTRACT_DIR)" checkout -q --detach FETCH_HEAD) \
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
		    echo "      make core / standalone / package-mlp1 / dist-pakrat / dist-source" >&2; \
		    echo "" >&2; \
		    exit 1)

validate: | $(CONTRACT_DIR)
	@python3 "$(REPO_ROOT)/scripts/validate-pak.py" \
		--contract "$(CONTRACT_DIR)" --pak "$(REPO_ROOT)/pak"

test-wrapper:
	@sh "$(REPO_ROOT)/tests/test-wrapper.sh"

check: validate test-wrapper package-mlp1
	@python3 "$(REPO_ROOT)/scripts/validate-pak.py" \
		--contract "$(CONTRACT_DIR)" --pak "$(PACKAGE)" --packaged

clean:
	@rm -rf "$(BUILD)/package" "$(BUILD)/dist" "$(BUILD)/contract"

distclean:
	@rm -rf "$(BUILD)"

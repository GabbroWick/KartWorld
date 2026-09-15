# KartWorld — developer shortcuts. Run from the project root with GNU make
# (Git for Windows ships it as `make` in some installs; otherwise install
# `mingw32-make` or run the commands inside by hand).
#
# The recipes are POSIX sh (mkdir -p, rm -rf, grep, for loops). Started from
# cmd.exe or PowerShell, make would hand them to cmd.exe and every one fails
# with "CreateProcess(NULL, mkdir -p ...) failed"; force Git's sh instead.
# GnuWin32 make does not look SHELL up in PATH and chokes on spaces, so the
# candidates use 8.3 short names.
ifeq ($(OS),Windows_NT)
SH_CANDIDATES := C:/PROGRA~1/Git/usr/bin/sh.exe C:/PROGRA~2/Git/usr/bin/sh.exe \
                 C:/PROGRA~1/Git/bin/sh.exe C:/PROGRA~2/Git/bin/sh.exe
SHELL := $(firstword $(wildcard $(SH_CANDIDATES)))
ifeq ($(SHELL),)
$(error Git for Windows sh.exe not found - set SHELL by hand or run make from Git Bash)
endif
.SHELLFLAGS := -c
# make 3.81 runs metacharacter-free recipe lines without a shell at all, so
# mkdir/rm/grep must also be reachable through PATH, not only through sh.
export PATH := $(patsubst %/,%,$(dir $(SHELL))):$(PATH)
endif

GODOT ?= C:/Users/gabri/Godot_v4.7.2/Godot_v4.7.2-stable_win64_console.exe
WEB_DIR := builds/web
SUITES := test_runner test_kart_runner test_island_runner test_portal_runner \
          test_level_runner test_combat_runner test_progression_runner test_hub_runner test_touch_runner test_volcano_runner

.PHONY: help run web serve test test-lighting import screenshot clean-web character concept gpu-check

help:
	@echo "make run            - launch the game"
	@echo "make web            - export the Web build to $(WEB_DIR)"
	@echo "make serve          - serve $(WEB_DIR) on http://localhost:8060"
	@echo "make test           - run every headless suite"
	@echo "make test-lighting  - run the windowed lighting suite"
	@echo "make import         - reimport assets / refresh the class cache"
	@echo "make screenshot     - render a frame to screenshot.png"
	@echo "make clean-web      - delete the Web build"
	@echo "make gpu-check      - verify PyTorch sees the AMD GPU (ROCm)"
	@echo "make concept NAME=fox PROMPT=\"cute cartoon fox...\"  - local SDXL concepts"
	@echo "make character NAME=fox [ARGS=\"--tail 0.5\"]        - concept -> shape -> texture -> Blender -> Mixamo FBX"

run:
	"$(GODOT)" --path .

apk: import
	@mkdir -p builds/android
	"$(GODOT)" --headless --path . --export-debug "Android" builds/android/MegaAdventure.apk
	@echo "APK in builds/android/MegaAdventure.apk (debug-signed: install with 'adb install -r' or copy to the phone)"

web: import
	@mkdir -p $(WEB_DIR)
	"$(GODOT)" --headless --path . --export-release "Web" $(WEB_DIR)/index.html
	@echo "Web build in $(WEB_DIR) - run 'make serve' and open http://localhost:8060"

serve:
	python tools/serve_web.py

test:
	@status=0; for s in $(SUITES); do \
		echo "=== $$s ==="; \
		out=$$("$(GODOT)" --headless --path . res://tools/tests/$$s.tscn 2>&1); \
		echo "$$out" | grep -E "FAIL|checks|SCRIPT ERROR"; \
		if echo "$$out" | grep -qE "FAIL|SCRIPT ERROR"; then status=1; fi; \
	done; exit $$status

test-lighting:
	"$(GODOT)" --path . res://tools/tests/test_lighting_runner.tscn 2>&1 | grep -E "PASS|FAIL|checks"

import:
	"$(GODOT)" --headless --path . --editor --quit >/dev/null 2>&1 || true

screenshot:
	"$(GODOT)" --path . res://tools/capture_screenshot.tscn -- screenshot.png 120

clean-web:
	rm -rf $(WEB_DIR)

AI3D_PY := tools/ai3d/.venv/Scripts/python

gpu-check:
	$(AI3D_PY) tools/ai3d/check_gpu.py

concept:
	$(AI3D_PY) tools/ai3d/generate_concept.py --name $(NAME) --prompt "$(PROMPT)" --variants 6 --size 640

character:
	$(AI3D_PY) tools/ai3d/generate_character.py $(NAME) $(ARGS)

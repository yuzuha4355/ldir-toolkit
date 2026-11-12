# 開発用タスク
#   make lint    静的解析（shellcheck）
#   make test    単体テスト（root 不要）
#   make smoke   実収集テスト（root 必須。コンテナや検証機で実行すること）
#   make check   lint + test
#   make dist    配布用アーカイブを dist/ に作成（.sha256 付き）

SHELL_FILES := $(shell find ldir-toolkit tests docker-test -name '*.sh' | sort)

VERSION := $(shell bash ldir-toolkit/ldir-collect.sh --version | awk '{print $$2}')
DIST_NAME := ldir-toolkit-v$(VERSION)

.PHONY: lint test smoke check dist

lint:
	bash -n ldir-toolkit/ldir-collect.sh
	shellcheck -x -S warning $(SHELL_FILES)

test:
	bash tests/test_unit.sh

smoke:
	bash tests/test_smoke.sh

check: lint test

# 配布物: 収集ツール本体 + 文書。展開すると ldir-toolkit-vX.Y.Z/ ができる。
dist: check
	rm -rf dist/$(DIST_NAME)
	mkdir -p dist/$(DIST_NAME)
	cp -a ldir-toolkit/ldir-collect.sh ldir-toolkit/lib ldir-toolkit/modules dist/$(DIST_NAME)/
	cp -a README.md CHANGELOG.md LICENSE docs dist/$(DIST_NAME)/
	chmod +x dist/$(DIST_NAME)/ldir-collect.sh
	tar -czf dist/$(DIST_NAME).tar.gz -C dist $(DIST_NAME)
	cd dist && sha256sum $(DIST_NAME).tar.gz > $(DIST_NAME).tar.gz.sha256
	rm -rf dist/$(DIST_NAME)
	@echo "dist/$(DIST_NAME).tar.gz"

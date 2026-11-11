# 開発用タスク
#   make lint    静的解析（shellcheck）
#   make test    単体テスト（root 不要）
#   make smoke   実収集テスト（root 必須。コンテナや検証機で実行すること）
#   make check   lint + test

SHELL_FILES := $(shell find ldir-toolkit tests docker-test -name '*.sh' | sort)

.PHONY: lint test smoke check

lint:
	bash -n ldir-toolkit/ldir-collect.sh
	shellcheck -x -S warning $(SHELL_FILES)

test:
	bash tests/test_unit.sh

smoke:
	bash tests/test_smoke.sh

check: lint test

NVIM ?= nvim
STYLUA ?= stylua
LUA_LS ?= lua-language-server
VIMRUNTIME ?= $(shell $(NVIM) --headless -u NONE -i NONE -n -c "lua io.write(vim.env.VIMRUNTIME or (vim.fn.fnamemodify(vim.v.progpath, ':h:h') .. '/share/nvim/runtime'))" -c qa 2>/dev/null)

.PHONY: test format format-check benchmark typecheck

test: typecheck
	$(NVIM) --headless -u NONE -i NONE -n +"lua require('tests.run').run()"

typecheck:
	VIMRUNTIME="$(VIMRUNTIME)" $(LUA_LS) --check . --checklevel=Warning

benchmark:
	$(NVIM) --headless -u NONE -i NONE --cmd "set noswapfile" +"luafile tests/duet_edits_bench.lua" +"qa!"

format:
	$(STYLUA) lua/ tests/

format-check:
	$(STYLUA) --check lua/ tests/

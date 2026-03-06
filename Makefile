.PHONY: compile bench clean shell

compile:
	mix compile

bench: compile
	mix run bench/http_parser_bench.exs

shell: compile
	iex -S mix

clean:
	mix clean
	rm -rf _build deps

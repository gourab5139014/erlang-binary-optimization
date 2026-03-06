# Benchee benchmark for the three http_parser variants.
#
# Run with:
#   make bench
#   # or: mix run bench/http_parser_bench.exs

response =
  "HTTP/1.1 200 OK\r\n" <>
    "Content-Type: application/json\r\n" <>
    "Content-Length: 27\r\n" <>
    "Connection: keep-alive\r\n" <>
    "X-Request-Id: abc123def456\r\n" <>
    "\r\n" <>
    ~s({"status":"ok","code":200})

patterns = :http_parser.compile_patterns()

Benchee.run(
  %{
    "plain" => fn -> :http_parser.parse_plain(response) end,
    "compiled_bti" => fn -> :http_parser.parse_compiled_bti(response, patterns) end,
    "compiled" => fn -> :http_parser.parse_compiled(response, patterns) end
  },
  warmup: 2,
  time: 5,
  memory_time: 2
)

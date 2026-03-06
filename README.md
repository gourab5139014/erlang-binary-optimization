# Erlang Binary Matching Optimization

A benchmarked demonstration of two targeted optimizations that produce a **~4x speedup** when parsing binary data in Erlang hot paths — without changing the algorithm.

This repo accompanies a write-up on the topic. The example uses an HTTP/1.1 response parser as a concrete, realistic workload.

Benchmarks use [Benchee](https://github.com/bencheeorg/benchee) for statistically rigorous measurements (warmup, multiple samples, standard deviation).

---

## What's Inside

Three implementations of the same HTTP response parser in `src/http_parser.erl`:

| Variant | Description |
|---|---|
| `parse_plain/1` | Baseline — plain binary literals in every `binary:split` call |
| `parse_compiled_bti/2` | Precompiled patterns + `binary_to_integer` for status code |
| `parse_compiled/2` | Precompiled patterns + arithmetic integer conversion |

The Benchee script lives in `bench/http_parser_bench.exs`.

---

## Requirements

- Erlang/OTP 25 or later
- Elixir 1.14 or later (for Benchee — `brew install elixir` on macOS)
- [rebar3](https://rebar3.org) is not required; Mix handles compilation

---

## Quick Start

```bash
git clone https://github.com/gourab5139014/erlang-binary-optimization
cd erlang-binary-optimization
mix deps.get
make bench
```

### Expected output

```
Operating System: macOS
CPU Information: Apple M4
Number of Available Cores: 10
Available memory: 16 GB
Elixir 1.19.5
Erlang 28.3.3
JIT enabled: true

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 5 s
memory time: 2 s
parallel: 1

Name                   ips        average  deviation         median         99th %
compiled            2.76 M      362.87 ns  ±1047.25%         333 ns         500 ns
compiled_bti        2.63 M      380.50 ns  ±1136.25%         334 ns         500 ns
plain               0.77 M     1294.41 ns   ±543.51%        1208 ns        1750 ns

Comparison:
compiled            2.76 M
compiled_bti        2.63 M - 1.05x slower +17.63 ns
plain               0.77 M - 3.57x slower +931.54 ns

Memory usage statistics:
Name            Memory usage
compiled             1.02 KB
compiled_bti         1.05 KB - 1.02x memory usage
plain                1.05 KB - 1.02x memory usage
```

> Numbers will vary by machine and OTP version. The dominant win is from precompiled patterns (~4-5x). The arithmetic conversion vs `binary_to_integer` difference is smaller and may vary with the JIT in OTP 26+.

---

## Running Interactively

```bash
make shell
# opens iex -S mix
```

Then in the IEx shell:

```elixir
# Parse a single response
response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nhello"
:http_parser.parse_plain(response)

patterns = :http_parser.compile_patterns()
:http_parser.parse_compiled(response, patterns)
```

---

## The Two Optimizations

### 1. Precompiled Binary Patterns

`binary:split/2` uses Boyer-Moore search internally. When you pass a plain binary literal, those tables are rebuilt on every call. In a hot loop parsing thousands of responses per second, that overhead adds up.

`binary:compile_pattern/1` builds the tables once and returns an opaque `binary:cp()` value you can reuse:

```erlang
% Build once at startup
Patterns = binary:compile_pattern(<<"\r\n\r\n">>),

% Reuse across all calls — no table reconstruction
binary:split(Bin, Patterns)
```

### 2. Arithmetic Integer Parsing

HTTP status codes are always 3 ASCII digits. The generic `binary_to_integer/1` BIF doesn't know that — it allocates a sub-binary and does general-purpose parsing.

Direct byte extraction with arithmetic is faster and allocates nothing:

```erlang
% Instead of:
%   <<"HTTP/1.1 ", Status:3/binary, ...>> = Line,
%   Code = binary_to_integer(Status),

% Do this:
<<"HTTP/1.1 ", N1, N2, N3, " ", _/binary>> = Line,
Code = (N1 - $0) * 100 + (N2 - $0) * 10 + (N3 - $0).
```

---

## Profiling Your Own Code

To identify hotspots before optimizing:

```erlang
eprof:start().
eprof:start_profiling([self()]).

%% ... run your workload ...

eprof:stop_profiling().
eprof:analyze(total).
```

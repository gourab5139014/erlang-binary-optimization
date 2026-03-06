# LinkedIn Post — Erlang Binary Matching Optimization

---

A 3.5x speedup. No algorithmic change. No C NIF. Just understanding what the Erlang runtime was doing on every function call.

Here's what I found.

---

**Why binary parsing performance matters in production Erlang**

If you're building anything on the BEAM that touches binary data at scale — HTTP clients, custom protocol parsers, log ingestion pipelines — you're probably calling `binary:split/2` in a hot path.

These functions are fast. But there's a cost that's easy to overlook.

When you write `binary:split(Bin, <<"\r\n">>)`, Erlang doesn't just scan for those two bytes.

It first constructs Boyer-Moore search tables from the pattern — then uses them to search the binary.

That table construction happens on every call when you pass a plain binary literal.

In a loop running tens of thousands of times per second, that overhead adds up.

---

**How did I find this**

I was looking at some code that parsed HTTP responses and something felt off. Rather than guessing, I profiled it with `eprof` — Erlang's built-in function-level profiler.

The output was unambiguous:

- `binary:split/2` → 24% of total runtime
- `binary_to_integer/1` → another 3%

Armed with that, I made two changes.

---

**Change 1: Pre-compile the patterns**

`binary:compile_pattern/1` builds the Boyer-Moore tables once and returns an opaque `binary:cp()` value.

Pass that into `binary:split/2` instead of a raw binary literal, and the table construction happens exactly once — at startup — not on every parse.

```erlang
%% Before: tables rebuilt on every call
binary:split(Bin, <<"\r\n\r\n">>)

%% After: tables built once, reused on every call
Patterns = binary:compile_pattern(<<"\r\n\r\n">>),
binary:split(Bin, Patterns)
```

This single change was responsible for the bulk of the improvement.

---

**Change 2: Exploit domain knowledge**

HTTP status codes are always exactly three ASCII digits.

The generic `binary_to_integer/1` BIF doesn't know that — it allocates a sub-binary and runs a general-purpose parser.

If you know the input format, you can skip all of that:

```erlang
%% Before
<<"HTTP/1.1 ", Status:3/binary, " ", _/binary>> = Line,
Code = binary_to_integer(Status),

%% After: direct byte extraction, no allocation
<<"HTTP/1.1 ", N1, N2, N3, " ", _/binary>> = Line,
Code = (N1 - $0) * 100 + (N2 - $0) * 10 + (N3 - $0)
```

The gain from this second change is smaller — the JIT in OTP 26+ handles `binary_to_integer/1` well.

But the principle stands: when you know more about your input than a generic function does, you can write something faster and simpler.

---

**The result**

Measured with Benchee — proper warmup, multiple samples, standard deviation:

- plain baseline: **1294 ns/call**
- precompiled patterns + arithmetic parsing: **362 ns/call**
- **3.5x faster on OTP 28 with JIT. The gap is larger on older OTP versions.**

---

**Try it yourself**

The full example — three parser variants, a Benchee benchmark, and a Makefile — is on GitHub:

https://github.com/gourab5139014/erlang-binary-optimization

```bash
git clone https://github.com/gourab5139014/erlang-binary-optimization
cd erlang-binary-optimization
mix deps.get
make bench
```

You'll need Erlang/OTP 25+ and Elixir 1.14+ (`brew install elixir` on macOS).

---

**Further reading**

- eprof documentation: https://www.erlang.org/doc/apps/tools/eprof.html
- Benchee: https://github.com/bencheeorg/benchee

---

If you've hit similar bottlenecks in production BEAM systems — or found optimizations that surprised you — I'd love to hear about them in the comments.

---

*#Erlang #BEAM #PerformanceEngineering #BackendDevelopment #SystemsProgramming*

%% @doc HTTP/1.1 response parser — three variants demonstrating binary matching optimizations.
%%
%% Variants:
%%   parse_plain/1         — baseline: binary literals passed directly to binary:split
%%   parse_compiled_bti/2  — precompiled patterns + binary_to_integer for status code
%%   parse_compiled/2      — precompiled patterns + arithmetic integer conversion (fastest)
%%
%% Use benchmark:run/1 to compare all three.
-module(http_parser).

-export([
    compile_patterns/0,
    parse_plain/1,
    parse_compiled_bti/2,
    parse_compiled/2
]).

-record(patterns, {
    rn   :: binary:cp(),   %% \r\n
    rnrn :: binary:cp(),   %% \r\n\r\n
    sep  :: binary:cp()    %% ": "
}).

-type patterns() :: #patterns{}.
-type status()   :: 100..599.
-type reason()   :: binary().
-type header()   :: {binary(), binary()}.
-type headers()  :: [header()].
-type body()     :: binary().
-type response() :: {status(), reason(), headers(), body()}.

%% Build and return pre-compiled search patterns.
%% Call once at startup; pass the result into parse_compiled/2 and parse_compiled_bti/2.
-spec compile_patterns() -> patterns().
compile_patterns() ->
    #patterns{
        rn   = binary:compile_pattern(<<"\r\n">>),
        rnrn = binary:compile_pattern(<<"\r\n\r\n">>),
        sep  = binary:compile_pattern(<<": ">>)
    }.

%% --- Variant 1: plain binary literals (baseline) ----------------------------
%% binary:split/2 must rebuild Boyer-Moore search tables on every call.

-spec parse_plain(binary()) -> response().
parse_plain(Bin) ->
    [HeaderSection, Body] = binary:split(Bin, <<"\r\n\r\n">>),
    [StatusLine | HeaderLines] = binary:split(HeaderSection, <<"\r\n">>, [global]),
    <<"HTTP/1.1 ", StatusBin:3/binary, " ", Reason/binary>> = StatusLine,
    Status = binary_to_integer(StatusBin),
    Headers = parse_headers_plain(HeaderLines, []),
    {Status, Reason, Headers, Body}.

parse_headers_plain([], Acc) -> Acc;
parse_headers_plain([Line | Rest], Acc) ->
    [Name, Value] = binary:split(Line, <<": ">>),
    parse_headers_plain(Rest, [{Name, Value} | Acc]).

%% --- Variant 2: compiled patterns + binary_to_integer ------------------------
%% Boyer-Moore tables built once. Status code still goes through binary_to_integer/1.

-spec parse_compiled_bti(binary(), patterns()) -> response().
parse_compiled_bti(Bin, #patterns{rn = Rn, rnrn = Rnrn, sep = Sep}) ->
    [HeaderSection, Body] = binary:split(Bin, Rnrn),
    [StatusLine | HeaderLines] = binary:split(HeaderSection, Rn, [global]),
    <<"HTTP/1.1 ", StatusBin:3/binary, " ", Reason/binary>> = StatusLine,
    Status = binary_to_integer(StatusBin),
    Headers = parse_headers(HeaderLines, [], Sep),
    {Status, Reason, Headers, Body}.

%% --- Variant 3: compiled patterns + arithmetic integer conversion (fastest) --
%% Boyer-Moore tables built once AND status code converted via direct arithmetic.
%% HTTP status codes are always 3-digit ASCII — no need for the generic BIF.

-spec parse_compiled(binary(), patterns()) -> response().
parse_compiled(Bin, #patterns{rn = Rn, rnrn = Rnrn, sep = Sep}) ->
    [HeaderSection, Body] = binary:split(Bin, Rnrn),
    [StatusLine | HeaderLines] = binary:split(HeaderSection, Rn, [global]),
    <<"HTTP/1.1 ", N1, N2, N3, " ", Reason/binary>> = StatusLine,
    Status = (N1 - $0) * 100 + (N2 - $0) * 10 + (N3 - $0),
    Headers = parse_headers(HeaderLines, [], Sep),
    {Status, Reason, Headers, Body}.

%% Shared tail-recursive header parser used by variants 2 and 3.
parse_headers([], Acc, _Sep) -> Acc;
parse_headers([Line | Rest], Acc, Sep) ->
    [Name, Value] = binary:split(Line, Sep),
    parse_headers(Rest, [{Name, Value} | Acc], Sep).

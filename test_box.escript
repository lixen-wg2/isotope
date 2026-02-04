#!/usr/bin/env escript
%% -*- erlang -*-

%% Test box rendering directly

main(_) ->
    %% Clear screen and go home
    io:format("\e[2J\e[H"),

    %% Test 1: Using io:format with escape sequences
    io:format("Test 1: io:format~n"),
    io:format("\e[3;1H╔══════════════════╗"),
    io:format("\e[4;1H║ Line 2           ║"),
    io:format("\e[5;1H║ Line 3           ║"),
    io:format("\e[6;1H╚══════════════════╝"),

    %% Test 2: Using io:put_chars with binary
    io:format("\e[8;1HTest 2: io:put_chars with binary"),
    Seq1 = <<"\e[10;1H╔══════════════════╗">>,
    Seq2 = <<"\e[11;1H║ Binary test      ║">>,
    Seq3 = <<"\e[12;1H╚══════════════════╝">>,
    io:put_chars(user, Seq1),
    io:put_chars(user, Seq2),
    io:put_chars(user, Seq3),

    %% Test 3: Using iolist_to_binary like iso_render does
    io:format("\e[14;1HTest 3: iolist_to_binary"),
    Move1 = iolist_to_binary(io_lib:format("\e[~B;~BH", [16, 1])),
    Move2 = iolist_to_binary(io_lib:format("\e[~B;~BH", [17, 1])),
    Move3 = iolist_to_binary(io_lib:format("\e[~B;~BH", [18, 1])),
    io:put_chars(user, [Move1, <<"╔══════════════════╗">>]),
    io:put_chars(user, [Move2, <<"║ iolist test      ║">>]),
    io:put_chars(user, [Move3, <<"╚══════════════════╝">>]),

    io:format("\e[20;1HPress Enter to exit..."),
    io:get_line(""),
    ok.


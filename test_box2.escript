#!/usr/bin/env escript
%% -*- erlang -*-

%% Test the exact same approach as iso_tty

main(_) ->
    io:format("\e[2J\e[H"),
    
    %% Build an iolist like iso_render does
    Move1 = iolist_to_binary(io_lib:format("\e[~B;~BH", [3, 1])),
    Move2 = iolist_to_binary(io_lib:format("\e[~B;~BH", [4, 1])),
    Move3 = iolist_to_binary(io_lib:format("\e[~B;~BH", [5, 1])),
    
    %% Test: single io:format with ~ts and iolist_to_binary
    IOList = [
        Move1, <<"╔══════════════════╗"/utf8>>,
        Move2, <<"║ Test line        ║"/utf8>>,
        Move3, <<"╚══════════════════╝"/utf8>>
    ],
    
    io:format("\e[1;1HTest: io:format with ~~ts and iolist_to_binary~n"),
    io:format(user, "~ts", [iolist_to_binary(IOList)]),
    
    %% Test 2: io:format with ~ts directly on iolist (no iolist_to_binary)
    Move4 = iolist_to_binary(io_lib:format("\e[~B;~BH", [8, 1])),
    Move5 = iolist_to_binary(io_lib:format("\e[~B;~BH", [9, 1])),
    Move6 = iolist_to_binary(io_lib:format("\e[~B;~BH", [10, 1])),
    
    IOList2 = [
        Move4, <<"╔══════════════════╗"/utf8>>,
        Move5, <<"║ Test 2           ║"/utf8>>,
        Move6, <<"╚══════════════════╝"/utf8>>
    ],
    
    io:format("\e[7;1HTest 2: io:format ~~ts on iolist directly~n"),
    io:format(user, "~ts", [IOList2]),
    
    %% Test 3: Multiple io:format calls
    io:format("\e[12;1HTest 3: Multiple io:format calls~n"),
    io:format(user, "~ts", [<<"\e[14;1H╔══════════════════╗"/utf8>>]),
    io:format(user, "~ts", [<<"\e[15;1H║ Test 3           ║"/utf8>>]),
    io:format(user, "~ts", [<<"\e[16;1H╚══════════════════╝"/utf8>>]),
    
    io:format("\e[18;1HPress Enter to exit..."),
    io:get_line(""),
    ok.


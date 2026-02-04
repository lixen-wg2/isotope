#!/usr/bin/env escript
%% -*- erlang -*-
%%! -noinput

%% Minimal TTY test to isolate Windows Terminal issues

main(_) ->
    io:format("Testing TTY escape sequences...~n"),
    io:format("Press Enter after each test to continue.~n~n"),
    
    %% Test 1: Basic text
    io:format("Test 1: Basic text - you should see this~n"),
    wait_enter(),
    
    %% Test 2: Colors
    io:format("\e[1;32mTest 2: Green bold text\e[0m~n"),
    wait_enter(),
    
    %% Test 3: Clear screen
    io:format("Test 3: About to clear screen...~n"),
    wait_enter(),
    io:format("\e[2J\e[H"),  %% Clear and home
    io:format("Screen cleared! You should see only this.~n"),
    wait_enter(),
    
    %% Test 4: Alternate screen buffer
    io:format("Test 4: Entering alternate screen buffer...~n"),
    wait_enter(),
    io:format("\e[?1049h"),  %% Enter alt screen
    io:format("\e[2J\e[H"),  %% Clear
    io:format("You are now in the ALTERNATE screen buffer.~n"),
    io:format("Your previous content should be hidden.~n"),
    io:format("Press Enter to exit alternate buffer...~n"),
    wait_enter(),
    io:format("\e[?1049l"),  %% Exit alt screen
    io:format("Back to normal screen. Previous content should be restored.~n"),
    wait_enter(),
    
    %% Test 5: Hide/show cursor
    io:format("Test 5: Hiding cursor...~n"),
    io:format("\e[?25l"),  %% Hide cursor
    wait_enter(),
    io:format("\e[?25h"),  %% Show cursor
    io:format("Cursor should be visible again.~n"),
    wait_enter(),
    
    %% Test 6: Rapid alt screen switch (stress test)
    io:format("Test 6: Rapid alt screen switching (3 times)...~n"),
    wait_enter(),
    lists:foreach(fun(N) ->
        io:format("\e[?1049h\e[2J\e[HAlt screen #~p~n", [N]),
        timer:sleep(200),
        io:format("\e[?1049l")
    end, [1, 2, 3]),
    io:format("Done with rapid switching.~n"),
    wait_enter(),
    
    io:format("All tests complete!~n"),
    ok.

wait_enter() ->
    io:get_line("").


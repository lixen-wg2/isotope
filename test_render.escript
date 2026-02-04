#!/usr/bin/env escript
%% -*- erlang -*-
%%! -pa _build/default/lib/isotope/ebin

%% Test iso_render output

-include_lib("isotope/include/iso_elements.hrl").

main(_) ->
    %% Build a simple tree
    Tree = #box{
        border = double,
        title = <<"Test">>,
        width = 20,
        height = 5,
        style = #{fg => cyan},
        children = [
            #text{content = <<"Hello">>, x = 1, y = 0}
        ]
    },
    
    Bounds = #bounds{x = 0, y = 0, width = 80, height = 24},
    
    %% Render it
    Output = iso_render:render(Tree, Bounds),
    
    %% Show the raw output for debugging
    io:format("Raw iolist structure:~n~p~n~n", [Output]),
    
    %% Convert to binary and show
    Bin = iolist_to_binary(Output),
    io:format("Binary (escaped):~n~p~n~n", [Bin]),
    
    %% Now actually render it
    io:format("\e[2J\e[H"),
    io:format("Rendered output:~n~n"),
    io:format(user, "~ts", [Bin]),
    
    io:format("\e[15;1HPress Enter to exit..."),
    io:get_line(""),
    ok.


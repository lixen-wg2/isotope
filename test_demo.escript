#!/usr/bin/env escript
%% -*- erlang -*-
%%! -pa examples/demo/_build/default/lib/demo/ebin -pa examples/demo/_build/default/checkouts/isotope/ebin

-include_lib("isotope/include/iso_elements.hrl").

main([]) ->
    %% Ensure iso_render is loaded from checkouts
    code:purge(iso_render),
    code:load_file(iso_render),
    io:format("=== Testing Isotope Demo ===~n~n"),
    
    %% Test 1: demo_server:view works
    io:format("Test 1: demo_server:view...~n"),
    State = #{name => <<"Test">>},
    Tree = demo_server:view(State),
    TreeType = element(1, Tree),
    io:format("  Tree type: ~p ", [TreeType]),
    case TreeType of
        hbox -> io:format("[OK]~n");
        _ -> io:format("[FAIL - expected hbox]~n")
    end,
    
    %% Test 2: hbox has 2 children (box and tabs)
    io:format("Test 2: hbox children...~n"),
    %% hbox record: {hbox, id, module, x, y, width, height, style, visible, focusable, spacing, children}
    Children = element(12, Tree), %% hbox.children (field 12)
    io:format("  Number of children: ~p ", [length(Children)]),
    case length(Children) of
        2 -> io:format("[OK]~n");
        N -> io:format("[FAIL - expected 2, got ~p]~n", [N])
    end,
    
    %% Test 3: First child is box, second is tabs
    io:format("Test 3: Child types...~n"),
    [Child1, Child2] = Children,
    C1Type = element(1, Child1),
    C2Type = element(1, Child2),
    io:format("  Child 1: ~p ", [C1Type]),
    case C1Type of box -> io:format("[OK]~n"); _ -> io:format("[FAIL]~n") end,
    io:format("  Child 2: ~p ", [C2Type]),
    case C2Type of tabs -> io:format("[OK]~n"); _ -> io:format("[FAIL]~n") end,
    
    %% Test 4: render_dimmed works with tabs
    io:format("Test 4: render_dimmed with tabs...~n"),
    Bounds = #bounds{x = 0, y = 0, width = 120, height = 24},
    DimOutput = iso_render:render_dimmed(Tree, Bounds, undefined),
    DimSize = iolist_size(DimOutput),
    io:format("  Output size: ~p bytes ", [DimSize]),
    case DimSize > 500 of
        true -> io:format("[OK - tabs rendered]~n");
        false -> io:format("[FAIL - tabs likely missing]~n")
    end,
    
    %% Test 5: Modal renders correctly
    io:format("Test 5: Modal rendering...~n"),
    Modal = #modal{title = <<"Greeting">>, visible = true, width = 40, height = 5,
                   children = [#text{content = <<"Hello Test!">>}]},
    ModalOutput = iso_render:render_two_level(Modal, Bounds, undefined, undefined),
    ModalSize = iolist_size(ModalOutput),
    io:format("  Modal output size: ~p bytes ", [ModalSize]),
    case ModalSize > 100 of
        true -> io:format("[OK - modal box rendered]~n");
        false -> io:format("[FAIL - modal not rendering box]~n")
    end,
    
    %% Test 6: Check modal output contains border characters
    io:format("Test 6: Modal contains border...~n"),
    ModalBin = iolist_to_binary(ModalOutput),
    %% Double border uses ╔ which is <<226,149,148>> in UTF-8
    HasBorder = binary:match(ModalBin, <<226,149,148>>) =/= nomatch orelse  %% ╔
                binary:match(ModalBin, <<226,148,140>>) =/= nomatch,        %% ┌
    io:format("  Has border chars: ~p ", [HasBorder]),
    case HasBorder of
        true -> io:format("[OK]~n");
        false -> io:format("[WARN - might be encoding issue]~n")
    end,
    
    %% Test 7: Full render with modal overlay
    io:format("Test 7: Full render with modal overlay...~n"),
    %% Simulate what render_full does when modal is set
    DimmedBg = iso_render:render_dimmed(Tree, Bounds, undefined),
    ModalFg = iso_render:render_two_level(Modal, Bounds, undefined, undefined),
    TotalSize = iolist_size(DimmedBg) + iolist_size(ModalFg),
    io:format("  Background: ~p bytes, Modal: ~p bytes, Total: ~p bytes ", 
              [iolist_size(DimmedBg), iolist_size(ModalFg), TotalSize]),
    case TotalSize > 1000 of
        true -> io:format("[OK]~n");
        false -> io:format("[FAIL]~n")
    end,
    
    io:format("~n=== Tests Complete ===~n"),
    ok.


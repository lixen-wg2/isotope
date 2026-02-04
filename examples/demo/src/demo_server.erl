%%%-------------------------------------------------------------------
%%% @doc Demo application for Isotope TUI framework.
%%%
%%% Simple demo showing how to use isotope with callbacks:
%%% - init/1 - return initial state (a map)
%%% - view/1 - return the UI tree based on state
%%% - handle_event/2 - handle events and return new state
%%% @end
%%%-------------------------------------------------------------------
-module(demo_server).

-include_lib("isotope/include/iso_elements.hrl").

%% Isotope callbacks
-export([init/1, view/1, handle_event/2]).

%%====================================================================
%% Isotope Callbacks
%%====================================================================

init(_Args) ->
    {ok, #{name => <<>>}}.

view(State) ->
    #{name := Name} = State,
    #hbox{spacing = 1, children = [
        #box{
            id = main_box,
            border = double,
            title = <<"Isotope Demo">>,
            width = 50, height = 10,
            focusable = true,
            style = #{fg => cyan, bold => true},
            children = [
                #text{content = <<"Welcome to Isotope!">>, x = 1,
                      style = #{bold => true}},
                #text{content = <<"Tab/Arrows to navigate, Enter to activate">>,
                      x = 1, y = 1},
                #text{content = <<"Ctrl+C to quit">>, x = 1, y = 2,
                      style = #{fg => green}},
                #text{content = <<"Name:">>, x = 1, y = 4},
                #input{id = name_input, x = 7, y = 4, width = 30,
                       value = Name, placeholder = <<"Enter your name">>,
                       focusable = true},
                #button{id = greet_btn, x = 1, y = 6, label = <<"Greet">>,
                        focusable = true, style = #{fg => green}},
                #button{id = quit_btn, x = 15, y = 6, label = <<"Quit">>,
                        focusable = true, style = #{fg => red}}
            ]
        },
        #tabs{
            id = demo_tabs,
            height = 10,
            focusable = true,
            style = #{fg => cyan},
            tabs = [
                #tab{id = processes, label = <<"Processes">>, content = [
                    #table{
                        id = proc_table,
                        columns = [
                            #table_col{id = pid, header = <<"PID">>, width = 12},
                            #table_col{id = name, header = <<"Name">>},
                            #table_col{id = mem, header = <<"Mem">>, width = 10, align = right}
                        ],
                        rows = get_process_list(),
                        selected_row = 1
                    }
                ]},
                #tab{id = apps, label = <<"Apps">>, content = [
                    #vbox{children = [
                        #text{content = <<"Running Applications:">>, style = #{bold => true}},
                        #text{content = <<"  kernel">>, style = #{fg => green}},
                        #text{content = <<"  stdlib">>, style = #{fg => green}},
                        #text{content = <<"  demo">>, style = #{fg => cyan}}
                    ]}
                ]},
                #tab{id = memory, label = <<"Memory">>, content = [
                    #vbox{children = [
                        #text{content = <<"Memory Usage:">>, style = #{bold => true}},
                        #text{content = <<"  Total: 24.5 MB">>},
                        #text{content = <<"  Processes: 8.2 MB">>, style = #{fg => yellow}},
                        #text{content = <<"  Atoms: 1.1 MB">>, style = #{fg => cyan}}
                    ]}
                ]}
            ]
        }
    ]}.

handle_event(quit, State) ->
    %% Just return stop - iso_server:terminate will cleanup and halt
    {stop, normal, State};

handle_event({click, greet_btn, _}, State) ->
    Name = maps:get(name, State, <<>>),
    Greeting = case Name of
        <<>> -> <<"Hello, stranger!">>;
        N -> iolist_to_binary([<<"Hello, ">>, N, <<"!">>])
    end,
    Modal = #modal{
        title = <<"Greeting">>,
        width = 40, height = 7,
        style = #{fg => cyan, bold => true},
        children = [
            #text{content = Greeting, x = 1, y = 1, style = #{fg => yellow, bold => true}},
            #text{content = <<"Press ESC to close">>, x = 1, y = 3, style = #{fg => white, dim => true}}
        ]
    },
    {modal, Modal, State};

handle_event({click, quit_btn, _}, State) ->
    handle_event(quit, State);

handle_event({input, name_input, Value}, State) ->
    {noreply, State#{name => Value}};

handle_event({table_activate, proc_table, _RowIdx, [PidStr | _]}, _State) ->
    %% Switch to process detail view
    {switch, process_detail_server, #{pid_str => PidStr}};

handle_event(_Event, State) ->
    {unhandled, State}.

%%====================================================================
%% Internal functions
%%====================================================================

get_process_list() ->
    Procs = erlang:processes(),
    lists:map(fun(Pid) ->
        Info = erlang:process_info(Pid, [registered_name, memory]),
        Name = case proplists:get_value(registered_name, Info) of
            undefined -> <<"(unnamed)">>;
            [] -> <<"(unnamed)">>;
            RegName when is_atom(RegName) -> atom_to_binary(RegName, utf8)
        end,
        Mem = proplists:get_value(memory, Info, 0),
        MemStr = format_memory(Mem),
        [list_to_binary(pid_to_list(Pid)), Name, MemStr]
    end, lists:sublist(Procs, 20)).  %% Limit to 20 processes

format_memory(Bytes) when Bytes < 1024 ->
    iolist_to_binary(io_lib:format("~B B", [Bytes]));
format_memory(Bytes) when Bytes < 1024 * 1024 ->
    iolist_to_binary(io_lib:format("~.1f KB", [Bytes / 1024]));
format_memory(Bytes) ->
    iolist_to_binary(io_lib:format("~.1f MB", [Bytes / (1024 * 1024)])).

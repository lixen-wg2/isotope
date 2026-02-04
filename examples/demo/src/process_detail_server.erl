%%%-------------------------------------------------------------------
%%% @doc Process detail view - shows detailed info about a process
%%% Demonstrates the {switch, Module, Args} pattern for navigation
%%% @end
%%%-------------------------------------------------------------------
-module(process_detail_server).

-include_lib("isotope/include/iso_elements.hrl").

%% Isotope callbacks
-export([init/1, view/1, handle_event/2]).

%%====================================================================
%% Isotope Callbacks
%%====================================================================

init(#{pid_str := PidStr}) ->
    %% Try to convert the PID string back to a real PID
    Pid = try list_to_pid(binary_to_list(PidStr)) catch _:_ -> undefined end,
    {ok, #{pid_str => PidStr, pid => Pid}}.

view(#{pid_str := PidStr, pid := Pid}) ->
    Info = get_process_info(Pid),
    #box{
        id = detail_box,
        border = double,
        title = <<"Process Detail">>,
        width = 60,
        height = 20,
        focusable = true,
        children = [
            #text{content = <<"PID: ", PidStr/binary>>, y = 1, style = #{bold => true, fg => cyan}},
            #text{content = format_info(<<"Status">>, maps:get(status, Info, <<"unknown">>)), y = 3},
            #text{content = format_info(<<"Registered">>, maps:get(registered_name, Info, <<"(none)">>)), y = 4},
            #text{content = format_info(<<"Memory">>, maps:get(memory, Info, <<"?">>)), y = 5},
            #text{content = format_info(<<"Message Queue">>, maps:get(message_queue_len, Info, <<"?">>)), y = 6},
            #text{content = format_info(<<"Reductions">>, maps:get(reductions, Info, <<"?">>)), y = 7},
            #text{content = format_info(<<"Current Function">>, maps:get(current_function, Info, <<"?">>)), y = 9, style = #{fg => yellow}},
            #text{content = format_info(<<"Initial Call">>, maps:get(initial_call, Info, <<"?">>)), y = 10, style = #{fg => yellow}},
            #text{content = <<"">>, y = 12},
            #text{content = <<"Press ESC or 'b' to go back">>, y = 14, style = #{dim => true}},
            #button{id = back_btn, label = <<"[ Back ]">>, y = 16, style = #{fg => white}}
        ]
    }.

handle_event(quit, State) ->
    {stop, normal, State};

handle_event({click, back_btn, _}, _State) ->
    %% Switch back to the main demo
    {switch, demo_server, #{}};

handle_event({event, {char, $b}}, _State) ->
    %% 'b' key also goes back
    {switch, demo_server, #{}};

handle_event(_Event, State) ->
    {unhandled, State}.

%%====================================================================
%% Internal functions
%%====================================================================

get_process_info(undefined) ->
    #{};
get_process_info(Pid) ->
    case erlang:is_process_alive(Pid) of
        false -> #{status => <<"dead">>};
        true ->
            Info = erlang:process_info(Pid, [
                registered_name, memory, message_queue_len, 
                reductions, current_function, initial_call, status
            ]),
            #{
                status => format_value(proplists:get_value(status, Info)),
                registered_name => format_value(proplists:get_value(registered_name, Info)),
                memory => format_bytes(proplists:get_value(memory, Info)),
                message_queue_len => format_value(proplists:get_value(message_queue_len, Info)),
                reductions => format_value(proplists:get_value(reductions, Info)),
                current_function => format_mfa(proplists:get_value(current_function, Info)),
                initial_call => format_mfa(proplists:get_value(initial_call, Info))
            }
    end.

format_info(Label, Value) when is_binary(Label), is_binary(Value) ->
    <<Label/binary, ": ", Value/binary>>.

format_value(undefined) -> <<"(none)">>;
format_value([]) -> <<"(none)">>;
format_value(V) when is_atom(V) -> atom_to_binary(V, utf8);
format_value(V) when is_integer(V) -> integer_to_binary(V);
format_value(V) -> iolist_to_binary(io_lib:format("~p", [V])).

format_bytes(undefined) -> <<"?">>;
format_bytes(Bytes) when Bytes < 1024 ->
    <<(integer_to_binary(Bytes))/binary, " B">>;
format_bytes(Bytes) when Bytes < 1024 * 1024 ->
    KB = Bytes / 1024,
    iolist_to_binary(io_lib:format("~.1f KB", [KB]));
format_bytes(Bytes) ->
    MB = Bytes / (1024 * 1024),
    iolist_to_binary(io_lib:format("~.1f MB", [MB])).

format_mfa(undefined) -> <<"?">>;
format_mfa({M, F, A}) ->
    iolist_to_binary(io_lib:format("~s:~s/~B", [M, F, A]));
format_mfa(Other) ->
    format_value(Other).


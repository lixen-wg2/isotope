%%%-------------------------------------------------------------------
%%% @doc Demo Processes Page - Process list with dummy data
%%% @end
%%%-------------------------------------------------------------------
-module(demo_processes).

-behaviour(iso_callback).

-include_lib("isotope/include/iso_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    {ok, #{}}.

view(_State) ->
    Processes = fake_processes(),
    #vbox{children = [
        %% Header
        #header{
            title = "Processes",
            subtitle = "nonode@nohost",
            items = [{"Total", "45,678"}]
        },
        
        %% Stats
        #stat_row{
            items = [
                {"Running", "234"},
                {"Waiting", "45,444"},
                {"MsgQ Total", "1,234"}
            ]
        },

        %% Process table
        #table{
            id = proc_table,
            height = fill,
            border = single,
            focusable = true,
            sortable = true,
            activate_on_reclick = true,
            columns = [
                #table_col{id = pid, header = "PID", width = 14},
                #table_col{id = name, header = "Name/Initial Call", width = 25},
                #table_col{id = reds, header = "Reds", width = 12, align = right},
                #table_col{id = mem, header = "Memory", width = 10, align = right},
                #table_col{id = msgq, header = "MsgQ", width = 6, align = right}
            ],
            rows = [process_row(Process) || Process <- Processes],
            selected_row = 1
        },

        %% Status bar
        #status_bar{
            items = [
                {"H", "Home"},
                {"Enter", "Details"},
                {"Q", "Quit"}
            ]
        }
    ]}.

handle_event({table_activate, proc_table, _RowIdx, RowData}, State) ->
    Process = selected_process(RowData),
    Args = #{
        pid_str => maps:get(pid, Process),
        info => maps:get(info, Process)
    },
    {push, process_detail, Args, State};
handle_event(Event, State) ->
    case iso_shortcuts:handle(Event, State, [
        {["h", escape], fun(_) -> {switch, demo_home, #{}} end},
        {"q", {stop, normal}}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.

process_row(Process) ->
    [
        maps:get(pid, Process),
        maps:get(name, Process),
        maps:get(reds, Process),
        maps:get(mem, Process),
        maps:get(msgq, Process)
    ].

selected_process([Pid | _RowData]) ->
    case lists:search(fun(Process) -> maps:get(pid, Process) =:= Pid end, fake_processes()) of
        {value, Process} -> Process;
        false -> hd(fake_processes())
    end.

fake_processes() ->
    [
        #{
            pid => "<0.0.0>",
            name => "init",
            reds => "1,234,567",
            mem => "45.2 KB",
            msgq => "0",
            info => #{
                status => "running",
                registered_name => "init",
                memory => "45.2 KB",
                message_queue_len => "0",
                reductions => "1,234,567",
                current_function => "init:boot_loop/2",
                initial_call => "init:boot/1"
            }
        },
        #{
            pid => "<0.1.0>",
            name => "erts_code_purger",
            reds => "567,890",
            mem => "12.1 KB",
            msgq => "0",
            info => #{
                status => "waiting",
                registered_name => "erts_code_purger",
                memory => "12.1 KB",
                message_queue_len => "0",
                reductions => "567,890",
                current_function => "erts_code_purger:wait_for_request/0",
                initial_call => "erts_code_purger:start/0"
            }
        },
        #{
            pid => "<0.2.0>",
            name => "erl_prim_loader",
            reds => "2,345,678",
            mem => "89.5 KB",
            msgq => "5",
            info => #{
                status => "running",
                registered_name => "erl_prim_loader",
                memory => "89.5 KB",
                message_queue_len => "5",
                reductions => "2,345,678",
                current_function => "erl_prim_loader:loop/3",
                initial_call => "erl_prim_loader:start/3"
            }
        },
        #{
            pid => "<0.3.0>",
            name => "kernel_sup",
            reds => "456,789",
            mem => "34.2 KB",
            msgq => "0",
            info => #{
                status => "waiting",
                registered_name => "kernel_sup",
                memory => "34.2 KB",
                message_queue_len => "0",
                reductions => "456,789",
                current_function => "supervisor:loop/1",
                initial_call => "supervisor:kernel/1"
            }
        },
        #{
            pid => "<0.4.0>",
            name => "application_controller",
            reds => "789,012",
            mem => "56.7 KB",
            msgq => "2",
            info => #{
                status => "running",
                registered_name => "application_controller",
                memory => "56.7 KB",
                message_queue_len => "2",
                reductions => "789,012",
                current_function => "application_controller:loop/4",
                initial_call => "application_controller:start/1"
            }
        },
        #{
            pid => "<0.5.0>",
            name => "code_server",
            reds => "3,456,789",
            mem => "234.5 KB",
            msgq => "0",
            info => #{
                status => "running",
                registered_name => "code_server",
                memory => "234.5 KB",
                message_queue_len => "0",
                reductions => "3,456,789",
                current_function => "code_server:loop/1",
                initial_call => "code_server:start_link/0"
            }
        },
        #{
            pid => "<0.6.0>",
            name => "file_server_2",
            reds => "123,456",
            mem => "23.4 KB",
            msgq => "0",
            info => #{
                status => "waiting",
                registered_name => "file_server_2",
                memory => "23.4 KB",
                message_queue_len => "0",
                reductions => "123,456",
                current_function => "file_server:server_loop/1",
                initial_call => "file_server:start_link/0"
            }
        },
        #{
            pid => "<0.7.0>",
            name => "standard_error_sup",
            reds => "12,345",
            mem => "8.9 KB",
            msgq => "0",
            info => #{
                status => "waiting",
                registered_name => "standard_error_sup",
                memory => "8.9 KB",
                message_queue_len => "0",
                reductions => "12,345",
                current_function => "supervisor:loop/1",
                initial_call => "standard_error_sup:start_link/0"
            }
        },
        #{
            pid => "<0.8.0>",
            name => "user_drv",
            reds => "234,567",
            mem => "45.6 KB",
            msgq => "1",
            info => #{
                status => "running",
                registered_name => "user_drv",
                memory => "45.6 KB",
                message_queue_len => "1",
                reductions => "234,567",
                current_function => "user_drv:server_loop/6",
                initial_call => "user_drv:start/0"
            }
        },
        #{
            pid => "<0.9.0>",
            name => "group:server/3",
            reds => "345,678",
            mem => "67.8 KB",
            msgq => "0",
            info => #{
                status => "waiting",
                registered_name => "(none)",
                memory => "67.8 KB",
                message_queue_len => "0",
                reductions => "345,678",
                current_function => "group:server_loop/3",
                initial_call => "group:server/3"
            }
        }
    ].

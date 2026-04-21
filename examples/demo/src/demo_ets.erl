%%%-------------------------------------------------------------------
%%% @doc Demo ETS Page - ETS tables with dummy data
%%% @end
%%%-------------------------------------------------------------------
-module(demo_ets).

-behaviour(iso_callback).

-include_lib("isotope/include/iso_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    {ok, #{}}.

view(_State) ->
    #vbox{children = [
        %% Header
        #header{
            title = "ETS Tables",
            subtitle = "nonode@nohost",
            items = [{"Tables", "89"}]
        },

        %% Memory usage
        #text{content = "ETS Memory:", style = #{bold => true}},
        #hbox{spacing = 2, children = [
            #text{content = "Total:", width = 6},
            #progress_bar{value = 45, max = 100, width = 30, show_percent = true},
            #text{content = "(45 MB / 100 MB limit)"}
        ]},

        %% ETS table list
        #text{content = "Top Tables by Memory:", style = #{bold => true}},
        #table{
            id = ets_table,
            height = fill,
            border = single,
            focusable = true,
            columns = [
                #table_col{id = name, header = "Name", width = 25},
                #table_col{id = type, header = "Type", width = 12},
                #table_col{id = size, header = "Size", width = 10, align = right},
                #table_col{id = mem, header = "Memory", width = 12, align = right},
                #table_col{id = owner, header = "Owner", width = 15}
            ],
            rows = [
                ["code", "set", "12,345", "8.5 MB", "code_server"],
                ["ac_tab", "set", "234", "2.3 MB", "application_c"],
                ["shell_records", "ordered_set", "567", "1.2 MB", "shell"],
                ["inet_db", "set", "89", "890 KB", "inet_db"],
                ["file_io_servers", "set", "45", "456 KB", "file_server"],
                ["global_names", "set", "23", "234 KB", "global_name"],
                ["pg_local", "bag", "12", "123 KB", "pg"],
                ["timer_tab", "ordered_set", "8", "89 KB", "timer_server"]
            ],
            selected_row = 1
        },

        %% Spacer pushes status bar to bottom
        #spacer{},

        %% Status bar
        #status_bar{
            items = [
                {"H", "Home"},
                {"Enter", "Browse"},
                {"D", "Delete"},
                {"Q", "Quit"}
            ]
        }
    ]}.

handle_event(Event, State) ->
    case iso_shortcuts:handle(Event, State, [
        {["h", escape], fun(_) -> {switch, demo_home, #{}} end},
        {"q", {stop, normal}}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.

%%%-------------------------------------------------------------------
%%% @doc Demo Widgets - Showcases List and Scroll elements
%%% @end
%%%-------------------------------------------------------------------
-module(demo_widgets).

-behaviour(iso_callback).

-include_lib("isotope/include/iso_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    %% Sample items for the list
    MenuItems = [
        "Dashboard",
        "Processes",
        "Network",
        "ETS Tables",
        "System Info",
        "Settings",
        "Help"
    ],
    {ok, #{
        menu_items => MenuItems,
        selected_idx => 0,
        log_wrap => false,
        log_fullscreen => false
    }}.

view(State) ->
    #{
        menu_items := MenuItems,
        selected_idx := SelectedIdx,
        log_wrap := LogWrap,
        log_fullscreen := LogFullscreen
    } = State,
    ActiveItem = selected_menu_item(MenuItems, SelectedIdx),
    LogEntries = prepared_logs(logs_for(ActiveItem), LogWrap, LogFullscreen),
    LogTitle = log_title(ActiveItem, LogWrap, LogFullscreen),
    case LogFullscreen of
        true ->
            #box{
                id = logs_box,
                title = LogTitle,
                width = fill,
                height = fill,
                focusable = true,
                children = [
                    #scroll{
                        id = log_scroll,
                        height = fill,
                        focusable = true,
                        children = [
                            #vbox{children = [
                                #text{content = Entry} || Entry <- LogEntries
                            ]}
                        ]
                    }
                ]
            };
        false ->
            #vbox{children = [
                %% Header
                #header{
                    title = "Widget Demo",
                    subtitle = "List & Scroll elements"
                },

                %% Main content row
                #hbox{spacing = 2, height = fill, children = [
                    %% Left panel: List element
                    #box{
                        id = menu_box,
                        title = "Menu",
                        width = 15,
                        height = fill,
                        focusable = true,
                        children = [
                            #list{
                                id = menu_list,
                                items = MenuItems,
                                selected = SelectedIdx,
                                height = fill,
                                focusable = true,
                                selected_style = #{bg => blue, fg => white, bold => true}
                            }
                        ]
                    },

                    %% Right panel: Scroll container with logs
                    #box{
                        id = logs_box,
                        title = LogTitle,
                        width = fill,
                        height = fill,
                        focusable = true,
                        children = [
                            #scroll{
                                id = log_scroll,
                                height = fill,
                                focusable = true,
                                children = [
                                    #vbox{children = [
                                        #text{content = Entry} || Entry <- LogEntries
                                    ]}
                                ]
                            }
                        ]
                    }
                ]},

                %% Status bar
                #status_bar{
                    items = [
                        {"H", "Home"},
                        {"Q", "Quit"}
                    ]
                }
            ]}
    end.

handle_event({list_select, menu_list, Idx, _Item}, State) ->
    %% Update selected index when list selection changes (Enter key pressed)
    {noreply, State#{selected_idx => Idx}};
handle_event({event, {char, $w}}, State = #{log_wrap := LogWrap}) ->
    {noreply, State#{log_wrap => not LogWrap}};
handle_event({event, {char, $W}}, State = #{log_wrap := LogWrap}) ->
    {noreply, State#{log_wrap => not LogWrap}};
handle_event({event, {char, $f}}, State = #{log_fullscreen := LogFullscreen}) ->
    {noreply, State#{log_fullscreen => not LogFullscreen}};
handle_event({event, {char, $F}}, State = #{log_fullscreen := LogFullscreen}) ->
    {noreply, State#{log_fullscreen => not LogFullscreen}};
handle_event({event, escape}, State = #{log_fullscreen := true}) ->
    {noreply, State#{log_fullscreen => false}};
handle_event(Event, State) ->
    case iso_shortcuts:handle(Event, State, [
        {"h", fun(_) -> {switch, demo_home, #{}} end},
        {["q", escape], {stop, normal}}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.

selected_menu_item(MenuItems, SelectedIdx)
        when SelectedIdx >= 0, SelectedIdx < length(MenuItems) ->
    lists:nth(SelectedIdx + 1, MenuItems);
selected_menu_item([First | _], _SelectedIdx) ->
    First;
selected_menu_item([], _SelectedIdx) ->
    "Dashboard".

logs_for("Dashboard") ->
    make_log_stream(
        [
            "[INFO] Dashboard layout initialized",
            "[INFO] KPI widgets loaded",
            "[DEBUG] Revenue sparkline seeded with demo data",
            "[INFO] Alert summary refreshed",
            "[WARN] Forecast source is using fallback values"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] Dashboard tile ~2..0B completed refresh in ~B ms",
                [N, 8 + (N rem 11)]))
        end);
logs_for("Processes") ->
    make_log_stream(
        [
            "[INFO] Process monitor attached to node demo@localhost",
            "[DEBUG] Enumerating top consumers by reductions",
            "[INFO] Mailbox sampler online",
            "[WARN] Process <0.421.0> exceeded soft queue threshold",
            "[INFO] Scheduler utilization snapshot captured"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] pid=<0.~B.0> reductions=~B mailbox=~B",
                [100 + N, 1200 + N * 37, N rem 9]))
        end);
logs_for("Network") ->
    make_log_stream(
        [
            "[INFO] Network probe started",
            "[INFO] Listening socket verified on port 8080",
            "[DEBUG] DNS cache warmed for demo upstreams",
            "[WARN] Retry budget increased for flaky edge route",
            "[INFO] TLS handshake metrics reset"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] conn=net-~2..0B rx=~BKB tx=~BKB rtt=~Bms",
                [N, 40 + N * 3, 25 + N * 2, 12 + (N rem 17)]))
        end);
logs_for("ETS Tables") ->
    make_log_stream(
        [
            "[INFO] ETS inspector opened",
            "[DEBUG] Sampling cache_index table",
            "[INFO] session_store table stats updated",
            "[WARN] routing_cache reached 78% of demo capacity",
            "[INFO] Expired entries cleanup completed"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] table=demo_cache shard=~2..0B objects=~B memory=~BKB",
                [N, 500 + N * 19, 64 + N * 4]))
        end);
logs_for("System Info") ->
    make_log_stream(
        [
            "[INFO] System overview collected",
            "[DEBUG] CPU topology cached",
            "[INFO] Memory watermark history loaded",
            "[WARN] Disk usage sample is synthetic demo data",
            "[INFO] Uptime counter synchronized"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] sample=~2..0B cpu=~B% mem=~B% load=~.1f",
                [N, 20 + (N rem 35), 35 + (N rem 40), 0.5 + (N rem 8) / 10]))
        end);
logs_for("Settings") ->
    make_log_stream(
        [
            "[INFO] Settings panel mounted",
            "[DEBUG] Theme preset loaded: terminal-classic",
            "[INFO] User preferences hydrated from demo profile",
            "[WARN] Autosave is disabled in demo mode",
            "[INFO] Keyboard shortcut map validated"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] setting=batch-~2..0B applied source=demo_profile version=~B",
                [N, 3 + (N rem 5)]))
        end);
logs_for("Help") ->
    make_log_stream(
        [
            "[INFO] Help index generated",
            "[DEBUG] Command palette tips loaded",
            "[INFO] Keyboard navigation guide prepared",
            "[WARN] External docs links are disabled in demo mode",
            "[INFO] Support shortcuts rendered"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] help-topic=section-~2..0B rendered with ~B examples",
                [N, 2 + (N rem 6)]))
        end);
logs_for(_Other) ->
    make_log_stream(
        [
            "[INFO] Generic log stream initialized"
        ],
        fun(N) ->
            lists:flatten(io_lib:format("[TRACE] fallback event ~2..0B", [N]))
        end).

make_log_stream(BaseEntries, Generator) ->
    BaseEntries ++ [Generator(N) || N <- lists:seq(1, 50)].

prepared_logs(LogEntries, false, _LogFullscreen) ->
    LogEntries;
prepared_logs(LogEntries, true, LogFullscreen) ->
    lists:flatmap(fun(Entry) -> wrap_log_entry(Entry, wrap_width(LogFullscreen)) end, LogEntries).

wrap_width(true) -> 120;
wrap_width(false) -> 80.

wrap_log_entry(Entry, Width) ->
    Chars = unicode:characters_to_list(iolist_to_binary(Entry)),
    wrap_log_chars(Chars, max(8, Width), true, []).

wrap_log_chars([], _Width, true, Acc) ->
    lists:reverse([<<>> | Acc]);
wrap_log_chars([], _Width, false, Acc) ->
    lists:reverse(Acc);
wrap_log_chars(Chars, Width, FirstLine, Acc) ->
    Prefix = case FirstLine of
        true -> "";
        false -> "  "
    end,
    LineWidth = case FirstLine of
        true -> Width;
        false -> max(8, Width - length(Prefix))
    end,
    {LineChars, Rest} = lists:split(min(length(Chars), LineWidth), Chars),
    Line = unicode:characters_to_binary([Prefix, LineChars]),
    wrap_log_chars(Rest, Width, false, [Line | Acc]).

log_title(ActiveItem, LogWrap, LogFullscreen) ->
    lists:flatten(io_lib:format("Logs (~s) [w:~s f:~s]", [
        ActiveItem,
        on_off(LogWrap),
        on_off(LogFullscreen)
    ])).

on_off(true) -> "on";
on_off(false) -> "off".

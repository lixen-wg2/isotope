%%%-------------------------------------------------------------------
%%% @doc Demo Tree Page - Supervision tree with dummy data
%%% @end
%%%-------------------------------------------------------------------
-module(demo_tree).

-behaviour(iso_callback).

-include_lib("isotope/include/iso_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    {ok, #{}}.

view(_State) ->
    #vbox{children = [
        %% Header
        #header{
            title = "Supervision Tree",
            subtitle = "kernel",
            items = [{"Supervisors", "5"}, {"Workers", "12"}]
        },
        
        %% Tree view
        #tree{
            id = sup_tree,
            height = fill,
            focusable = true,
            selected = kernel_sup,
            nodes = [
                #tree_node{
                    id = kernel_sup,
                    label = "kernel_sup",
                    icon = <<"🌳"/utf8>>,
                    expanded = true,
                    children = [
                        #tree_node{
                            id = code_server,
                            label = "code_server",
                            icon = <<"🔧"/utf8>>
                        },
                        #tree_node{
                            id = file_server,
                            label = "file_server_2",
                            icon = <<"📄"/utf8>>
                        },
                        #tree_node{
                            id = standard_error_sup,
                            label = "standard_error_sup",
                            icon = <<"🚨"/utf8>>,
                            expanded = true,
                            children = [
                                #tree_node{
                                    id = standard_error,
                                    label = "standard_error",
                                    icon = <<"📝"/utf8>>
                                }
                            ]
                        },
                        #tree_node{
                            id = user_sup,
                            label = "user_sup",
                            icon = <<"👥"/utf8>>,
                            expanded = false,
                            children = [
                                #tree_node{id = user, label = "user", icon = <<"👤"/utf8>>},
                                #tree_node{id = user_drv, label = "user_drv", icon = <<"🔌"/utf8>>}
                            ]
                        },
                        #tree_node{
                            id = logger_sup,
                            label = "logger_sup",
                            icon = <<"📦"/utf8>>,
                            expanded = true,
                            children = [
                                #tree_node{id = logger, label = "logger", icon = <<"🪵"/utf8>>},
                                #tree_node{id = logger_handler_watcher, label = "logger_handler_watcher", icon = <<"👁"/utf8>>}
                            ]
                        }
                    ]
                }
            ]
        },

        %% Status bar
        #status_bar{
            items = [
                {"H", "Home"},
                {"Up/Down", "Select"},
                {"Left/Right", "Collapse/Expand"},
                {"Enter", "Toggle"},
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

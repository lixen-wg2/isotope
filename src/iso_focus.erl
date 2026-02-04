%%%-------------------------------------------------------------------
%%% @doc Focus management for Isotope.
%%%
%%% Two-level focus model:
%%% - Tab/Shift+Tab: Navigate between containers (box, tabs)
%%% - Arrow keys: Navigate between elements within focused container
%%% @end
%%%-------------------------------------------------------------------
-module(iso_focus).

-include("iso_elements.hrl").

-export([collect_focusable/1, next_focus/2, prev_focus/2, find_element/2]).
-export([collect_containers/1, collect_children/2]).

%%====================================================================
%% API
%%====================================================================

%% @doc Collect all focusable container IDs (for Tab navigation).
-spec collect_containers(tuple()) -> [term()].
collect_containers(Element) ->
    lists:flatten(do_collect_containers(Element)).

%% @doc Collect focusable children within a container (for arrow navigation).
-spec collect_children(tuple(), term()) -> [term()].
collect_children(Tree, ContainerId) ->
    case find_element(Tree, ContainerId) of
        undefined -> [];
        Container -> lists:flatten(do_collect_children(Container))
    end.

%% @doc Collect all focusable element IDs from the tree in order (legacy).
-spec collect_focusable(tuple()) -> [term()].
collect_focusable(Element) ->
    lists:flatten(do_collect(Element)).

%% @doc Get the next focusable element ID after CurrentId.
%% If CurrentId is undefined or not found, returns the first focusable.
-spec next_focus([term()], term()) -> term() | undefined.
next_focus([], _CurrentId) ->
    undefined;
next_focus(FocusableIds, undefined) ->
    hd(FocusableIds);
next_focus(FocusableIds, CurrentId) ->
    case find_next(FocusableIds, CurrentId) of
        undefined -> hd(FocusableIds);  %% Wrap around
        NextId -> NextId
    end.

%% @doc Get the previous focusable element ID before CurrentId.
-spec prev_focus([term()], term()) -> term() | undefined.
prev_focus([], _CurrentId) ->
    undefined;
prev_focus(FocusableIds, undefined) ->
    lists:last(FocusableIds);
prev_focus(FocusableIds, CurrentId) ->
    case find_prev(FocusableIds, CurrentId) of
        undefined -> lists:last(FocusableIds);  %% Wrap around
        PrevId -> PrevId
    end.

%% @doc Find an element by ID in the tree.
-spec find_element(tuple(), term()) -> tuple() | undefined.
find_element(Element, Id) ->
    do_find(Element, Id).

%%====================================================================
%% Internal - Container collection (for Tab navigation)
%%====================================================================

%% Containers are: box with id, tabs with id
do_collect_containers(#box{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_containers(#box{children = Children}) -> [do_collect_containers(C) || C <- Children];
do_collect_containers(#tabs{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_containers(#tabs{}) -> [];
do_collect_containers(#panel{children = Children}) -> [do_collect_containers(C) || C <- Children];
do_collect_containers(#vbox{children = Children}) -> [do_collect_containers(C) || C <- Children];
do_collect_containers(#hbox{children = Children}) -> [do_collect_containers(C) || C <- Children];
do_collect_containers(_) -> [].

%%====================================================================
%% Internal - Children collection (for arrow navigation within container)
%%====================================================================

do_collect_children(#box{children = Children}) ->
    lists:flatten([do_collect_child(C) || C <- Children]);
do_collect_children(#tabs{tabs = TabList}) ->
    %% For tabs, the "children" are the tab IDs themselves
    [T#tab.id || T <- TabList];
do_collect_children(_) -> [].

%% Collect focusable elements (not containers)
do_collect_child(#button{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_child(#button{}) -> [];
do_collect_child(#input{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_child(#input{}) -> [];
do_collect_child(#table{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_child(#table{}) -> [];
do_collect_child(#vbox{children = Children}) -> [do_collect_child(C) || C <- Children];
do_collect_child(#hbox{children = Children}) -> [do_collect_child(C) || C <- Children];
do_collect_child(_) -> [].

%%====================================================================
%% Internal - Legacy collection (all focusable)
%%====================================================================

do_collect(#text{}) -> [];
do_collect(#button{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect(#button{}) -> [];
do_collect(#input{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect(#input{}) -> [];
do_collect(#table{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect(#table{}) -> [];
do_collect(#tabs{id = Id, focusable = true, tabs = TabList, active_tab = ActiveTab0}) when Id =/= undefined ->
    %% Collect tabs widget itself, plus focusable elements in active tab content
    ActiveTab = case ActiveTab0 of
        undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
        _ -> ActiveTab0
    end,
    ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end,
    [Id | [do_collect(C) || C <- ActiveContent]];
do_collect(#tabs{tabs = TabList, active_tab = ActiveTab0}) ->
    %% Not focusable itself, but collect from active tab content
    ActiveTab = case ActiveTab0 of
        undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
        _ -> ActiveTab0
    end,
    ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end,
    [do_collect(C) || C <- ActiveContent];
do_collect(#box{children = Children}) -> [do_collect(C) || C <- Children];
do_collect(#panel{children = Children}) -> [do_collect(C) || C <- Children];
do_collect(#vbox{children = Children}) -> [do_collect(C) || C <- Children];
do_collect(#hbox{children = Children}) -> [do_collect(C) || C <- Children];
do_collect(_) -> [].

find_next([CurrentId, NextId | _], CurrentId) -> NextId;
find_next([_ | Rest], CurrentId) -> find_next(Rest, CurrentId);
find_next(_, _) -> undefined.

find_prev([PrevId, CurrentId | _], CurrentId) -> PrevId;
find_prev([_ | Rest], CurrentId) -> find_prev(Rest, CurrentId);
find_prev(_, _) -> undefined.

do_find(#button{id = Id} = E, Id) -> E;
do_find(#input{id = Id} = E, Id) -> E;
do_find(#table{id = Id} = E, Id) -> E;
do_find(#tabs{id = Id} = E, Id) -> E;
do_find(#tabs{tabs = TabList, active_tab = ActiveTab0}, Id) ->
    %% Search in active tab content (default to first tab if undefined)
    ActiveTab = case ActiveTab0 of
        undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
        _ -> ActiveTab0
    end,
    ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end,
    find_in_children(ActiveContent, Id);
do_find(#box{id = Id} = E, Id) -> E;
do_find(#box{children = Children}, Id) -> find_in_children(Children, Id);
do_find(#panel{children = Children}, Id) -> find_in_children(Children, Id);
do_find(#vbox{children = Children}, Id) -> find_in_children(Children, Id);
do_find(#hbox{children = Children}, Id) -> find_in_children(Children, Id);
do_find(_, _) -> undefined.

find_in_children([], _Id) -> undefined;
find_in_children([Child | Rest], Id) ->
    case do_find(Child, Id) of
        undefined -> find_in_children(Rest, Id);
        Found -> Found
    end.


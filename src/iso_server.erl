%%%-------------------------------------------------------------------
%%% @doc Isotope UI Server - Core TUI event loop and rendering.
%%%
%%% This module handles all the TUI machinery:
%%% - Input event handling (keyboard, mouse)
%%% - Focus management
%%% - Rendering
%%% - Modal overlays
%%%
%%% Users implement a callback module with:
%%% - init() -> {ok, State} | {ok, State, Tree}
%%% - view(State) -> Tree
%%% - handle_event(Event, State) -> {noreply, State} | {stop, Reason, State}
%%% @end
%%%-------------------------------------------------------------------
-module(iso_server).

-behaviour(gen_server).

-include("iso_elements.hrl").

%% API
-export([start_link/1, start_link/2, start_link/3, stop/1]).
-export([update/2, get_state/1, set_modal/2, close_modal/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(iso_state, {
    callback :: module(),          %% User callback module
    user_state :: term(),          %% User's state (typically a map)
    tree :: term(),                %% Current element tree
    bounds :: #bounds{},           %% Screen bounds
    focused_container :: term(),   %% Currently focused container (Tab navigation)
    focused_child :: term(),       %% Currently focused child within container (Arrow navigation)
    container_ids :: [term()],     %% List of container IDs (for Tab)
    modal :: undefined | term(),   %% Current modal overlay
    debug_event :: undefined | term()  %% Last unhandled event for debug display
}).

%%====================================================================
%% API
%%====================================================================

-spec start_link(module()) -> {ok, pid()} | {error, term()}.
start_link(CallbackModule) ->
    start_link(CallbackModule, #{}).

-spec start_link(module(), term()) -> {ok, pid()} | {error, term()}.
start_link(CallbackModule, InitArg) ->
    gen_server:start_link(?MODULE, {undefined, CallbackModule, InitArg}, []).

-spec start_link({local, atom()} | {global, term()}, module(), term()) -> {ok, pid()} | {error, term()}.
start_link(Name, CallbackModule, InitArg) ->
    gen_server:start_link(Name, ?MODULE, {Name, CallbackModule, InitArg}, []).

-spec stop(pid() | atom()) -> ok.
stop(Server) ->
    gen_server:stop(Server).

%% Update user state and re-render
-spec update(pid() | atom(), fun((term()) -> term())) -> ok.
update(Server, UpdateFun) ->
    gen_server:cast(Server, {update, UpdateFun}).

%% Get current user state
-spec get_state(pid() | atom()) -> term().
get_state(Server) ->
    gen_server:call(Server, get_state).

%% Show a modal overlay
-spec set_modal(pid() | atom(), term()) -> ok.
set_modal(Server, Modal) ->
    gen_server:cast(Server, {set_modal, Modal}).

%% Close current modal
-spec close_modal(pid() | atom()) -> ok.
close_modal(Server) ->
    gen_server:cast(Server, close_modal).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init({_Name, CallbackModule, InitArg}) ->
    timer:sleep(100),  %% Give iso_tty time to initialize
    %% Register this process as the input target
    iso_input:set_target(self()),
    %% Get terminal size
    Bounds = case iso_tty:get_size() of
        {ok, {Cols, Rows}} -> #bounds{width = Cols, height = Rows};
        _ -> #bounds{width = 80, height = 24}
    end,
    %% Initialize user state
    {UserState, Tree} = case CallbackModule:init(InitArg) of
        {ok, S} -> {S, CallbackModule:view(S)};
        {ok, S, T} -> {S, T}
    end,
    %% Collect containers (for Tab navigation)
    ContainerIds = iso_focus:collect_containers(Tree),
    FocusedContainer = case ContainerIds of
        [First | _] -> First;
        [] -> undefined
    end,
    %% Collect children within first container (for Arrow navigation)
    ChildIds = iso_focus:collect_children(Tree, FocusedContainer),
    FocusedChild = case ChildIds of
        [FirstChild | _] -> FirstChild;
        [] -> undefined
    end,
    %% Initial render
    iso_tty:clear(),
    render_tree(Tree, Bounds, FocusedContainer, FocusedChild),
    {ok, #iso_state{
        callback = CallbackModule,
        user_state = UserState,
        tree = Tree,
        bounds = Bounds,
        focused_container = FocusedContainer,
        focused_child = FocusedChild,
        container_ids = ContainerIds,
        modal = undefined
    }}.

handle_call(get_state, _From, State = #iso_state{user_state = UserState}) ->
    {reply, UserState, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({update, UpdateFun}, State) ->
    NewState = do_update(UpdateFun, State),
    {noreply, NewState};
handle_cast({set_modal, Modal}, State) ->
    NewState = State#iso_state{modal = Modal},
    render_full(NewState),
    {noreply, NewState};
handle_cast(close_modal, State) ->
    NewState = State#iso_state{modal = undefined},
    render_full(NewState),
    {noreply, NewState};
handle_cast(_Msg, State) ->
    {noreply, State}.

%% Handle input events from iso_input
handle_info({input, Event}, State) ->
    handle_input(Event, State);
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    %% Cleanup terminal state (disable mouse, show cursor, exit alt screen)
    %% We catch errors in case iso_tty is already stopped
    catch iso_tty:cleanup(),
    %% Halt the VM cleanly after a short delay to allow cleanup to complete
    spawn(fun() ->
        timer:sleep(100),
        halt(0)
    end),
    ok.

%%====================================================================
%% Internal: Input handling
%%====================================================================

handle_input(escape, State = #iso_state{modal = Modal}) when Modal =/= undefined ->
    handle_close_modal(State);
handle_input({ctrl, $c}, State = #iso_state{callback = Cb, user_state = US}) ->
    case call_handler(Cb, quit, US) of
        {stop, _Reason, _NewUS} -> {stop, normal, State};
        _ -> {noreply, State}
    end;
handle_input(tab, State) ->
    handle_focus_next(State);
handle_input({key, btab}, State) ->
    handle_focus_prev(State);
handle_input(enter, State) ->
    handle_activate(State);
handle_input({key, Dir}, State) when Dir =:= up; Dir =:= down; Dir =:= left; Dir =:= right ->
    handle_arrow(Dir, State);
handle_input({char, Char}, State) when Char >= 32, Char < 127 ->
    handle_char_input(Char, State);
handle_input(backspace, State) ->
    handle_backspace(State);
handle_input({mouse, click, left, Col, Row}, State) ->
    handle_mouse_click(Col, Row, State);
handle_input({mouse, _, _, _, _}, State) ->
    {noreply, State};
handle_input(_Event, State = #iso_state{modal = Modal}) when Modal =/= undefined ->
    {noreply, State};
handle_input(Event, State) ->
    forward_event(Event, State).

%%====================================================================
%% Internal: Focus management (Tab = containers, Arrows = children)
%%====================================================================

handle_focus_next(State = #iso_state{container_ids = Ids, focused_container = Current, tree = Tree}) ->
    NewContainer = iso_focus:next_focus(Ids, Current),
    %% Get first child in new container
    ChildIds = iso_focus:collect_children(Tree, NewContainer),
    NewChild = case ChildIds of [First | _] -> First; [] -> undefined end,
    NewState = State#iso_state{focused_container = NewContainer, focused_child = NewChild},
    render_full(NewState),
    {noreply, NewState}.

handle_focus_prev(State = #iso_state{container_ids = Ids, focused_container = Current, tree = Tree}) ->
    NewContainer = iso_focus:prev_focus(Ids, Current),
    %% Get first child in new container
    ChildIds = iso_focus:collect_children(Tree, NewContainer),
    NewChild = case ChildIds of [First | _] -> First; [] -> undefined end,
    NewState = State#iso_state{focused_container = NewContainer, focused_child = NewChild},
    render_full(NewState),
    {noreply, NewState}.

handle_close_modal(State) ->
    NewState = State#iso_state{modal = undefined},
    render_full(NewState),
    {noreply, NewState}.

%%====================================================================
%% Internal: Element activation
%%====================================================================

handle_activate(State = #iso_state{focused_container = Container, focused_child = FocusedChild,
                                    tree = Tree, callback = Cb, user_state = US}) ->
    case iso_focus:find_element(Tree, FocusedChild) of
        #button{id = Id, on_click = Handler} ->
            case call_handler(Cb, {click, Id, Handler}, US) of
                {noreply, NewUS} ->
                    do_update(fun(_) -> NewUS end, State);
                {modal, Modal, NewUS} ->
                    NewState = State#iso_state{user_state = NewUS, modal = Modal},
                    render_full(NewState),
                    {noreply, NewState};
                {switch, NewModule, Args} ->
                    do_switch(NewModule, Args, State);
                {stop, Reason, _NewUS} ->
                    {stop, Reason, State}
            end;
        #input{id = Id, value = Value, on_submit = Handler} ->
            case call_handler(Cb, {submit, Id, Value, Handler}, US) of
                {noreply, NewUS} -> do_update(fun(_) -> NewUS end, State);
                {switch, NewModule, Args} -> do_switch(NewModule, Args, State);
                {stop, Reason, _NewUS} -> {stop, Reason, State}
            end;
        #table{id = Id, rows = Rows, selected_row = SelRow} ->
            %% Enter on a table - activate the selected row
            RowData = case SelRow >= 1 andalso SelRow =< length(Rows) of
                true -> lists:nth(SelRow, Rows);
                false -> []
            end,
            Event = {table_activate, Id, SelRow, RowData},
            case call_handler_with_debug(Cb, Event, US, State) of
                {unhandled, NewUS, NewState} ->
                    do_update(fun(_) -> NewUS end, NewState);
                {handled, {noreply, NewUS}, _} ->
                    do_update(fun(_) -> NewUS end, State);
                {handled, {modal, Modal, NewUS}, _} ->
                    NewState = State#iso_state{user_state = NewUS, modal = Modal},
                    render_full(NewState),
                    {noreply, NewState};
                {handled, {switch, NewModule, Args}, _} ->
                    do_switch(NewModule, Args, State);
                {handled, {stop, Reason, _NewUS}, _} ->
                    {stop, Reason, State}
            end;
        _ ->
            %% Check if we're in a tabs widget with a table (focused_child is tab id)
            handle_activate_in_tabs(Container, Tree, Cb, US, State)
    end.

%% Handle Enter when focused on a tab that contains a table
handle_activate_in_tabs(Container, Tree, Cb, US, State) ->
    case iso_focus:find_element(Tree, Container) of
        #tabs{tabs = TabList, active_tab = ActiveTab0} ->
            ActiveTab = case ActiveTab0 of
                undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
                _ -> ActiveTab0
            end,
            case lists:keyfind(ActiveTab, #tab.id, TabList) of
                #tab{content = Content} ->
                    case find_table_in_content(Content) of
                        {ok, #table{id = Id, rows = Rows, selected_row = SelRow}} ->
                            RowData = case SelRow >= 1 andalso SelRow =< length(Rows) of
                                true -> lists:nth(SelRow, Rows);
                                false -> []
                            end,
                            Event = {table_activate, Id, SelRow, RowData},
                            case call_handler_with_debug(Cb, Event, US, State) of
                                {unhandled, NewUS, NewState} ->
                                    do_update(fun(_) -> NewUS end, NewState);
                                {handled, {noreply, NewUS}, _} ->
                                    do_update(fun(_) -> NewUS end, State);
                                {handled, {modal, Modal, NewUS}, _} ->
                                    NewState = State#iso_state{user_state = NewUS, modal = Modal},
                                    render_full(NewState),
                                    {noreply, NewState};
                                {handled, {switch, NewModule, Args}, _} ->
                                    do_switch(NewModule, Args, State);
                                {handled, {stop, Reason, _NewUS}, _} ->
                                    {stop, Reason, State}
                            end;
                        false ->
                            {noreply, State}
                    end;
                false ->
                    {noreply, State}
            end;
        _ ->
            {noreply, State}
    end.

%%====================================================================
%% Internal: Arrow key navigation within container
%%====================================================================

handle_arrow(Dir, State = #iso_state{focused_container = Container, focused_child = Child,
                                      tree = Tree, callback = Cb, user_state = US}) ->
    %% Get children of current container
    ChildIds = iso_focus:collect_children(Tree, Container),
    case iso_focus:find_element(Tree, Container) of
        #tabs{id = Id, tabs = TabList, active_tab = ActiveTab} = Tabs ->
            %% For tabs: left/right navigates tabs, up/down navigates within active tab content
            case Dir of
                left ->
                    NewTabs = navigate_tabs(left, Tabs),
                    NewActiveTab = NewTabs#tabs.active_tab,
                    NewTree = iso_tree:update(Tree, Container, NewTabs),
                    NewUS = case call_handler(Cb, {tab_change, Id, NewActiveTab}, US) of
                        {noreply, S} -> S;
                        _ -> US
                    end,
                    NewState = State#iso_state{tree = NewTree, user_state = NewUS, focused_child = NewActiveTab},
                    render_full(NewState),
                    {noreply, NewState};
                right ->
                    NewTabs = navigate_tabs(right, Tabs),
                    NewActiveTab = NewTabs#tabs.active_tab,
                    NewTree = iso_tree:update(Tree, Container, NewTabs),
                    NewUS = case call_handler(Cb, {tab_change, Id, NewActiveTab}, US) of
                        {noreply, S} -> S;
                        _ -> US
                    end,
                    NewState = State#iso_state{tree = NewTree, user_state = NewUS, focused_child = NewActiveTab},
                    render_full(NewState),
                    {noreply, NewState};
                UpOrDown when UpOrDown =:= up; UpOrDown =:= down ->
                    %% Navigate within active tab content (e.g., table rows)
                    %% Default to first tab if active_tab is undefined
                    EffectiveTab = case ActiveTab of
                        undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
                        _ -> ActiveTab
                    end,
                    case lists:keyfind(EffectiveTab, #tab.id, TabList) of
                        #tab{content = Content} ->
                            case find_table_in_content(Content) of
                                {ok, Table} ->
                                    NewTable = navigate_table(UpOrDown, Table),
                                    NewTabs = update_tab_content(Tabs, EffectiveTab, Table, NewTable),
                                    NewTree = iso_tree:update(Tree, Container, NewTabs),
                                    NewState = State#iso_state{tree = NewTree},
                                    render_full(NewState),
                                    {noreply, NewState};
                                false ->
                                    {noreply, State}
                            end;
                        false ->
                            {noreply, State}
                    end
            end;
        #box{} ->
            %% For box, up/down navigates between children
            case Dir of
                up ->
                    NewChild = iso_focus:prev_focus(ChildIds, Child),
                    NewState = State#iso_state{focused_child = NewChild},
                    render_full(NewState),
                    {noreply, NewState};
                down ->
                    NewChild = iso_focus:next_focus(ChildIds, Child),
                    NewState = State#iso_state{focused_child = NewChild},
                    render_full(NewState),
                    {noreply, NewState};
                _ ->
                    {noreply, State}
            end;
        _ ->
            {noreply, State}
    end.

%% Find first table in tab content
find_table_in_content([]) -> false;
find_table_in_content([#table{} = T | _]) -> {ok, T};
find_table_in_content([_ | Rest]) -> find_table_in_content(Rest).

%% Navigate table rows with up/down
navigate_table(down, #table{rows = Rows, selected_row = Sel, scroll_offset = Off, height = H} = T) ->
    NumRows = length(Rows),
    NewSel = min(NumRows, Sel + 1),
    VisibleH = case H of auto -> 5; _ -> H - 4 end,
    NewOff = if NewSel > Off + VisibleH -> Off + 1; true -> Off end,
    T#table{selected_row = NewSel, scroll_offset = NewOff};
navigate_table(up, #table{selected_row = Sel, scroll_offset = Off} = T) ->
    NewSel = max(1, Sel - 1),
    NewOff = if NewSel < Off + 1 -> max(0, Off - 1); true -> Off end,
    T#table{selected_row = NewSel, scroll_offset = NewOff};
navigate_table(_, T) -> T.

%% Update table in tab content
update_tab_content(#tabs{tabs = TabList} = Tabs, TabId, OldTable, NewTable) ->
    NewTabList = lists:map(
        fun(#tab{id = Id, content = Content} = Tab) when Id =:= TabId ->
            NewContent = lists:map(
                fun(El) when El =:= OldTable -> NewTable;
                   (El) -> El
                end, Content),
            Tab#tab{content = NewContent};
           (Tab) -> Tab
        end, TabList),
    Tabs#tabs{tabs = NewTabList}.

navigate_tabs(left, #tabs{tabs = TabList, active_tab = Active0} = T) ->
    TabIds = [Tab#tab.id || Tab <- TabList],
    Active = resolve_active_tab(Active0, TabIds),
    T#tabs{active_tab = prev_in_list(TabIds, Active)};
navigate_tabs(right, #tabs{tabs = TabList, active_tab = Active0} = T) ->
    TabIds = [Tab#tab.id || Tab <- TabList],
    Active = resolve_active_tab(Active0, TabIds),
    T#tabs{active_tab = next_in_list(TabIds, Active)}.

resolve_active_tab(undefined, [First | _]) -> First;
resolve_active_tab(undefined, []) -> undefined;
resolve_active_tab(Active, _) -> Active.

next_in_list([H], _) -> H;
next_in_list([C, N | _], C) -> N;
next_in_list([_ | R], C) -> next_in_list(R, C);
next_in_list(L, _) -> hd(L).

prev_in_list(L, C) -> next_in_list(lists:reverse(L), C).

%%====================================================================
%% Internal: Text input handling
%%====================================================================

handle_char_input(Char, State = #iso_state{focused_child = FocusedChild, tree = Tree,
                                            callback = Cb, user_state = US}) ->
    case iso_focus:find_element(Tree, FocusedChild) of
        #input{id = Id, value = Value, cursor_pos = Pos} = Input ->
            ValueBin = iolist_to_binary([Value]),
            {Before, After} = split_at(ValueBin, Pos),
            NewValue = <<Before/binary, Char, After/binary>>,
            NewInput = Input#input{value = NewValue, cursor_pos = Pos + 1},
            NewTree = iso_tree:update(Tree, FocusedChild, NewInput),
            %% Notify callback of input change
            NewUS = case call_handler(Cb, {input, Id, NewValue}, US) of
                {noreply, S} -> S;
                _ -> US
            end,
            NewState = State#iso_state{tree = NewTree, user_state = NewUS},
            render_full(NewState),
            {noreply, NewState};
        _ ->
            forward_event({char, Char}, State)
    end.

handle_backspace(State = #iso_state{focused_child = FocusedChild, tree = Tree,
                                     callback = Cb, user_state = US}) ->
    case iso_focus:find_element(Tree, FocusedChild) of
        #input{id = Id, value = Value, cursor_pos = Pos} = Input when Pos > 0 ->
            ValueBin = iolist_to_binary([Value]),
            {Before, After} = split_at(ValueBin, Pos),
            NewBefore = case byte_size(Before) of
                0 -> <<>>;
                _ -> binary:part(Before, 0, byte_size(Before) - 1)
            end,
            NewValue = <<NewBefore/binary, After/binary>>,
            NewInput = Input#input{value = NewValue, cursor_pos = max(0, Pos - 1)},
            NewTree = iso_tree:update(Tree, FocusedChild, NewInput),
            %% Notify callback of input change
            NewUS = case call_handler(Cb, {input, Id, NewValue}, US) of
                {noreply, S} -> S;
                _ -> US
            end,
            NewState = State#iso_state{tree = NewTree, user_state = NewUS},
            render_full(NewState),
            {noreply, NewState};
        _ ->
            {noreply, State}
    end.

split_at(Bin, Pos) ->
    Size = byte_size(Bin),
    case Pos >= Size of
        true -> {Bin, <<>>};
        false -> {binary:part(Bin, 0, Pos), binary:part(Bin, Pos, Size - Pos)}
    end.

%%====================================================================
%% Internal: Mouse handling
%%====================================================================

handle_mouse_click(Col, Row, State = #iso_state{tree = Tree, bounds = Bounds,
                                                callback = Cb, user_state = US}) ->
    case iso_hit:find_at(Tree, Col, Row, Bounds) of
        {tab, TabsId, TabId} ->
            case iso_focus:find_element(Tree, TabsId) of
                #tabs{} = Tabs ->
                    NewTabs = Tabs#tabs{active_tab = TabId},
                    NewTree = iso_tree:update(Tree, TabsId, NewTabs),
                    NewState = State#iso_state{tree = NewTree,
                                               focused_container = TabsId,
                                               focused_child = TabId},
                    render_full(NewState),
                    {noreply, NewState};
                _ -> {noreply, State}
            end;
        {tabs_container, TabsId} ->
            %% Clicked on tabs widget but not on a specific tab
            ChildIds = iso_focus:collect_children(Tree, TabsId),
            FirstChild = case ChildIds of [C|_] -> C; [] -> undefined end,
            NewState = State#iso_state{focused_container = TabsId, focused_child = FirstChild},
            render_full(NewState),
            {noreply, NewState};
        {box, BoxId} ->
            %% Clicked on box container (border or empty space)
            ChildIds = iso_focus:collect_children(Tree, BoxId),
            FirstChild = case ChildIds of [C|_] -> C; [] -> undefined end,
            NewState = State#iso_state{focused_container = BoxId, focused_child = FirstChild},
            render_full(NewState),
            {noreply, NewState};
        {button, ButtonId} ->
            %% Find which container owns this button
            Container = find_parent_container(Tree, ButtonId),
            NewState = State#iso_state{focused_container = Container, focused_child = ButtonId},
            handle_activate(NewState);
        {input, InputId} ->
            %% Find which container owns this input
            Container = find_parent_container(Tree, InputId),
            NewState = State#iso_state{focused_container = Container, focused_child = InputId},
            render_full(NewState),
            {noreply, NewState};
        {table_row, TableId, RowIdx} ->
            %% Click on a specific table row - select it and notify callback
            case iso_focus:find_element(Tree, TableId) of
                #table{} = Table ->
                    NewTable = Table#table{selected_row = RowIdx},
                    NewTree = iso_tree:update(Tree, TableId, NewTable),
                    %% Find which container owns this table
                    Container = find_parent_container(Tree, TableId),
                    NewState = State#iso_state{tree = NewTree,
                                               focused_container = Container,
                                               focused_child = TableId},
                    %% Notify callback but don't regenerate tree (would reset selection)
                    _ = call_handler(Cb, {table_select, TableId, RowIdx}, US),
                    render_full(NewState),
                    {noreply, NewState};
                _ -> {noreply, State}
            end;
        {table, TableId} ->
            %% Clicked on table but not on a specific row
            Container = find_parent_container(Tree, TableId),
            NewState = State#iso_state{focused_container = Container, focused_child = TableId},
            render_full(NewState),
            {noreply, NewState};
        not_found ->
            forward_event({mouse, click, Col, Row}, State)
    end.

%%====================================================================
%% Internal: State update and rendering
%%====================================================================

do_update(UpdateFun, State = #iso_state{callback = Cb, user_state = US,
                                         focused_container = Container,
                                         focused_child = Child}) ->
    NewUS = UpdateFun(US),
    NewTree = Cb:view(NewUS),
    %% Collect containers for Tab navigation
    ContainerIds = iso_focus:collect_containers(NewTree),
    NewContainer = case lists:member(Container, ContainerIds) of
        true -> Container;
        false -> case ContainerIds of [C|_] -> C; [] -> undefined end
    end,
    %% Collect children for arrow navigation (preserve current if still valid)
    ChildIds = iso_focus:collect_children(NewTree, NewContainer),
    NewChild = case lists:member(Child, ChildIds) of
        true -> Child;
        false -> case ChildIds of [Ch|_] -> Ch; [] -> undefined end
    end,
    NewState = State#iso_state{
        user_state = NewUS,
        tree = NewTree,
        focused_container = NewContainer,
        focused_child = NewChild,
        container_ids = ContainerIds
    },
    render_full(NewState),
    {noreply, NewState}.

%% Switch to a completely different callback module
do_switch(NewModule, Args, State) ->
    {ok, NewUS} = NewModule:init(Args),
    NewTree = NewModule:view(NewUS),
    %% Collect containers for Tab navigation
    ContainerIds = iso_focus:collect_containers(NewTree),
    NewContainer = case ContainerIds of [C|_] -> C; [] -> undefined end,
    %% Collect children for arrow navigation
    ChildIds = iso_focus:collect_children(NewTree, NewContainer),
    NewChild = case ChildIds of [Ch|_] -> Ch; [] -> undefined end,
    NewState = State#iso_state{
        callback = NewModule,
        user_state = NewUS,
        tree = NewTree,
        focused_container = NewContainer,
        focused_child = NewChild,
        container_ids = ContainerIds,
        modal = undefined,
        debug_event = undefined
    },
    %% Clear screen before rendering new view (different layout may leave garbage)
    iso_tty:clear(),
    render_full(NewState),
    {noreply, NewState}.

forward_event(Event, State = #iso_state{callback = Cb, user_state = US}) ->
    %% Store event in debug_event for display
    StateWithDebug = State#iso_state{debug_event = Event},
    case call_handler(Cb, {event, Event}, US) of
        {noreply, NewUS} -> do_update(fun(_) -> NewUS end, StateWithDebug);
        {unhandled, NewUS} -> do_update(fun(_) -> NewUS end, StateWithDebug);
        {switch, NewModule, Args} -> do_switch(NewModule, Args, State);
        {stop, Reason, _NewUS} -> {stop, Reason, StateWithDebug}
    end.

call_handler(Cb, Event, US) ->
    case erlang:function_exported(Cb, handle_event, 2) of
        true -> Cb:handle_event(Event, US);
        false -> {noreply, US}
    end.

%% Call handler and set debug_event if unhandled
call_handler_with_debug(Cb, Event, US, State) ->
    case erlang:function_exported(Cb, handle_event, 2) of
        true ->
            case Cb:handle_event(Event, US) of
                {unhandled, NewUS} ->
                    {unhandled, NewUS, State#iso_state{debug_event = Event}};
                Other ->
                    {handled, Other, State}
            end;
        false ->
            {unhandled, US, State#iso_state{debug_event = Event}}
    end.

%% Find parent container for an element
find_parent_container(Tree, ChildId) ->
    find_parent_container(Tree, ChildId, undefined).

find_parent_container(#box{id = Id, focusable = true, children = Children}, ChildId, _Parent) ->
    case contains_child(Children, ChildId) of
        true -> Id;
        false ->
            lists:foldl(fun(C, Acc) ->
                case Acc of undefined -> find_parent_container(C, ChildId, Id); _ -> Acc end
            end, undefined, Children)
    end;
find_parent_container(#box{children = Children}, ChildId, Parent) ->
    lists:foldl(fun(C, Acc) ->
        case Acc of undefined -> find_parent_container(C, ChildId, Parent); _ -> Acc end
    end, undefined, Children);
find_parent_container(#tabs{id = Id, focusable = true}, _ChildId, _Parent) ->
    %% For tabs, the tabs widget is the container
    Id;
find_parent_container(#panel{children = Children}, ChildId, Parent) ->
    lists:foldl(fun(C, Acc) ->
        case Acc of undefined -> find_parent_container(C, ChildId, Parent); _ -> Acc end
    end, undefined, Children);
find_parent_container(#vbox{children = Children}, ChildId, Parent) ->
    lists:foldl(fun(C, Acc) ->
        case Acc of undefined -> find_parent_container(C, ChildId, Parent); _ -> Acc end
    end, undefined, Children);
find_parent_container(#hbox{children = Children}, ChildId, Parent) ->
    lists:foldl(fun(C, Acc) ->
        case Acc of undefined -> find_parent_container(C, ChildId, Parent); _ -> Acc end
    end, undefined, Children);
find_parent_container(_, _, Parent) -> Parent.

contains_child([], _) -> false;
contains_child([#button{id = Id} | _], Id) -> true;
contains_child([#input{id = Id} | _], Id) -> true;
contains_child([#table{id = Id} | _], Id) -> true;
contains_child([_ | Rest], Id) -> contains_child(Rest, Id).

render_tree(Tree, Bounds, FocusedContainer, FocusedChild) ->
    iso_tty:write(iso_render:render_two_level(Tree, Bounds, FocusedContainer, FocusedChild)).

render_full(#iso_state{tree = Tree, bounds = Bounds,
                       focused_container = Container, focused_child = Child,
                       modal = Modal, debug_event = DebugEvent}) ->
    %% Always clear the debug line first
    clear_debug_row(Bounds),
    %% Don't clear screen - just redraw in place to avoid blinking
    case Modal of
        undefined ->
            iso_tty:write(iso_render:render_two_level(Tree, Bounds, Container, Child));
        _ ->
            iso_tty:write(iso_render:render_dimmed(Tree, Bounds, Child)),
            iso_tty:write(iso_render:render_two_level(Modal, Bounds, undefined, undefined))
    end,
    %% Render debug row at the bottom if there's an event
    render_debug_row(Bounds, DebugEvent).

clear_debug_row(#bounds{height = Height}) ->
    iso_tty:write([
        io_lib:format("\e[~B;1H", [Height]),  %% Move to last row
        "\e[2K"                                %% Clear line
    ]).

render_debug_row(_Bounds, undefined) ->
    ok;
render_debug_row(#bounds{width = Width, height = Height}, Event) ->
    DebugStr = iolist_to_binary(io_lib:format("~p", [Event])),
    %% Truncate if too long
    MaxLen = max(0, Width - 10),
    TruncatedStr = case byte_size(DebugStr) > MaxLen of
        true -> <<(binary:part(DebugStr, 0, MaxLen))/binary, "...">>;
        false -> DebugStr
    end,
    iso_tty:write([
        io_lib:format("\e[~B;1H", [Height]),  %% Move to last row
        "\e[2m",                               %% Dim style
        "[DEBUG] ", TruncatedStr,
        "\e[0m"                                %% Reset style
    ]).


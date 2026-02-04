%%%-------------------------------------------------------------------
%%% @doc Isotope Hit Testing - Find elements at screen coordinates.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_hit).

-include("iso_elements.hrl").

-export([find_at/4]).

%% Find interactive element at given screen coordinates
-spec find_at(term(), integer(), integer(), #bounds{}) ->
    {tab, term(), term()} | {button, term()} | {input, term()} |
    {box, term()} | {tabs_container, term()} | {table, term()} |
    {table_row, term(), integer()} | not_found.
find_at(Tree, Col, Row, Bounds) ->
    find_at_impl(Tree, Col, Row, Bounds).

find_at_impl(#panel{children = Children}, Col, Row, Bounds) ->
    find_in_children(Children, Col, Row, Bounds);

find_at_impl(#tabs{id = Id, tabs = TabList, active_tab = ActiveTab0, x = X, y = Y, width = W, height = H, focusable = Focusable}, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; _ -> W end,
    Height = case H of auto -> Bounds#bounds.height - Y; _ -> H end,
    %% Check if click is on tab bar (first row of tabs widget)
    if
        Row =:= ActualY + 1, Col >= ActualX + 1, Col =< ActualX + Width ->
            case find_clicked_tab(TabList, Col - ActualX, 0) of
                {ok, TabId} -> {tab, Id, TabId};
                not_found when Focusable -> {tabs_container, Id};
                not_found -> not_found
            end;
        %% Click in content area - check active tab's content
        Row > ActualY + 1, Row =< ActualY + Height,
        Col >= ActualX + 1, Col =< ActualX + Width ->
            %% Find active tab and check its content
            ActiveTab = case ActiveTab0 of
                undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
                _ -> ActiveTab0
            end,
            ContentBounds = #bounds{x = ActualX + 1, y = ActualY + 2,
                                    width = Width - 2, height = Height - 3},
            case find_tab_content(TabList, ActiveTab) of
                {ok, Content} ->
                    case find_in_children(Content, Col, Row, ContentBounds) of
                        not_found when Focusable -> {tabs_container, Id};
                        not_found -> not_found;
                        Found -> Found
                    end;
                not_found when Focusable -> {tabs_container, Id};
                not_found -> not_found
            end;
        true -> not_found
    end;

find_at_impl(#button{id = Id, x = X, y = Y, width = W, label = Label}, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    LabelLen = string:length(unicode:characters_to_list(iolist_to_binary([Label]))),
    Width = case W of auto -> LabelLen + 4; _ -> W end,
    if
        Row =:= ActualY + 1, Col >= ActualX + 1, Col =< ActualX + Width ->
            {button, Id};
        true -> not_found
    end;

find_at_impl(#input{id = Id, x = X, y = Y, width = W}, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> 20; _ -> W end,
    if
        Row =:= ActualY + 1, Col >= ActualX + 1, Col =< ActualX + Width ->
            {input, Id};
        true -> not_found
    end;

find_at_impl(#box{id = Id, children = Children, x = X, y = Y, width = W, height = H, focusable = Focusable}, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; _ -> W end,
    Height = case H of auto -> Bounds#bounds.height - Y; _ -> H end,
    ChildBounds = Bounds#bounds{x = ActualX + 1, y = ActualY + 1},
    %% First check if we hit a child element
    case find_in_children(Children, Col, Row, ChildBounds) of
        not_found when Focusable,
                       Row > ActualY, Row =< ActualY + Height,
                       Col > ActualX, Col =< ActualX + Width ->
            %% Click is inside the box but not on a child - return box container
            {box, Id};
        not_found -> not_found;
        Found -> Found
    end;

find_at_impl(#vbox{children = Children, x = X, y = Y}, Col, Row, Bounds) ->
    ChildBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    find_in_children_vbox(Children, Col, Row, ChildBounds);

find_at_impl(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Col, Row, Bounds) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    %% Calculate remaining width for auto-sized children (same as render)
    TotalSpacing = max(0, (length(Children) - 1) * Spacing),
    FixedWidth = lists:sum([case element_fixed_width(C) of auto -> 0; W -> W end || C <- Children]),
    RemainingWidth = max(0, StartBounds#bounds.width - FixedWidth - TotalSpacing),
    find_in_children_hbox(Children, Col, Row, StartBounds, Spacing, RemainingWidth);

find_at_impl(#table{id = Id, x = X, y = Y, width = W, height = H, border = Border,
                    show_header = ShowHeader, scroll_offset = ScrollOffset, rows = Rows}, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; _ -> W end,
    Height = case H of auto -> min(length(Rows) + 3, Bounds#bounds.height - Y); _ -> H end,
    BorderOffset = case Border of none -> 0; _ -> 1 end,
    HeaderOffset = case ShowHeader of true -> 2; false -> 0 end,
    %% Check if click is within table bounds
    if
        Col >= ActualX + BorderOffset, Col =< ActualX + Width - BorderOffset,
        Row > ActualY + BorderOffset + HeaderOffset, Row =< ActualY + Height - BorderOffset ->
            %% Calculate which row was clicked
            ClickedRowIdx = Row - ActualY - BorderOffset - HeaderOffset + ScrollOffset,
            if
                ClickedRowIdx >= 1, ClickedRowIdx =< length(Rows) ->
                    {table_row, Id, ClickedRowIdx};
                true ->
                    {table, Id}
            end;
        Col >= ActualX, Col =< ActualX + Width,
        Row >= ActualY, Row =< ActualY + Height ->
            {table, Id};
        true ->
            not_found
    end;

find_at_impl(_, _, _, _) -> not_found.

find_in_children([], _, _, _) -> not_found;
find_in_children([Child | Rest], Col, Row, Bounds) ->
    case find_at_impl(Child, Col, Row, Bounds) of
        not_found -> find_in_children(Rest, Col, Row, Bounds);
        Found -> Found
    end.

find_clicked_tab([], _, _) -> not_found;
find_clicked_tab([#tab{id = Id, label = Label} | Rest], ClickCol, CurrentX) ->
    LabelLen = string:length(unicode:characters_to_list(iolist_to_binary([Label]))),
    TabWidth = LabelLen + 3,  %% " Label " + separator
    if
        ClickCol >= CurrentX, ClickCol < CurrentX + TabWidth ->
            {ok, Id};
        true ->
            find_clicked_tab(Rest, ClickCol, CurrentX + TabWidth)
    end.

%% Find content of active tab
find_tab_content([], _) -> not_found;
find_tab_content([#tab{id = Id, content = Content} | _], Id) -> {ok, Content};
find_tab_content([_ | Rest], ActiveTab) -> find_tab_content(Rest, ActiveTab).

%% Find in hbox children with proper width calculation
find_in_children_hbox([], _, _, _, _, _) -> not_found;
find_in_children_hbox([Child | Rest], Col, Row, Bounds, Spacing, RemainingWidth) ->
    ChildWidth = case element_fixed_width(Child) of
        auto -> RemainingWidth;
        W -> W
    end,
    ChildBounds = Bounds#bounds{width = ChildWidth},
    case find_at_impl(Child, Col, Row, ChildBounds) of
        not_found ->
            NextBounds = Bounds#bounds{x = Bounds#bounds.x + ChildWidth + Spacing},
            find_in_children_hbox(Rest, Col, Row, NextBounds, Spacing, RemainingWidth);
        Found -> Found
    end.

%% Find in vbox children with proper y offset
find_in_children_vbox([], _, _, _) -> not_found;
find_in_children_vbox([Child | Rest], Col, Row, Bounds) ->
    ChildHeight = element_height(Child),
    case find_at_impl(Child, Col, Row, Bounds) of
        not_found ->
            NextBounds = Bounds#bounds{y = Bounds#bounds.y + ChildHeight},
            find_in_children_vbox(Rest, Col, Row, NextBounds);
        Found -> Found
    end.

%% Returns the fixed width of an element, or 'auto' if it should fill remaining space
element_fixed_width(#box{width = W}) -> W;
element_fixed_width(#tabs{width = W}) -> W;
element_fixed_width(#table{width = W}) -> W;
element_fixed_width(#text{content = C}) -> byte_size(iolist_to_binary([C]));
element_fixed_width(#button{width = auto, label = L}) -> byte_size(iolist_to_binary([L])) + 4;
element_fixed_width(#button{width = W}) -> W;
element_fixed_width(#input{width = auto}) -> 22;
element_fixed_width(#input{width = W}) -> W;
element_fixed_width(_) -> auto.

element_height(#text{}) -> 1;
element_height(#button{}) -> 1;
element_height(#input{}) -> 1;
element_height(_) -> 1.

%%%-------------------------------------------------------------------
%%% @doc Isotope Renderer
%%%
%%% Renders element trees to ANSI escape sequences.
%%% Each element is rendered within its calculated bounds.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_render).

-include("iso_elements.hrl").

-export([render/2, render_to_tty/2, render_with_focus/3, render_dimmed/3]).
-export([render_two_level/4]).
-export([style_to_ansi/1, reset_style/0]).

%%====================================================================
%% API
%%====================================================================

%% @doc Render an element tree to iolist within given bounds.
-spec render(tuple(), #bounds{}) -> iolist().
render(Element, _Bounds) when not is_tuple(Element) ->
    [];
render(#text{visible = false}, _Bounds) ->
    [];
render(#text{} = Text, Bounds) ->
    render_text(Text, Bounds);
render(#box{visible = false}, _Bounds) ->
    [];
render(#box{} = Box, Bounds) ->
    render_box(Box, Bounds);
render(#panel{visible = false}, _Bounds) ->
    [];
render(#panel{children = Children}, Bounds) ->
    render_children(Children, Bounds);
render(#vbox{visible = false}, _Bounds) ->
    [];
render(#vbox{} = VBox, Bounds) ->
    render_vbox(VBox, Bounds);
render(#hbox{visible = false}, _Bounds) ->
    [];
render(#hbox{} = HBox, Bounds) ->
    render_hbox(HBox, Bounds);
render(#button{visible = false}, _Bounds) ->
    [];
render(#button{} = Button, Bounds) ->
    render_button(Button, Bounds, false);
render(#input{visible = false}, _Bounds) ->
    [];
render(#input{} = Input, Bounds) ->
    render_input(Input, Bounds, false);
render(_Unknown, _Bounds) ->
    [].

%% @doc Render element tree with focus tracking.
%% FocusedId is the id of the currently focused element.
-spec render_with_focus(tuple(), #bounds{}, term()) -> iolist().
render_with_focus(Element, Bounds, FocusedId) ->
    render_focused(Element, Bounds, FocusedId).

%% @doc Render element tree with dim styling (for background behind modal).
-spec render_dimmed(tuple(), #bounds{}, term()) -> iolist().
render_dimmed(Element, Bounds, FocusedId) ->
    render_focused_styled(Element, Bounds, FocusedId, #{dim => true}).

%% @doc Render with two-level focus: container and child.
%% Container gets a highlighted border, child gets element focus.
-spec render_two_level(tuple(), #bounds{}, term(), term()) -> iolist().
render_two_level(Element, Bounds, FocusedContainer, FocusedChild) ->
    render_two_level_impl(Element, Bounds, FocusedContainer, FocusedChild).

%% @doc Render element tree and write directly to iso_tty.
-spec render_to_tty(tuple(), #bounds{}) -> ok.
render_to_tty(Element, Bounds) ->
    Output = render(Element, Bounds),
    iso_tty:write(Output).

%%====================================================================
%% Internal - Text Rendering
%%====================================================================

render_text(#text{content = Content, style = Style, x = X, y = Y}, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    [
        move_to(ActualY + 1, ActualX + 1),  %% ANSI is 1-based
        style_to_ansi(Style),
        truncate_content(Content, Bounds#bounds.width - X),
        reset_style()
    ].

truncate_content(_Content, MaxWidth) when MaxWidth =< 0 ->
    <<>>;
truncate_content(Content, MaxWidth) ->
    Bin = iolist_to_binary([Content]),
    case byte_size(Bin) > MaxWidth of
        true -> binary:part(Bin, 0, MaxWidth);
        false -> Bin
    end.

%%====================================================================
%% Internal - Focused Rendering (traverses tree with focus context)
%%====================================================================

render_focused(#panel{children = Children}, Bounds, FocusedId) ->
    render_children_focused(Children, Bounds, FocusedId);
render_focused(#vbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, FocusedId) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    {Output, _} = lists:foldl(
        fun(Child, {Acc, CurrentY}) ->
            ChildBounds = StartBounds#bounds{y = CurrentY},
            ChildHeight = element_height(Child, ChildBounds),
            ChildOutput = render_focused(Child, ChildBounds, FocusedId),
            {[Acc, ChildOutput], CurrentY + ChildHeight + Spacing}
        end, {[], StartBounds#bounds.y}, Children),
    Output;
render_focused(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, FocusedId) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    TotalSpacing = max(0, (length(Children) - 1) * Spacing),
    FixedWidth = lists:sum([case element_fixed_width(C) of auto -> 0; W -> W end || C <- Children]),
    RemainingWidth = max(0, StartBounds#bounds.width - FixedWidth - TotalSpacing),
    {Output, _} = lists:foldl(
        fun(Child, {Acc, CurrentX}) ->
            ChildWidth = case element_fixed_width(Child) of
                auto -> RemainingWidth;
                W -> W
            end,
            ChildBounds = StartBounds#bounds{x = CurrentX, width = ChildWidth},
            ChildOutput = render_focused(Child, ChildBounds, FocusedId),
            {[Acc, ChildOutput], CurrentX + ChildWidth + Spacing}
        end, {[], StartBounds#bounds.x}, Children),
    Output;
render_focused(#box{border = Border, title = Title, children = Children,
                    style = Style, x = X, y = Y, width = W, height = H}, Bounds, FocusedId) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = resolve_size(W, Bounds#bounds.width - X),
    Height = resolve_size(H, Bounds#bounds.height - Y),
    {TL, TR, BL, BR, HZ, VT} = border_chars(Border),
    ChildBounds = #bounds{x = ActualX + 1, y = ActualY + 1,
                          width = max(1, Width - 2), height = max(1, Height - 2)},
    [
        style_to_ansi(Style),
        move_to(ActualY + 1, ActualX + 1),
        TL, render_title_line(Title, HZ, Width - 2), TR,
        [[move_to(ActualY + 1 + Row, ActualX + 1),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        move_to(ActualY + Height, ActualX + 1),
        BL, repeat_bin(HZ, Width - 2), BR,
        reset_style(),
        render_children_focused(Children, ChildBounds, FocusedId)
    ];
render_focused(#button{id = Id} = Button, Bounds, FocusedId) ->
    render_button(Button, Bounds, Id =:= FocusedId);
render_focused(#input{id = Id} = Input, Bounds, FocusedId) ->
    render_input(Input, Bounds, Id =:= FocusedId);
render_focused(#modal{} = Modal, Bounds, FocusedId) ->
    render_modal(Modal, Bounds, FocusedId);
render_focused(#table{id = Id} = Table, Bounds, FocusedId) ->
    render_table(Table, Bounds, Id =:= FocusedId);
render_focused(#tabs{id = Id} = Tabs, Bounds, FocusedId) ->
    render_tabs(Tabs, Bounds, Id =:= FocusedId, FocusedId);
render_focused(Element, Bounds, _FocusedId) ->
    render(Element, Bounds).

render_children_focused(Children, Bounds, FocusedId) ->
    [render_focused(Child, Bounds, FocusedId) || Child <- Children].

%%====================================================================
%% Internal - Two-Level Focus Rendering
%% FocusedContainer: ID of container that has Tab focus (box/tabs)
%% FocusedChild: ID of element within container that has arrow focus
%%====================================================================

render_two_level_impl(#panel{children = Children}, Bounds, Container, Child) ->
    render_children_two_level(Children, Bounds, Container, Child);
render_two_level_impl(#vbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, Container, Child) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    {Output, _} = lists:foldl(
        fun(Elem, {Acc, CurrentY}) ->
            ElemBounds = StartBounds#bounds{y = CurrentY},
            ElemHeight = element_height(Elem, ElemBounds),
            ElemOutput = render_two_level_impl(Elem, ElemBounds, Container, Child),
            {[Acc, ElemOutput], CurrentY + ElemHeight + Spacing}
        end, {[], StartBounds#bounds.y}, Children),
    Output;
render_two_level_impl(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, Container, Child) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    %% Calculate remaining width for auto-sized children
    TotalSpacing = max(0, (length(Children) - 1) * Spacing),
    FixedWidth = lists:sum([case element_fixed_width(C) of auto -> 0; W -> W end || C <- Children]),
    RemainingWidth = max(0, StartBounds#bounds.width - FixedWidth - TotalSpacing),
    {Output, _} = lists:foldl(
        fun(Elem, {Acc, CurrentX}) ->
            ElemWidth = case element_fixed_width(Elem) of
                auto -> RemainingWidth;
                W -> W
            end,
            ElemBounds = StartBounds#bounds{x = CurrentX, width = ElemWidth},
            ElemOutput = render_two_level_impl(Elem, ElemBounds, Container, Child),
            {[Acc, ElemOutput], CurrentX + ElemWidth + Spacing}
        end, {[], StartBounds#bounds.x}, Children),
    Output;
render_two_level_impl(#box{id = Id, children = Children, border = Border, title = Title,
                           style = Style, x = X, y = Y, width = W, height = H}, Bounds, Container, Child) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; _ -> W end,
    Height = case H of auto -> Bounds#bounds.height - Y; _ -> H end,
    ChildBounds = #bounds{x = ActualX + 1, y = ActualY + 1,
                          width = Width - 2, height = Height - 2},
    {TL, TR, BL, BR, HZ, VT} = border_chars(Border),
    %% Container focus: highlight border if this box is the focused container
    IsContainerFocused = Id =:= Container,
    BorderStyle = case IsContainerFocused of
        true -> maps:merge(Style, #{bold => true, fg => yellow});
        false -> Style
    end,
    [
        style_to_ansi(BorderStyle),
        move_to(ActualY + 1, ActualX + 1),
        TL, render_title_line(Title, HZ, Width - 2), TR,
        [[move_to(ActualY + 1 + Row, ActualX + 1),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        move_to(ActualY + Height, ActualX + 1),
        BL, repeat_bin(HZ, Width - 2), BR,
        reset_style(),
        render_children_two_level(Children, ChildBounds, Container, Child)
    ];
render_two_level_impl(#button{id = Id} = Button, Bounds, _Container, Child) ->
    render_button(Button, Bounds, Id =:= Child);
render_two_level_impl(#input{id = Id} = Input, Bounds, _Container, Child) ->
    render_input(Input, Bounds, Id =:= Child);
render_two_level_impl(#table{id = Id} = Table, Bounds, _Container, Child) ->
    render_table(Table, Bounds, Id =:= Child);
render_two_level_impl(#tabs{id = Id} = Tabs, Bounds, Container, Child) ->
    IsContainerFocused = Id =:= Container,
    render_tabs_two_level(Tabs, Bounds, IsContainerFocused, Child);
render_two_level_impl(#modal{} = Modal, Bounds, _Container, Child) ->
    render_modal(Modal, Bounds, Child);
render_two_level_impl(Element, Bounds, _Container, _Child) ->
    render(Element, Bounds).

render_children_two_level(Children, Bounds, Container, Child) ->
    [render_two_level_impl(C, Bounds, Container, Child) || C <- Children].

%% Tabs with two-level focus
render_tabs_two_level(#tabs{tabs = TabList, active_tab = ActiveTab0,
                            style = Style, x = X, y = Y, width = W, height = H},
                      Bounds, IsContainerFocused, FocusedChild) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; _ -> W end,
    Height = case H of auto -> Bounds#bounds.height - Y; _ -> H end,
    %% Default active tab to first if undefined
    ActiveTab = case ActiveTab0 of
        undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
        _ -> ActiveTab0
    end,
    %% Draw border around the entire tabs widget
    BorderStyle = if
        IsContainerFocused -> maps:merge(Style, #{fg => yellow, bold => true});
        true -> Style
    end,
    Border = render_box_border(ActualX, ActualY, Width, Height, BorderStyle, undefined, single),
    %% Tab headers with focus indicator (inside the top border)
    TabHeaders = render_tab_headers_two_level(TabList, ActiveTab, FocusedChild,
                                               ActualX + 1, ActualY, Style, IsContainerFocused),
    %% Active tab content (inside the border, below tab bar which is on row 1)
    ContentBounds = #bounds{x = ActualX + 1, y = ActualY + 2,
                            width = Width - 2, height = max(1, Height - 3)},
    ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end,
    ContentOutput = [render_two_level_impl(C, ContentBounds, undefined, undefined) || C <- ActiveContent],
    [Border, TabHeaders, ContentOutput].

render_tab_headers_two_level(Tabs, ActiveTab, FocusedChild, X, Y, Style, IsContainerFocused) ->
    {Headers, _} = lists:foldl(
        fun(#tab{id = Id, label = Label}, {Acc, CurX}) ->
            IsActive = Id =:= ActiveTab,
            IsFocused = Id =:= FocusedChild andalso IsContainerFocused,
            TabStyle = if
                IsFocused ->
                    %% Focused tab (arrow navigated to it)
                    maps:merge(Style, #{bg => white, fg => black, bold => true});
                IsActive ->
                    %% Active but not focused - darker background
                    maps:merge(Style, #{bg => cyan, fg => black});
                true ->
                    %% Inactive tabs - dimmed
                    maps:merge(Style, #{dim => true})
            end,
            LabelBin = iolist_to_binary([<<" ">>, Label, <<" ">>]),
            LabelLen = byte_size(LabelBin),
            Header = [
                move_to(Y + 1, CurX + 1),
                style_to_ansi(TabStyle),
                LabelBin,
                reset_style()
            ],
            {[Acc, Header], CurX + LabelLen + 1}
        end, {[], X}, Tabs),
    Headers.

%%====================================================================
%% Internal - Styled Rendering (with base style modifier for dimming)
%%====================================================================

render_focused_styled(#panel{children = Children}, Bounds, FocusedId, BaseStyle) ->
    render_children_styled(Children, Bounds, FocusedId, BaseStyle);
render_focused_styled(#vbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, FocusedId, BaseStyle) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    {Output, _} = lists:foldl(
        fun(Child, {Acc, CurrentY}) ->
            ChildBounds = StartBounds#bounds{y = CurrentY},
            ChildHeight = element_height(Child, ChildBounds),
            ChildOutput = render_focused_styled(Child, ChildBounds, FocusedId, BaseStyle),
            {[Acc, ChildOutput], CurrentY + ChildHeight + Spacing}
        end, {[], StartBounds#bounds.y}, Children),
    Output;
render_focused_styled(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, FocusedId, BaseStyle) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    TotalSpacing = max(0, (length(Children) - 1) * Spacing),
    FixedWidth = lists:sum([case element_fixed_width(C) of auto -> 0; W -> W end || C <- Children]),
    RemainingWidth = max(0, StartBounds#bounds.width - FixedWidth - TotalSpacing),
    {Output, _} = lists:foldl(
        fun(Child, {Acc, CurrentX}) ->
            ChildWidth = case element_fixed_width(Child) of
                auto -> RemainingWidth;
                W -> W
            end,
            ChildBounds = StartBounds#bounds{x = CurrentX, width = ChildWidth},
            ChildOutput = render_focused_styled(Child, ChildBounds, FocusedId, BaseStyle),
            {[Acc, ChildOutput], CurrentX + ChildWidth + Spacing}
        end, {[], StartBounds#bounds.x}, Children),
    Output;
render_focused_styled(#box{border = Border, title = Title, children = Children,
                    style = Style, x = X, y = Y, width = W, height = H}, Bounds, FocusedId, BaseStyle) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = resolve_size(W, Bounds#bounds.width - X),
    Height = resolve_size(H, Bounds#bounds.height - Y),
    {TL, TR, BL, BR, HZ, VT} = border_chars(Border),
    ChildBounds = #bounds{x = ActualX + 1, y = ActualY + 1,
                          width = max(1, Width - 2), height = max(1, Height - 2)},
    MergedStyle = maps:merge(Style, BaseStyle),
    [
        style_to_ansi(MergedStyle),
        move_to(ActualY + 1, ActualX + 1),
        TL, render_title_line(Title, HZ, Width - 2), TR,
        [[move_to(ActualY + 1 + Row, ActualX + 1),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        move_to(ActualY + Height, ActualX + 1),
        BL, repeat_bin(HZ, Width - 2), BR,
        reset_style(),
        render_children_styled(Children, ChildBounds, FocusedId, BaseStyle)
    ];
render_focused_styled(#text{content = Content, style = Style, x = X, y = Y}, Bounds, _FocusedId, BaseStyle) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    MergedStyle = maps:merge(Style, BaseStyle),
    [
        move_to(ActualY + 1, ActualX + 1),
        style_to_ansi(MergedStyle),
        truncate_content(Content, Bounds#bounds.width - X),
        reset_style()
    ];
render_focused_styled(#button{id = Id} = Button, Bounds, FocusedId, BaseStyle) ->
    render_button_styled(Button, Bounds, Id =:= FocusedId, BaseStyle);
render_focused_styled(#input{id = Id} = Input, Bounds, FocusedId, BaseStyle) ->
    render_input_styled(Input, Bounds, Id =:= FocusedId, BaseStyle);
render_focused_styled(#tabs{} = Tabs, Bounds, FocusedId, BaseStyle) ->
    render_tabs_styled(Tabs, Bounds, FocusedId, BaseStyle);
render_focused_styled(#table{} = Table, Bounds, _FocusedId, BaseStyle) ->
    render_table_styled(Table, Bounds, BaseStyle);
render_focused_styled(_Element, _Bounds, _FocusedId, _BaseStyle) ->
    [].

render_children_styled(Children, Bounds, FocusedId, BaseStyle) ->
    [render_focused_styled(Child, Bounds, FocusedId, BaseStyle) || Child <- Children].

render_button_styled(#button{label = Label, style = Style, x = X, y = Y, width = W}, Bounds, Focused, BaseStyle) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    LabelBin = iolist_to_binary([Label]),
    LabelLen = string:length(unicode:characters_to_list(LabelBin)),
    Width = case W of
        auto -> LabelLen + 4;
        _ -> W
    end,
    {Left, Right} = case Focused of
        true -> {<<"▶ ["/utf8>>, <<"] ◀"/utf8>>};
        false -> {<<"  [">>, <<"]  ">>}
    end,
    FocusStyle = case Focused of
        true -> maps:merge(Style, #{bold => true});
        false -> Style
    end,
    MergedStyle = maps:merge(FocusStyle, BaseStyle),
    Padding = max(0, Width - LabelLen - 4),
    LeftPad = Padding div 2,
    RightPad = Padding - LeftPad,
    [
        move_to(ActualY + 1, ActualX + 1),
        style_to_ansi(MergedStyle),
        Left, lists:duplicate(LeftPad, $\s), LabelBin, lists:duplicate(RightPad, $\s), Right,
        reset_style()
    ].

render_input_styled(#input{value = Value, placeholder = Placeholder, cursor_pos = CursorPos,
                    style = Style, x = X, y = Y, width = W}, Bounds, Focused, BaseStyle) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of
        auto -> 20;
        _ -> W
    end,
    ValueBin = iolist_to_binary([Value]),
    DisplayText = case byte_size(ValueBin) of
        0 -> iolist_to_binary([Placeholder]);
        _ -> ValueBin
    end,
    FieldWidth = Width - 2,
    DisplayLen = string:length(unicode:characters_to_list(DisplayText)),
    PaddedText = case DisplayLen >= FieldWidth of
        true -> truncate_content(DisplayText, FieldWidth);
        false -> [DisplayText, lists:duplicate(FieldWidth - DisplayLen, $\s)]
    end,
    TextStyle = case byte_size(ValueBin) of
        0 -> maps:merge(Style, #{dim => true});
        _ -> Style
    end,
    FocusStyle = case Focused of
        true -> maps:merge(TextStyle, #{underline => true});
        false -> TextStyle
    end,
    MergedStyle = maps:merge(FocusStyle, BaseStyle),
    CursorOutput = case Focused of
        true ->
            CursorCol = ActualX + 2 + min(CursorPos, FieldWidth - 1),
            [move_to(ActualY + 1, CursorCol)];
        false -> []
    end,
    [
        move_to(ActualY + 1, ActualX + 1),
        style_to_ansi(MergedStyle),
        <<"[">>, PaddedText, <<"]">>,
        reset_style(),
        CursorOutput
    ].

%% Render tabs with base style (for dimmed background)
render_tabs_styled(#tabs{tabs = TabList, active_tab = ActiveTab0,
                         style = Style, x = X, y = Y, width = W, height = H},
                   Bounds, _FocusedId, BaseStyle) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; _ -> W end,
    Height = case H of auto -> Bounds#bounds.height - Y; _ -> H end,
    ActiveTab = case ActiveTab0 of
        undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
        _ -> ActiveTab0
    end,
    MergedStyle = maps:merge(Style, BaseStyle),
    %% Draw border
    Border = render_box_border(ActualX, ActualY, Width, Height, MergedStyle, undefined, single),
    %% Tab headers
    TabHeaders = render_tab_headers_styled(TabList, ActiveTab, ActualX + 1, ActualY, MergedStyle),
    %% Content
    ContentBounds = #bounds{x = ActualX + 1, y = ActualY + 2,
                            width = Width - 2, height = max(1, Height - 3)},
    ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end,
    ContentOutput = render_children_styled(ActiveContent, ContentBounds, undefined, BaseStyle),
    [Border, TabHeaders, ContentOutput].

render_tab_headers_styled(Tabs, ActiveTab, X, Y, Style) ->
    {Headers, _} = lists:foldl(
        fun(#tab{id = Id, label = Label}, {Acc, CurX}) ->
            LabelBin = iolist_to_binary([Label]),
            LabelLen = byte_size(LabelBin),
            TabStyle = if
                Id =:= ActiveTab -> maps:merge(Style, #{bg => cyan, fg => black});
                true -> Style
            end,
            Header = [
                move_to(Y + 1, CurX + 1),
                style_to_ansi(TabStyle),
                <<" ">>, LabelBin, <<" ">>,
                reset_style()
            ],
            {[Acc, Header], CurX + LabelLen + 3}
        end, {[], X}, Tabs),
    Headers.

%% Render table with base style (for dimmed background)
render_table_styled(#table{columns = Columns, rows = Rows, selected_row = SelectedRow,
                           scroll_offset = ScrollOffset, border = Border, show_header = ShowHeader,
                           style = Style, x = X, y = Y, width = W, height = H,
                           visible = Visible}, Bounds, BaseStyle) ->
    case Visible of
        false -> [];
        true ->
            ActualX = Bounds#bounds.x + X,
            ActualY = Bounds#bounds.y + Y,
            Width = case W of auto -> Bounds#bounds.width - X; _ -> W end,
            Height = case H of auto -> min(length(Rows) + 3, Bounds#bounds.height - Y); _ -> H end,
            MergedStyle = maps:merge(Style, BaseStyle),
            BorderOffset = case Border of none -> 0; _ -> 1 end,
            ColWidths = calculate_column_widths(Columns, Rows, Width - 2 * BorderOffset),
            %% Header
            HeaderRow = case ShowHeader of
                true ->
                    HeaderText = render_table_row_text(
                        [C#table_col.header || C <- Columns], ColWidths, Columns),
                    HeaderY = ActualY + BorderOffset + 1,
                    SepY = ActualY + BorderOffset + 2,
                    [
                        move_to(HeaderY, ActualX + BorderOffset + 1),
                        style_to_ansi(maps:merge(MergedStyle, #{bold => true})),
                        HeaderText,
                        reset_style(),
                        move_to(SepY, ActualX + BorderOffset + 1),
                        style_to_ansi(MergedStyle),
                        repeat_bin(<<"─"/utf8>>, Width - 2 * BorderOffset),
                        reset_style()
                    ];
                false -> []
            end,
            HeaderOffset2 = case ShowHeader of true -> 2; false -> 0 end,
            VisibleHeight = Height - 2 * BorderOffset - HeaderOffset2,
            VisibleRows = lists:sublist(
                lists:nthtail(min(ScrollOffset, max(0, length(Rows) - 1)), Rows),
                max(0, VisibleHeight)),
            DataRows = lists:map(
                fun({RowIdx, RowData}) ->
                    AbsRowIdx = ScrollOffset + RowIdx,
                    IsSelected = AbsRowIdx =:= SelectedRow,
                    RowStyle = if
                        IsSelected -> maps:merge(MergedStyle, #{bg => cyan, fg => black});
                        true -> MergedStyle
                    end,
                    RowText = render_table_row_text(RowData, ColWidths, Columns),
                    RowY = ActualY + BorderOffset + HeaderOffset2 + RowIdx,
                    [
                        move_to(RowY, ActualX + BorderOffset + 1),
                        style_to_ansi(RowStyle),
                        RowText,
                        reset_style()
                    ]
                end,
                lists:zip(lists:seq(1, length(VisibleRows)), VisibleRows)),
            BorderOutput = case Border of
                none -> [];
                _ ->
                    {TL, TR, BL, BR, HZ, VT} = border_chars(Border),
                    [
                        style_to_ansi(MergedStyle),
                        move_to(ActualY + 1, ActualX + 1),
                        TL, repeat_bin(HZ, Width - 2), TR,
                        [[move_to(ActualY + 1 + Row, ActualX + 1),
                          VT, lists:duplicate(Width - 2, $\s), VT]
                         || Row <- lists:seq(1, Height - 2)],
                        move_to(ActualY + Height, ActualX + 1),
                        BL, repeat_bin(HZ, Width - 2), BR,
                        reset_style()
                    ]
            end,
            [BorderOutput, HeaderRow, DataRows]
    end.

%%====================================================================
%% Internal - Button Rendering
%%====================================================================

render_button(#button{label = Label, style = Style, x = X, y = Y, width = W}, Bounds, Focused) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    LabelBin = iolist_to_binary([Label]),
    LabelLen = string:length(unicode:characters_to_list(LabelBin)),
    Width = case W of
        auto -> LabelLen + 4;  %% [ Label ]
        _ -> W
    end,
    %% Focus indicator: use reverse video or brackets
    {Left, Right} = case Focused of
        true -> {<<"▶ ["/utf8>>, <<"] ◀"/utf8>>};
        false -> {<<"  [">>, <<"]  ">>}
    end,
    FocusStyle = case Focused of
        true -> maps:merge(Style, #{bold => true});
        false -> Style
    end,
    Padding = max(0, Width - LabelLen - 4),
    LeftPad = Padding div 2,
    RightPad = Padding - LeftPad,
    [
        move_to(ActualY + 1, ActualX + 1),
        style_to_ansi(FocusStyle),
        Left, lists:duplicate(LeftPad, $\s), LabelBin, lists:duplicate(RightPad, $\s), Right,
        reset_style()
    ].

%%====================================================================
%% Internal - Input Rendering
%%====================================================================

render_input(#input{value = Value, placeholder = Placeholder, cursor_pos = CursorPos,
                    style = Style, x = X, y = Y, width = W}, Bounds, Focused) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of
        auto -> 20;  %% Default input width
        _ -> W
    end,
    ValueBin = iolist_to_binary([Value]),
    DisplayText = case byte_size(ValueBin) of
        0 -> iolist_to_binary([Placeholder]);
        _ -> ValueBin
    end,
    %% Truncate or pad to width
    FieldWidth = Width - 2,  %% Account for [ ]
    DisplayLen = string:length(unicode:characters_to_list(DisplayText)),
    PaddedText = case DisplayLen >= FieldWidth of
        true -> truncate_content(DisplayText, FieldWidth);
        false -> [DisplayText, lists:duplicate(FieldWidth - DisplayLen, $\s)]
    end,
    %% Style: dim for placeholder, normal for value
    TextStyle = case byte_size(ValueBin) of
        0 -> maps:merge(Style, #{dim => true});
        _ -> Style
    end,
    FocusStyle = case Focused of
        true -> maps:merge(TextStyle, #{underline => true});
        false -> TextStyle
    end,
    %% Cursor positioning (show cursor at position if focused)
    CursorOutput = case Focused of
        true ->
            CursorCol = ActualX + 2 + min(CursorPos, FieldWidth - 1),
            [move_to(ActualY + 1, CursorCol)];
        false -> []
    end,
    [
        move_to(ActualY + 1, ActualX + 1),
        style_to_ansi(FocusStyle),
        <<"[">>, PaddedText, <<"]">>,
        reset_style(),
        CursorOutput
    ].

%%====================================================================
%% Internal - Modal Rendering (centered overlay)
%%====================================================================

render_modal(#modal{title = Title, children = Children, border = Border,
                    style = Style, width = W, height = H, visible = Visible},
             Bounds, FocusedId) ->
    case Visible of
        false -> [];
        true ->
            %% Calculate modal size
            Width = case W of
                auto -> min(60, Bounds#bounds.width - 4);
                _ -> min(W, Bounds#bounds.width - 2)
            end,
            Height = case H of
                auto -> min(10, Bounds#bounds.height - 4);
                _ -> min(H, Bounds#bounds.height - 2)
            end,
            %% Center the modal
            ModalX = (Bounds#bounds.width - Width) div 2,
            ModalY = (Bounds#bounds.height - Height) div 2,
            {TL, TR, BL, BR, HZ, VT} = border_chars(Border),
            ChildBounds = #bounds{x = ModalX + 1, y = ModalY + 1,
                                  width = max(1, Width - 2), height = max(1, Height - 2)},
            %% Draw modal box (background dimming is handled by caller)
            ModalBox = [
                reset_style(),  %% Reset any dim styling from background
                style_to_ansi(Style),
                move_to(ModalY + 1, ModalX + 1),
                TL, render_title_line(Title, HZ, Width - 2), TR,
                [[move_to(ModalY + 1 + Row, ModalX + 1),
                  VT, lists:duplicate(Width - 2, $\s), VT]
                 || Row <- lists:seq(1, Height - 2)],
                move_to(ModalY + Height, ModalX + 1),
                BL, repeat_bin(HZ, Width - 2), BR,
                reset_style()
            ],
            %% Render children inside modal
            ChildOutput = render_children_focused(Children, ChildBounds, FocusedId),
            [ModalBox, ChildOutput]
    end.

%%====================================================================
%% Internal - Table Rendering
%%====================================================================

render_table(#table{columns = Columns, rows = Rows, selected_row = SelectedRow,
                    scroll_offset = ScrollOffset, border = Border, show_header = ShowHeader,
                    zebra = Zebra, style = Style, x = X, y = Y, width = W, height = H,
                    visible = Visible}, Bounds, Focused) ->
    case Visible of
        false -> [];
        true ->
            ActualX = Bounds#bounds.x + X,
            ActualY = Bounds#bounds.y + Y,
            %% Calculate dimensions
            Width = case W of
                auto -> Bounds#bounds.width - X;
                _ -> W
            end,
            Height = case H of
                auto -> min(length(Rows) + 3, Bounds#bounds.height - Y);
                _ -> H
            end,
            %% Border offsets (0 if no border, 1 if border)
            BorderOffset = case Border of none -> 0; _ -> 1 end,
            %% Calculate column widths
            ColWidths = calculate_column_widths(Columns, Rows, Width - 2 * BorderOffset),
            %% Header row
            HeaderRow = case ShowHeader of
                true ->
                    HeaderText = render_table_row_text(
                        [C#table_col.header || C <- Columns], ColWidths, Columns),
                    HeaderY = ActualY + BorderOffset + 1,
                    SepY = ActualY + BorderOffset + 2,
                    [
                        move_to(HeaderY, ActualX + BorderOffset + 1),
                        style_to_ansi(maps:merge(Style, #{bold => true})),
                        HeaderText,
                        reset_style(),
                        %% Header separator
                        move_to(SepY, ActualX + BorderOffset + 1),
                        style_to_ansi(Style),
                        repeat_bin(<<"─"/utf8>>, Width - 2 * BorderOffset),
                        reset_style()
                    ];
                false -> []
            end,
            HeaderOffset2 = case ShowHeader of true -> 2; false -> 0 end,
            %% Visible rows
            VisibleHeight = Height - 2 * BorderOffset - HeaderOffset2,
            VisibleRows = lists:sublist(
                lists:nthtail(min(ScrollOffset, max(0, length(Rows) - 1)), Rows),
                max(0, VisibleHeight)),
            %% Render data rows
            DataRows = lists:map(
                fun({RowIdx, RowData}) ->
                    AbsRowIdx = ScrollOffset + RowIdx,
                    IsSelected = AbsRowIdx =:= SelectedRow,
                    RowStyle = if
                        IsSelected andalso Focused ->
                            maps:merge(Style, #{bg => white, fg => black, bold => true});
                        IsSelected ->
                            maps:merge(Style, #{bg => cyan, fg => black});
                        Zebra andalso (AbsRowIdx rem 2 =:= 1) ->
                            maps:merge(Style, #{dim => true});
                        true -> Style
                    end,
                    RowText = render_table_row_text(RowData, ColWidths, Columns),
                    RowY = ActualY + BorderOffset + HeaderOffset2 + RowIdx,
                    [
                        move_to(RowY, ActualX + BorderOffset + 1),
                        style_to_ansi(RowStyle),
                        RowText,
                        reset_style()
                    ]
                end,
                lists:zip(lists:seq(1, length(VisibleRows)), VisibleRows)),
            %% Draw border (only if not none)
            BorderOutput = case Border of
                none -> [];
                _ ->
                    {TL, TR, BL, BR, HZ, VT} = border_chars(Border),
                    [
                        style_to_ansi(Style),
                        move_to(ActualY + 1, ActualX + 1),
                        TL, repeat_bin(HZ, Width - 2), TR,
                        [[move_to(ActualY + 1 + Row, ActualX + 1),
                          VT, lists:duplicate(Width - 2, $\s), VT]
                         || Row <- lists:seq(1, Height - 2)],
                        move_to(ActualY + Height, ActualX + 1),
                        BL, repeat_bin(HZ, Width - 2), BR,
                        reset_style()
                    ]
            end,
            [BorderOutput, HeaderRow, DataRows]
    end.

calculate_column_widths(Columns, Rows, AvailableWidth) ->
    NumCols = length(Columns),
    %% Calculate content widths
    ContentWidths = lists:map(
        fun({Idx, Col}) ->
            HeaderLen = string:length(to_string(Col#table_col.header)),
            MaxDataLen = lists:foldl(
                fun(Row, Max) ->
                    CellData = safe_nth(Idx, Row, <<>>),
                    max(Max, string:length(to_string(CellData)))
                end, 0, Rows),
            case Col#table_col.width of
                auto -> max(HeaderLen, MaxDataLen);
                W -> W
            end
        end,
        lists:zip(lists:seq(1, NumCols), Columns)),
    %% Distribute remaining space or truncate
    TotalWidth = lists:sum(ContentWidths) + NumCols - 1,  %% +separators
    if
        TotalWidth =< AvailableWidth -> ContentWidths;
        true ->
            %% Proportionally shrink columns
            Scale = AvailableWidth / max(1, TotalWidth),
            [max(3, round(W * Scale)) || W <- ContentWidths]
    end.

render_table_row_text(RowData, ColWidths, Columns) ->
    Cells = lists:map(
        fun({Idx, Width}) ->
            Data = safe_nth(Idx, RowData, <<>>),
            Col = safe_nth(Idx, Columns, #table_col{}),
            Align = Col#table_col.align,
            format_cell(to_string(Data), Width, Align)
        end,
        lists:zip(lists:seq(1, length(ColWidths)), ColWidths)),
    lists:join(<<" ">>, Cells).

format_cell(Text, Width, Align) ->
    Len = string:length(Text),
    if
        Len >= Width -> string:slice(Text, 0, Width);
        true ->
            Padding = Width - Len,
            case Align of
                left -> [Text, lists:duplicate(Padding, $\s)];
                right -> [lists:duplicate(Padding, $\s), Text];
                center ->
                    Left = Padding div 2,
                    Right = Padding - Left,
                    [lists:duplicate(Left, $\s), Text, lists:duplicate(Right, $\s)]
            end
    end.

to_string(Bin) when is_binary(Bin) -> unicode:characters_to_list(Bin);
to_string(List) when is_list(List) -> List;
to_string(Atom) when is_atom(Atom) -> atom_to_list(Atom);
to_string(Int) when is_integer(Int) -> integer_to_list(Int);
to_string(Float) when is_float(Float) -> float_to_list(Float, [{decimals, 2}]);
to_string(Other) -> io_lib:format("~p", [Other]).

safe_nth(N, List, _Default) when N > 0, N =< length(List) ->
    lists:nth(N, List);
safe_nth(_, _, Default) ->
    Default.

%%====================================================================
%% Internal - Tabs Rendering
%%====================================================================

render_tabs(#tabs{tabs = TabList, active_tab = ActiveTab0, style = Style,
                  x = X, y = Y, width = W, height = H, visible = Visible},
            Bounds, Focused, FocusedId) ->
    case Visible of
        false -> [];
        true ->
            %% Default to first tab if undefined
            ActiveTab = case ActiveTab0 of
                undefined -> case TabList of [#tab{id = FirstId} | _] -> FirstId; [] -> undefined end;
                _ -> ActiveTab0
            end,
            ActualX = Bounds#bounds.x + X,
            ActualY = Bounds#bounds.y + Y,
            Width = case W of
                auto -> Bounds#bounds.width - X;
                _ -> W
            end,
            Height = case H of
                auto -> Bounds#bounds.height - Y;
                _ -> H
            end,
            %% Render tab bar
            TabBar = render_tab_bar(TabList, ActiveTab, ActualX, ActualY, Width, Style, Focused),
            %% Find active tab content
            ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
                #tab{content = Content} -> Content;
                false -> []
            end,
            %% Render content area (below tab bar)
            ContentBounds = #bounds{
                x = ActualX,
                y = ActualY + 1,
                width = Width,
                height = max(1, Height - 1)
            },
            ContentOutput = render_children_focused(ActiveContent, ContentBounds, FocusedId),
            [TabBar, ContentOutput]
    end.

render_tab_bar(Tabs, ActiveTab, X, Y, Width, Style, Focused) ->
    %% Render each tab label
    {TabLabels, _} = lists:foldl(
        fun(#tab{id = Id, label = Label}, {Acc, CurrentX}) ->
            LabelBin = iolist_to_binary([Label]),
            LabelLen = string:length(unicode:characters_to_list(LabelBin)),
            IsActive = Id =:= ActiveTab,
            TabStyle = if
                IsActive andalso Focused ->
                    maps:merge(Style, #{bg => white, fg => black, bold => true});
                IsActive ->
                    maps:merge(Style, #{bg => cyan, fg => black});
                true ->
                    maps:merge(Style, #{dim => true})
            end,
            TabOutput = [
                move_to(Y + 1, CurrentX + 1),
                style_to_ansi(TabStyle),
                <<" ">>, LabelBin, <<" ">>,
                reset_style()
            ],
            Separator = if
                CurrentX + LabelLen + 2 < X + Width - 1 ->
                    [style_to_ansi(Style), <<"│"/utf8>>, reset_style()];
                true -> []
            end,
            {[Acc, TabOutput, Separator], CurrentX + LabelLen + 3}
        end,
        {[], X}, Tabs),
    %% Draw underline for tab bar
    Underline = [
        move_to(Y + 2, X + 1),
        style_to_ansi(Style),
        repeat_bin(<<"─"/utf8>>, Width),
        reset_style()
    ],
    [TabLabels, Underline].

%%====================================================================
%% Internal - Box Rendering
%%====================================================================

render_box(#box{border = none, children = Children, x = X, y = Y}, Bounds) ->
    ChildBounds = Bounds#bounds{
        x = Bounds#bounds.x + X,
        y = Bounds#bounds.y + Y
    },
    render_children(Children, ChildBounds);

render_box(#box{border = Border, title = Title, children = Children,
                style = Style, x = X, y = Y, width = W, height = H}, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = resolve_size(W, Bounds#bounds.width - X),
    Height = resolve_size(H, Bounds#bounds.height - Y),

    %% Child bounds (inside the border)
    ChildBounds = #bounds{
        x = ActualX + 1,
        y = ActualY + 1,
        width = max(1, Width - 2),
        height = max(1, Height - 2)
    },

    [
        render_box_border(ActualX, ActualY, Width, Height, Style, Title, Border),
        render_children(Children, ChildBounds)
    ].

%% Render just the border of a box (used by box and tabs)
render_box_border(ActualX, ActualY, Width, Height, Style, Title, Border) ->
    {TL, TR, BL, BR, HZ, VT} = border_chars(Border),
    [
        style_to_ansi(Style),
        %% Top border
        move_to(ActualY + 1, ActualX + 1),
        TL, render_title_line(Title, HZ, Width - 2), TR,
        %% Side borders
        [[move_to(ActualY + 1 + Row, ActualX + 1),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        %% Bottom border
        move_to(ActualY + Height, ActualX + 1),
        BL, repeat_bin(HZ, Width - 2), BR,
        reset_style()
    ].

render_title_line(undefined, HZ, Width) ->
    repeat_bin(HZ, Width);
render_title_line(Title, HZ, Width) ->
    TitleBin = iolist_to_binary([Title]),
    %% Unicode title length (not byte length)
    TitleLen = string:length(unicode:characters_to_list(TitleBin)),
    case TitleLen + 2 > Width of
        true -> repeat_bin(HZ, Width);
        false ->
            Padding = Width - TitleLen - 2,
            LeftPad = Padding div 2,
            RightPad = Padding - LeftPad,
            [repeat_bin(HZ, LeftPad), $\s, TitleBin, $\s, repeat_bin(HZ, RightPad)]
    end.

%% Repeat a binary N times
repeat_bin(_Bin, N) when N =< 0 -> [];
repeat_bin(Bin, N) -> [Bin || _ <- lists:seq(1, N)].

border_chars(single) -> {<<"┌"/utf8>>, <<"┐"/utf8>>, <<"└"/utf8>>, <<"┘"/utf8>>, <<"─"/utf8>>, <<"│"/utf8>>};
border_chars(double) -> {<<"╔"/utf8>>, <<"╗"/utf8>>, <<"╚"/utf8>>, <<"╝"/utf8>>, <<"═"/utf8>>, <<"║"/utf8>>};
border_chars(rounded) -> {<<"╭"/utf8>>, <<"╮"/utf8>>, <<"╰"/utf8>>, <<"╯"/utf8>>, <<"─"/utf8>>, <<"│"/utf8>>};
border_chars(_) -> {<<"┌"/utf8>>, <<"┐"/utf8>>, <<"└"/utf8>>, <<"┘"/utf8>>, <<"─"/utf8>>, <<"│"/utf8>>}.

resolve_size(auto, Available) -> Available;
resolve_size(Size, _Available) when is_integer(Size) -> Size.

%%====================================================================
%% Internal - VBox/HBox Rendering
%%====================================================================

render_vbox(#vbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds) ->
    StartBounds = Bounds#bounds{
        x = Bounds#bounds.x + X,
        y = Bounds#bounds.y + Y
    },
    {Output, _FinalY} = lists:foldl(
        fun(Child, {Acc, CurrentY}) ->
            ChildBounds = StartBounds#bounds{y = CurrentY},
            ChildHeight = element_height(Child, ChildBounds),
            ChildOutput = render(Child, ChildBounds),
            {[Acc, ChildOutput], CurrentY + ChildHeight + Spacing}
        end,
        {[], StartBounds#bounds.y},
        Children
    ),
    Output.

render_hbox(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds) ->
    StartBounds = Bounds#bounds{
        x = Bounds#bounds.x + X,
        y = Bounds#bounds.y + Y
    },
    TotalSpacing = max(0, (length(Children) - 1) * Spacing),
    FixedWidth = lists:sum([case element_fixed_width(C) of auto -> 0; W -> W end || C <- Children]),
    RemainingWidth = max(0, StartBounds#bounds.width - FixedWidth - TotalSpacing),
    {Output, _FinalX} = lists:foldl(
        fun(Child, {Acc, CurrentX}) ->
            ChildWidth = case element_fixed_width(Child) of
                auto -> RemainingWidth;
                W -> W
            end,
            ChildBounds = StartBounds#bounds{x = CurrentX, width = ChildWidth},
            ChildOutput = render(Child, ChildBounds),
            {[Acc, ChildOutput], CurrentX + ChildWidth + Spacing}
        end,
        {[], StartBounds#bounds.x},
        Children
    ),
    Output.

render_children(Children, Bounds) ->
    [render(Child, Bounds) || Child <- Children].

%% Simple size estimation (will be improved in iso_layout)
element_height(#text{}, _Bounds) -> 1;
element_height(#button{}, _Bounds) -> 1;
element_height(#input{}, _Bounds) -> 1;
element_height(#box{height = auto}, Bounds) -> Bounds#bounds.height;
element_height(#box{height = H}, _Bounds) -> H;
element_height(#vbox{children = Children, spacing = S}, Bounds) ->
    lists:sum([element_height(C, Bounds) || C <- Children]) +
    max(0, (length(Children) - 1) * S);
element_height(_, _) -> 1.

element_width(#text{content = C}, _Bounds) -> byte_size(iolist_to_binary([C]));
element_width(#button{label = L, width = auto}, _Bounds) ->
    byte_size(iolist_to_binary([L])) + 4;  %% [ Label ]
element_width(#button{width = W}, _Bounds) -> W;
element_width(#input{width = auto}, _Bounds) -> 22;  %% Default width + brackets
element_width(#input{width = W}, _Bounds) -> W;
element_width(#box{width = auto}, Bounds) -> Bounds#bounds.width;
element_width(#box{width = W}, _Bounds) -> W;
element_width(#hbox{children = Children, spacing = S}, Bounds) ->
    lists:sum([element_width(C, Bounds) || C <- Children]) +
    max(0, (length(Children) - 1) * S);
element_width(#tabs{width = auto}, Bounds) -> Bounds#bounds.width;
element_width(#tabs{width = W}, _Bounds) -> W;
element_width(#table{width = auto}, Bounds) -> Bounds#bounds.width;
element_width(#table{width = W}, _Bounds) -> W;
element_width(_, _) -> 1.

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

%%====================================================================
%% Internal - ANSI Helpers
%%====================================================================

move_to(Row, Col) ->
    iolist_to_binary(io_lib:format("\e[~B;~BH", [Row, Col])).

-spec style_to_ansi(map()) -> iolist().
style_to_ansi(Style) when map_size(Style) == 0 ->
    [];
style_to_ansi(Style) ->
    Codes = lists:filtermap(
        fun({Key, Value}) -> style_code(Key, Value) end,
        maps:to_list(Style)
    ),
    case Codes of
        [] -> [];
        _ -> [<<"\e[">>, lists:join($;, Codes), <<"m">>]
    end.

style_code(fg, Color) -> {true, fg_code(Color)};
style_code(bg, Color) -> {true, bg_code(Color)};
style_code(bold, true) -> {true, <<"1">>};
style_code(dim, true) -> {true, <<"2">>};
style_code(italic, true) -> {true, <<"3">>};
style_code(underline, true) -> {true, <<"4">>};
style_code(_, _) -> false.

fg_code(black) -> <<"30">>; fg_code(red) -> <<"31">>; fg_code(green) -> <<"32">>;
fg_code(yellow) -> <<"33">>; fg_code(blue) -> <<"34">>; fg_code(magenta) -> <<"35">>;
fg_code(cyan) -> <<"36">>; fg_code(white) -> <<"37">>;
fg_code(bright_black) -> <<"90">>; fg_code(bright_red) -> <<"91">>;
fg_code(bright_green) -> <<"92">>; fg_code(bright_yellow) -> <<"93">>;
fg_code(bright_blue) -> <<"94">>; fg_code(bright_magenta) -> <<"95">>;
fg_code(bright_cyan) -> <<"96">>; fg_code(bright_white) -> <<"97">>;
fg_code(_) -> <<"37">>.

bg_code(black) -> <<"40">>; bg_code(red) -> <<"41">>; bg_code(green) -> <<"42">>;
bg_code(yellow) -> <<"43">>; bg_code(blue) -> <<"44">>; bg_code(magenta) -> <<"45">>;
bg_code(cyan) -> <<"46">>; bg_code(white) -> <<"47">>;
bg_code(bright_black) -> <<"100">>; bg_code(bright_red) -> <<"101">>;
bg_code(bright_green) -> <<"102">>; bg_code(bright_yellow) -> <<"103">>;
bg_code(bright_blue) -> <<"104">>; bg_code(bright_magenta) -> <<"105">>;
bg_code(bright_cyan) -> <<"106">>; bg_code(bright_white) -> <<"107">>;
bg_code(_) -> <<"40">>.

-spec reset_style() -> binary().
reset_style() ->
    <<"\e[0m">>.


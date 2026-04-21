%%%-------------------------------------------------------------------
%%% @doc Isotope Scroll Container Element
%%%
%%% A scrollable viewport that can contain child elements.
%%% Supports vertical scrolling with optional scrollbar indicator.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_el_scroll).

-behaviour(iso_element).

-include("iso_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% iso_element callbacks
%%====================================================================

-spec render(#scroll{}, #bounds{}, map()) -> iolist().
render(#scroll{visible = false}, _Bounds, _Opts) ->
    [];
render(#scroll{children = Children, offset = Offset, show_scrollbar = ShowBar}, Bounds, Opts) ->
    %% Calculate total content height
    TotalHeight = calculate_content_height(Children, Bounds),
    ViewHeight = max(1, Bounds#bounds.height),

    %% Adjust bounds for scrollbar if shown
    ContentWidth = if ShowBar andalso TotalHeight > ViewHeight ->
                          max(1, Bounds#bounds.width - 1);
                      true ->
                          Bounds#bounds.width
                   end,
    ClampedOffset = clamp_offset(Offset, TotalHeight, ViewHeight),

    %% Render visible portion of children
    ChildOutput = render_children_with_offset(
        Children, ContentWidth, TotalHeight, ClampedOffset, ViewHeight, Opts,
        Bounds#bounds.x, Bounds#bounds.y),

    %% Render scrollbar if needed
    ScrollbarOutput = if ShowBar andalso TotalHeight > ViewHeight ->
                             render_scrollbar(Bounds, ClampedOffset, TotalHeight, ViewHeight);
                         true ->
                             []
                      end,
    
    [ChildOutput, ScrollbarOutput].

-spec height(#scroll{}, #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
height(#scroll{height = auto}, Bounds) -> Bounds#bounds.height;
height(#scroll{height = fill}, _Bounds) -> {flex, 1};
height(#scroll{height = H}, _Bounds) -> H.

-spec width(#scroll{}, #bounds{}) -> pos_integer().
width(#scroll{width = auto}, Bounds) -> Bounds#bounds.width;
width(#scroll{width = W}, _Bounds) -> W.

-spec fixed_width(#scroll{}) -> auto | pos_integer().
fixed_width(#scroll{width = W}) -> W.

%%====================================================================
%% Internal functions
%%====================================================================

calculate_content_height(Children, Bounds) ->
    lists:foldl(fun(Child, Acc) ->
        Acc + iso_element:height(Child, Bounds)
    end, 0, Children).

render_children_with_offset(Children, Width, TotalHeight, Offset, ViewHeight, Opts, DestX, DestY) ->
    ContentHeight = max(ViewHeight, TotalHeight),
    OffscreenBounds = #bounds{x = 0, y = 0, width = Width, height = ContentHeight},
    OffscreenOutput = render_children(Children, OffscreenBounds, Opts),
    OffscreenScreen = iso_screen:from_ansi(OffscreenOutput, Width, ContentHeight),
    viewport_to_ansi(OffscreenScreen, Width, ViewHeight, Offset, DestX, DestY).

render_children(Children, Bounds, Opts) ->
    ChildHeights = iso_layout:calculate_vbox_heights(Children, Bounds, 0),
    {Output, _} = lists:foldl(
        fun({Child, Height}, {Acc, CurrentY}) ->
            ChildBounds = Bounds#bounds{y = CurrentY, height = Height},
            ChildOutput = iso_element:render(Child, ChildBounds, Opts),
            {[Acc, ChildOutput], CurrentY + Height}
        end,
        {[], Bounds#bounds.y},
        lists:zip(Children, ChildHeights)
    ),
    Output.

viewport_to_ansi(Screen, Width, ViewHeight, Offset, DestX, DestY) ->
    [render_viewport_row(Screen, Width, Offset + Row, DestX, DestY + Row)
     || Row <- lists:seq(0, ViewHeight - 1)].

render_viewport_row(Screen, Width, SourceRow, DestX, DestY) ->
    [
        iso_ansi:move_to(DestY + 1, DestX + 1),
        render_viewport_cells(Screen, Width, SourceRow, 0, #{}, []),
        iso_ansi:reset_style()
    ].

render_viewport_cells(_Screen, Width, _SourceRow, Col, _LastStyle, Acc) when Col >= Width ->
    lists:reverse(Acc);
render_viewport_cells(Screen, Width, SourceRow, Col, LastStyle, Acc) ->
    {Char, Style} = iso_screen:get_cell(Screen, Col, SourceRow),
    StyleChange = style_change(LastStyle, Style),
    CharBin = char_to_binary(Char),
    render_viewport_cells(
        Screen, Width, SourceRow, Col + 1, Style,
        [[StyleChange, CharBin] | Acc]).

style_change(OldStyle, NewStyle) when OldStyle =:= NewStyle ->
    [];
style_change(_OldStyle, NewStyle) ->
    [iso_ansi:reset_style(), iso_ansi:style_to_ansi(NewStyle)].

char_to_binary(Char) when is_integer(Char) ->
    unicode:characters_to_binary([Char]);
char_to_binary(Bin) when is_binary(Bin) ->
    Bin.

clamp_offset(Offset, TotalHeight, ViewHeight) ->
    min(max(0, Offset), max(0, TotalHeight - ViewHeight)).

render_scrollbar(Bounds, Offset, TotalHeight, ViewHeight) ->
    %% Calculate scrollbar position and size
    BarX = Bounds#bounds.x + Bounds#bounds.width - 1,
    BarY = Bounds#bounds.y,
    
    %% Scrollbar thumb size (minimum 1)
    ThumbSize = max(1, (ViewHeight * ViewHeight) div TotalHeight),
    
    %% Scrollbar thumb position
    MaxOffset = TotalHeight - ViewHeight,
    ThumbPos = if MaxOffset > 0 ->
                      (Offset * (ViewHeight - ThumbSize)) div MaxOffset;
                  true ->
                      0
               end,
    
    %% Render scrollbar track and thumb
    render_scrollbar_lines(BarX, BarY, ViewHeight, ThumbPos, ThumbSize, []).

render_scrollbar_lines(_X, _Y, 0, _ThumbPos, _ThumbSize, Acc) ->
    lists:reverse(Acc);
render_scrollbar_lines(X, Y, Remaining, ThumbPos, ThumbSize, Acc) ->
    LineIdx = length(Acc),
    Char = if LineIdx >= ThumbPos andalso LineIdx < ThumbPos + ThumbSize ->
                  <<"█">>;  %% Thumb
              true ->
                  <<"░">>   %% Track
           end,
    Line = [iso_ansi:move_to(Y + LineIdx + 1, X + 1),
            iso_ansi:style_to_ansi(#{fg => gray}),
            Char,
            iso_ansi:reset_style()],
    render_scrollbar_lines(X, Y, Remaining - 1, ThumbPos, ThumbSize, [Line | Acc]).

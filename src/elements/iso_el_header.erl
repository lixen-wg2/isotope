%%%-------------------------------------------------------------------
%%% @doc Header Element
%%%
%%% Displays a top header bar with title, subtitle, and info items.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_el_header).

-behaviour(iso_element).

-include("iso_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% iso_element callbacks
%%====================================================================

render(#header{visible = false}, _Bounds, _Opts) ->
    [];
render(#header{title = Title, subtitle = Subtitle, items = Items,
               bg_color = BgColor, fg_color = FgColor,
               x = X, y = Y, style = Style}, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = Bounds#bounds.width - X,
    
    BaseStyle = maps:get(base_style, Opts, #{}),
    HeaderStyle = maps:merge(maps:merge(BaseStyle, Style), #{bg => BgColor, fg => FgColor}),
    BoldStyle = maps:merge(HeaderStyle, #{bold => true}),
    
    %% Build left side: Title - Subtitle
    LeftPart = case Subtitle of
        <<>> -> Title;
        _ -> [Title, <<" - ">>, Subtitle]
    end,
    LeftBin = iolist_to_binary(LeftPart),
    
    %% Build right side: Label: Value | Label: Value
    RightParts = lists:map(
        fun({Label, Value}) ->
            [Label, <<": ">>, Value]
        end,
        Items
    ),
    RightBin = iolist_to_binary(lists:join(<<" | ">>, RightParts)),
    
    %% Calculate padding
    LeftLen = byte_size(LeftBin),
    RightLen = byte_size(RightBin),
    PadLen = max(0, Width - LeftLen - RightLen - 2),
    Padding = list_to_binary(lists:duplicate(PadLen, $ )),
    
    %% Fill entire line with background
    FullLine = list_to_binary(lists:duplicate(Width, $ )),
    
    [
        iso_ansi:move_to(ActualY + 1, ActualX + 1),
        iso_ansi:style_to_ansi(HeaderStyle),
        FullLine,
        iso_ansi:move_to(ActualY + 1, ActualX + 1),
        iso_ansi:style_to_ansi(BoldStyle),
        LeftBin,
        iso_ansi:style_to_ansi(HeaderStyle),
        Padding,
        RightBin,
        <<" ">>,
        iso_ansi:reset_style()
    ].

height(#header{}, _Bounds) -> 1.

width(#header{}, Bounds) -> Bounds#bounds.width.

fixed_width(#header{width = fill}) -> auto;
fixed_width(#header{width = W}) -> W.


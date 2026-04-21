%%%-------------------------------------------------------------------
%%% @doc Stat Row Element
%%%
%%% Displays a horizontal row of key-value pairs with separators.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_el_stat_row).

-behaviour(iso_element).

-include("iso_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% iso_element callbacks
%%====================================================================

render(#stat_row{visible = false}, _Bounds, _Opts) ->
    [];
render(#stat_row{items = [], x = X, y = Y}, Bounds, _Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    [iso_ansi:move_to(ActualY + 1, ActualX + 1)];
render(#stat_row{items = Items, separator = Sep, x = X, y = Y,
                 label_style = LabelStyle, value_style = ValueStyle,
                 style = Style}, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    
    BaseStyle = maps:get(base_style, Opts, #{}),
    MergedLabelStyle = maps:merge(maps:merge(BaseStyle, Style), LabelStyle),
    MergedValueStyle = maps:merge(maps:merge(BaseStyle, Style), ValueStyle),
    
    %% Build output for each item
    ItemOutputs = lists:map(
        fun({Label, Value}) ->
            [
                iso_ansi:style_to_ansi(MergedLabelStyle),
                Label,
                <<": ">>,
                iso_ansi:style_to_ansi(MergedValueStyle),
                Value,
                iso_ansi:reset_style()
            ]
        end,
        Items
    ),
    
    %% Join with separator
    SepOutput = [iso_ansi:style_to_ansi(#{dim => true}), Sep, iso_ansi:reset_style()],
    Joined = lists:join(SepOutput, ItemOutputs),
    
    [
        iso_ansi:move_to(ActualY + 1, ActualX + 1),
        Joined
    ].

height(#stat_row{}, _Bounds) -> 1.

width(#stat_row{items = Items, separator = Sep}, _Bounds) ->
    %% Calculate total width
    ItemWidths = lists:sum([byte_size(L) + 2 + byte_size(V) || {L, V} <- Items]),
    SepWidth = byte_size(Sep) * max(0, length(Items) - 1),
    ItemWidths + SepWidth.

fixed_width(#stat_row{width = W}) -> W.


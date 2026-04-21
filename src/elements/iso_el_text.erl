%%%-------------------------------------------------------------------
%%% @doc Isotope Text Element
%%%
%%% Renders a simple text string.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_el_text).

-behaviour(iso_element).

-include("iso_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% iso_element callbacks
%%====================================================================

-spec render(#text{}, #bounds{}, map()) -> iolist().
render(#text{visible = false}, _Bounds, _Opts) ->
    [];
render(#text{content = Content, style = Style, x = X, y = Y}, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    BaseStyle = maps:get(base_style, Opts, #{}),
    MergedStyle = maps:merge(Style, BaseStyle),
    [
        iso_ansi:move_to(ActualY + 1, ActualX + 1),
        iso_ansi:style_to_ansi(MergedStyle),
        iso_ansi:truncate_content(Content, Bounds#bounds.width - X),
        iso_ansi:reset_style()
    ].

-spec height(#text{}, #bounds{}) -> pos_integer().
height(#text{}, _Bounds) -> 1.

-spec width(#text{}, #bounds{}) -> pos_integer().
width(#text{width = auto, content = C}, _Bounds) ->
    string:length(unicode:characters_to_list(iolist_to_binary([C])));
width(#text{width = W}, _Bounds) -> W.

%% Text always has a fixed width based on content or explicit width
-spec fixed_width(#text{}) -> pos_integer().
fixed_width(#text{width = auto, content = C}) ->
    string:length(unicode:characters_to_list(iolist_to_binary([C])));
fixed_width(#text{width = W}) -> W.


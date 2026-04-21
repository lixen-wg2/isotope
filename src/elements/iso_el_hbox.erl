%%%-------------------------------------------------------------------
%%% @doc Isotope HBox Element
%%%
%%% Renders children horizontally with optional spacing.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_el_hbox).

-behaviour(iso_element).

-include("iso_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% iso_element callbacks
%%====================================================================

-spec render(#hbox{}, #bounds{}, map()) -> iolist().
render(#hbox{visible = false}, _Bounds, _Opts) ->
    [];
render(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, Opts) ->
    StartBounds = Bounds#bounds{
        x = Bounds#bounds.x + X,
        y = Bounds#bounds.y + Y
    },
    ChildWidths = iso_layout:calculate_hbox_widths(Children, Bounds, Spacing, X),
    {Output, _FinalX} = lists:foldl(
        fun({Child, ChildWidth}, {Acc, CurrentX}) ->
            ChildBounds = StartBounds#bounds{x = CurrentX, width = ChildWidth},
            ChildOutput = iso_element:render(Child, ChildBounds, Opts),
            {[Acc, ChildOutput], CurrentX + ChildWidth + Spacing}
        end,
        {[], StartBounds#bounds.x},
        lists:zip(Children, ChildWidths)
    ),
    Output.

-spec height(#hbox{}, #bounds{}) -> pos_integer().
height(#hbox{children = Children}, Bounds) ->
    case Children of
        [] -> 1;
        _ -> lists:max([iso_element:height(C, Bounds) || C <- Children])
    end.

-spec width(#hbox{}, #bounds{}) -> pos_integer().
width(#hbox{width = W, children = Children, spacing = Spacing}, Bounds) ->
    case W of
        auto ->
            case Children of
                [] -> 1;
                _ ->
                    Widths = [iso_element:width(C, Bounds) || C <- Children],
                    TotalSpacing = max(0, (length(Children) - 1) * Spacing),
                    lists:sum(Widths) + TotalSpacing
            end;
        _ -> W
    end.

-spec fixed_width(#hbox{}) -> auto | pos_integer().
fixed_width(#hbox{width = auto}) -> auto;
fixed_width(#hbox{width = W}) -> W.

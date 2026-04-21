%%%-------------------------------------------------------------------
%%% @doc Isotope Input Element
%%%
%%% Renders a text input field with cursor and placeholder support.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_el_input).

-behaviour(iso_element).

-include("iso_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% iso_element callbacks
%%====================================================================

-spec render(#input{}, #bounds{}, map()) -> iolist().
render(#input{visible = false}, _Bounds, _Opts) ->
    [];
render(#input{value = Value, placeholder = Placeholder, cursor_pos = CursorPos,
              style = Style, x = X, y = Y, width = W}, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Focused = maps:get(focused, Opts, false),
    BaseStyle = maps:get(base_style, Opts, #{}),
    
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
        true -> iso_ansi:truncate_content(DisplayText, FieldWidth);
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
    MergedStyle = maps:merge(FocusStyle, BaseStyle),
    
    %% Cursor positioning (show cursor at position if focused)
    CursorOutput = case Focused of
        true ->
            CursorCol = ActualX + 2 + min(CursorPos, FieldWidth - 1),
            [iso_ansi:move_to(ActualY + 1, CursorCol)];
        false -> []
    end,
    [
        iso_ansi:move_to(ActualY + 1, ActualX + 1),
        iso_ansi:style_to_ansi(MergedStyle),
        <<"[">>, PaddedText, <<"]">>,
        iso_ansi:reset_style(),
        CursorOutput
    ].

-spec height(#input{}, #bounds{}) -> pos_integer().
height(#input{}, _Bounds) -> 1.

-spec width(#input{}, #bounds{}) -> pos_integer().
width(#input{width = W}, _Bounds) ->
    case W of
        auto -> 20;
        _ -> W
    end.

-spec fixed_width(#input{}) -> auto | pos_integer().
fixed_width(#input{width = auto}) -> 20;
fixed_width(#input{width = W}) -> W.


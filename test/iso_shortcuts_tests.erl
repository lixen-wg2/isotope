%%%-------------------------------------------------------------------
%%% @doc Unit tests for iso_shortcuts.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_shortcuts_tests).

-include_lib("eunit/include/eunit.hrl").

parse_printable_char_test() ->
    ?assertEqual({char, $q}, iso_shortcuts:parse(<<"Q">>)),
    ?assertEqual({char, $q}, iso_shortcuts:parse({event, {char, $Q}})).

parse_named_keys_test() ->
    ?assertEqual(enter, iso_shortcuts:parse(<<"Enter">>)),
    ?assertEqual(escape, iso_shortcuts:parse(escape)),
    ?assertEqual({key, page_down}, iso_shortcuts:parse(<<"PageDown">>)),
    ?assertEqual({ctrl, $c}, iso_shortcuts:parse(<<"Ctrl+C">>)).

matches_specs_test() ->
    ?assert(iso_shortcuts:matches({event, {char, $H}}, <<"h">>)),
    ?assert(iso_shortcuts:matches({event, escape}, [<<"q">>, escape])),
    ?assertNot(iso_shortcuts:matches({event, {char, $x}}, <<"q">>)).

handle_static_result_test() ->
    State = #{count => 1},
    ?assertEqual(
        {stop, normal, State},
        iso_shortcuts:handle({event, {char, $Q}}, State, [{<<"q">>, stop}])).

handle_fun_result_test() ->
    State = #{count => 1},
    Result = iso_shortcuts:handle({event, {char, $n}}, State, [
        {<<"n">>, fun(S) -> {noreply, S#{count => 2}} end}
    ]),
    ?assertEqual({noreply, #{count => 2}}, Result),
    ?assertEqual(nomatch, iso_shortcuts:handle({event, {char, $x}}, State, [])).

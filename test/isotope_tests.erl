%%%-------------------------------------------------------------------
%%% @doc Tests for the public isotope API.
%%% @end
%%%-------------------------------------------------------------------
-module(isotope_tests).

-include_lib("eunit/include/eunit.hrl").
-include("iso_elements.hrl").

-export([view/1]).

selected_item_returns_zero_based_selection_test() ->
    ?assertEqual(<<"Processes">>,
                 isotope:selected_item([<<"Dashboard">>, <<"Processes">>], 1)).

selected_item_uses_first_item_for_missing_selection_test() ->
    ?assertEqual(<<"Dashboard">>, isotope:selected_item([<<"Dashboard">>], 4)).

selected_item_returns_undefined_for_empty_list_test() ->
    ?assertEqual(undefined, isotope:selected_item([], 0)).

selected_item_with_default_uses_first_item_for_missing_selection_test() ->
    ?assertEqual("Dashboard",
                 isotope:selected_item(["Dashboard", "Processes"], 4, "Fallback")).

selected_item_with_default_uses_default_for_empty_list_test() ->
    ?assertEqual("Fallback", isotope:selected_item([], 0, "Fallback")).

selected_item_reads_list_by_id_from_view_context_test() ->
    Tree = #list{id = menu_list, items = ["Dashboard", "Processes"], selected = 1},
    ?assertEqual("Processes", iso_engine:call_view(?MODULE, menu_list, Tree)).

selected_item_reads_nested_list_by_container_id_from_view_context_test() ->
    Tree = #box{id = menu_box, children = [
        #list{id = menu_list, items = ["Dashboard", "Processes"], selected = 1}
    ]},
    ?assertEqual("Processes", iso_engine:call_view(?MODULE, menu_box, Tree)).

selected_item_without_view_context_is_undefined_test() ->
    ?assertEqual(undefined, isotope:selected_item(menu_box)).

sigwinch_filter_suppresses_prim_tty_resize_message_test() ->
    Event = #{
        msg => {report, #{
            label => {supervisor, unexpected_msg},
            msg => {make_ref(), {signal, sigwinch}}
        }}
    },
    ?assertEqual(stop, isotope_app:filter_sigwinch(Event, [])).

sigwinch_filter_suppresses_raw_resize_message_test() ->
    Event = #{
        msg => {report, #{
            label => {gen_server, no_handle_info},
            message => sigwinch
        }}
    },
    ?assertEqual(stop, isotope_app:filter_sigwinch(Event, [])).

view(ElementId) ->
    isotope:selected_item(ElementId).

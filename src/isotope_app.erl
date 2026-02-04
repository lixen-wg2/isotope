%%%-------------------------------------------------------------------
%%% @doc Isotope application callback module.
%%% @end
%%%-------------------------------------------------------------------
-module(isotope_app).

-behaviour(application).

-export([start/2, stop/1]).

%%--------------------------------------------------------------------
%% @doc Start the Isotope application.
%% @end
%%--------------------------------------------------------------------
-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    iso_sup:start_link().

%%--------------------------------------------------------------------
%% @doc Stop the Isotope application.
%% @end
%%--------------------------------------------------------------------
-spec stop(term()) -> ok.
stop(_State) ->
    ok.


%%%-------------------------------------------------------------------
%%% @doc Isotope TUI Framework - Main API module.
%%%
%%% Isotope is a Nitrogen-inspired terminal UI framework for Erlang.
%%% This module provides the public API for starting and interacting
%%% with TUI applications.
%%% @end
%%%-------------------------------------------------------------------
-module(isotope).

%% API
-export([start/0, stop/0]).

%%--------------------------------------------------------------------
%% @doc Start the Isotope TUI application.
%% @end
%%--------------------------------------------------------------------
-spec start() -> ok | {error, term()}.
start() ->
    case application:ensure_all_started(isotope) of
        {ok, _} -> ok;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Stop the Isotope TUI application.
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok | {error, term()}.
stop() ->
    application:stop(isotope).

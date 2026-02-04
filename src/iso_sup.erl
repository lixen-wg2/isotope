%%%-------------------------------------------------------------------
%%% @doc Isotope top-level supervisor.
%%%
%%% Supervises:
%%% - iso_tty: TTY owner process (prim_tty state, cleanup)
%%% - iso_input: Input reader and parser
%%%
%%% Uses one_for_all strategy since all components depend on each other.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

%%--------------------------------------------------------------------
%% @doc Start the supervisor.
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%--------------------------------------------------------------------
%% @doc Supervisor init callback.
%% @end
%%--------------------------------------------------------------------
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 3,
        period => 5
    },

    Children = [
        #{
            id => iso_tty,
            start => {iso_tty, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [iso_tty]
        },
        #{
            id => iso_input,
            start => {iso_input, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [iso_input]
        }
    ],

    {ok, {SupFlags, Children}}.


%%%-------------------------------------------------------------------
%%% @doc Demo supervisor.
%%% @end
%%%-------------------------------------------------------------------
-module(demo_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 1,
        period => 5
    },
    Children = [
        #{
            id => demo_home,
            start => {iso_server, start_link, [{local, demo_ui}, demo_home, #{}]},
            restart => temporary,
            shutdown => 5000,
            type => worker,
            modules => [iso_server, demo_home]
        }
    ],
    {ok, {SupFlags, Children}}.


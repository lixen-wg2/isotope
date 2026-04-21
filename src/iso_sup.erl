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

    %% Only start TTY components if a TTY is available
    %% This allows the web demo to work without a real terminal
    Children = case has_tty() of
        true ->
            [
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
            ];
        false ->
            %% No TTY - running in web mode or headless
            []
    end,

    {ok, {SupFlags, Children}}.

%% Check if we have a TTY available
%% Only rely on prim_tty:init - it will fail with enotsup if no TTY
has_tty() ->
    try prim_tty:init(#{input => raw, output => raw}) of
        _TtyState ->
            %% prim_tty has no public close API for a probe-only init; a
            %% successful init is enough to tell us a TTY is available.
            true
    catch
        error:enotsup -> false;
        _:_ -> false
    end.

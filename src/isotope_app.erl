%%%-------------------------------------------------------------------
%%% @doc Isotope application callback module.
%%% @end
%%%-------------------------------------------------------------------
-module(isotope_app).

-behaviour(application).

-export([start/2, stop/1]).

%% Internal
-export([filter_sigwinch/2]).

%%--------------------------------------------------------------------
%% @doc Start the Isotope application.
%% @end
%%--------------------------------------------------------------------
-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    %% Filter out "supervisor received unexpected message: sigwinch" warnings.
    %% The BEAM delivers sigwinch to supervisors in the process tree and
    %% OTP supervisors log a warning for any unexpected message.
    logger:add_primary_filter(iso_sigwinch_filter, {fun filter_sigwinch/2, []}),
    iso_sup:start_link().

%%--------------------------------------------------------------------
%% @doc Stop the Isotope application.
%% @end
%%--------------------------------------------------------------------
-spec stop(term()) -> ok.
stop(_State) ->
    logger:remove_primary_filter(iso_sigwinch_filter),
    ok.

%%====================================================================
%% Internal
%%====================================================================

%% @doc Logger filter that suppresses "received unexpected message: sigwinch".
%% The BEAM runtime delivers raw sigwinch atoms to processes in the
%% supervision tree on terminal resize. OTP gen_server/supervisors log
%% a warning for any message they don't handle. This filter drops those.
filter_sigwinch(#{msg := {report, #{label := {gen_server, no_handle_info}, message := sigwinch}}}, _Extra) ->
    stop;
filter_sigwinch(#{msg := {report, #{label := {supervisor, unexpected_msg}, msg := sigwinch}}}, _Extra) ->
    stop;
filter_sigwinch(_LogEvent, _Extra) ->
    ignore.


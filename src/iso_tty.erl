%%%-------------------------------------------------------------------
%%% @doc TTY owner process for Isotope.
%%%
%%% Manages the terminal state using OTP 28's prim_tty module.
%%% Responsibilities:
%%% - Initialize raw mode terminal
%%% - Enter alternate screen buffer
%%% - Hide cursor
%%% - Ensure cleanup on exit (restore terminal state)
%%% - Provide write interface for rendering
%%% - Forward input data to iso_input for parsing
%%% @end
%%%-------------------------------------------------------------------
-module(iso_tty).

-behaviour(gen_server).

%% API
-export([start_link/0, stop/0, cleanup/0]).
-export([write/1, clear/0, get_size/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    tty_state :: prim_tty:state() | undefined,
    reader_ref :: reference() | undefined
}).

%% ANSI escape sequences
-define(ENTER_ALT_SCREEN, <<"\e[?1049h">>).
-define(EXIT_ALT_SCREEN, <<"\e[?1049l">>).
-define(HIDE_CURSOR, <<"\e[?25l">>).
-define(SHOW_CURSOR, <<"\e[?25h">>).
-define(RESET_ATTRS, <<"\e[0m">>).
-define(CLEAR_SCREEN, <<"\e[2J\e[H">>).
%% Mouse tracking (SGR extended mode for better coordinates)
-define(ENABLE_MOUSE, <<"\e[?1000h\e[?1006h">>).
-define(DISABLE_MOUSE, <<"\e[?1006l\e[?1000l">>).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%% @doc Cleanup terminal state (disable mouse, show cursor, exit alt screen).
%% This is called before shutdown to restore the terminal.
-spec cleanup() -> ok.
cleanup() ->
    gen_server:call(?MODULE, cleanup).

%% @doc Write raw data to the terminal.
-spec write(iodata()) -> ok.
write(Data) ->
    gen_server:call(?MODULE, {write, Data}).

%% @doc Clear the screen.
-spec clear() -> ok.
clear() ->
    write(?CLEAR_SCREEN).

%% @doc Get terminal size as {Cols, Rows}.
-spec get_size() -> {ok, {pos_integer(), pos_integer()}} | {error, term()}.
get_size() ->
    gen_server:call(?MODULE, get_size).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    process_flag(trap_exit, true),
    case init_tty() of
        {ok, TtyState} ->
            %% Get the reader reference from prim_tty handles
            #{read := ReaderRef} = prim_tty:handles(TtyState),
            %% Enter alternate screen, hide cursor, enable mouse
            do_write(TtyState, [?ENTER_ALT_SCREEN, ?HIDE_CURSOR, ?ENABLE_MOUSE, ?CLEAR_SCREEN]),
            %% Start reading input
            prim_tty:read(TtyState),
            {ok, #state{tty_state = TtyState, reader_ref = ReaderRef}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call({write, Data}, _From, State = #state{tty_state = TtyState}) ->
    do_write(TtyState, Data),
    {reply, ok, State};

handle_call(get_size, _From, State = #state{tty_state = TtyState}) ->
    Result = prim_tty:window_size(TtyState),
    {reply, Result, State};

handle_call(cleanup, _From, State = #state{tty_state = TtyState}) ->
    cleanup_tty(TtyState),
    {reply, ok, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

%% Handle input data from prim_tty reader - forward to iso_input
handle_info({ReaderRef, {data, Data}}, State = #state{reader_ref = ReaderRef, tty_state = TtyState}) ->
    %% Forward raw data to iso_input for parsing
    iso_input:handle_data(Data),
    %% Request more data
    prim_tty:read(TtyState),
    {noreply, State};

handle_info({ReaderRef, eof}, State = #state{reader_ref = ReaderRef}) ->
    %% Terminal closed
    {stop, normal, State};

handle_info({'EXIT', _Pid, _Reason}, State) ->
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{tty_state = TtyState}) ->
    cleanup_tty(TtyState),
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

init_tty() ->
    try
        TtyState = prim_tty:init(#{input => raw, output => raw}),
        {ok, TtyState}
    catch
        error:enotsup ->
            {error, no_tty_available};
        Class:Reason:Stack ->
            {error, {Class, Reason, Stack}}
    end.

do_write(_TtyState, Data) ->
    %% Use io:format with ~ts to properly handle UTF-8 unicode
    io:format(user, "~ts", [iolist_to_binary(Data)]).

cleanup_tty(undefined) ->
    ok;
cleanup_tty(TtyState) ->
    %% Restore terminal state
    do_write(TtyState, [
        ?RESET_ATTRS,
        ?DISABLE_MOUSE,
        ?SHOW_CURSOR,
        ?EXIT_ALT_SCREEN
    ]).


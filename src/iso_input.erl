%%%-------------------------------------------------------------------
%%% @doc Input driver for Isotope.
%%%
%%% Receives raw input from iso_tty and parses ANSI escape sequences into
%%% clean event messages. Forwards parsed events to iso_server.
%%%
%%% Parsed events:
%%% - {key, up | down | left | right | home | 'end' | page_up | page_down}
%%% - {char, Char} - Regular character
%%% - {ctrl, Char} - Control key (e.g., {ctrl, $c})
%%% - enter, tab, backspace, escape, delete
%%% @end
%%%-------------------------------------------------------------------
-module(iso_input).

-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([handle_data/1, set_target/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    buffer = <<>> :: binary(),
    target = undefined :: pid() | undefined
}).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%% @doc Handle raw input data from iso_tty.
-spec handle_data(binary()) -> ok.
handle_data(Data) ->
    gen_server:cast(?MODULE, {data, Data}).

%% @doc Set the target process to receive input events.
-spec set_target(pid()) -> ok.
set_target(Pid) ->
    gen_server:cast(?MODULE, {set_target, Pid}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({data, Data}, State = #state{buffer = Buffer, target = Target}) ->
    NewBuffer = <<Buffer/binary, Data/binary>>,
    {Events, RemainingBuffer} = parse_input(NewBuffer),
    lists:foreach(fun(E) -> send_event(E, Target) end, Events),
    {noreply, State#state{buffer = RemainingBuffer}};

handle_cast({set_target, Pid}, State) ->
    {noreply, State#state{target = Pid}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

send_event(Event, Target) ->
    %% Send to target process
    case Target of
        undefined -> ok;
        Pid when is_pid(Pid) -> Pid ! {input, Event}
    end.

%% Parse input buffer into events
-spec parse_input(binary()) -> {[term()], binary()}.
parse_input(Buffer) ->
    parse_input(Buffer, []).

parse_input(<<>>, Acc) ->
    {lists:reverse(Acc), <<>>};

%% Escape sequences
parse_input(<<"\e[A", Rest/binary>>, Acc) -> parse_input(Rest, [{key, up} | Acc]);
parse_input(<<"\e[B", Rest/binary>>, Acc) -> parse_input(Rest, [{key, down} | Acc]);
parse_input(<<"\e[C", Rest/binary>>, Acc) -> parse_input(Rest, [{key, right} | Acc]);
parse_input(<<"\e[D", Rest/binary>>, Acc) -> parse_input(Rest, [{key, left} | Acc]);
parse_input(<<"\e[H", Rest/binary>>, Acc) -> parse_input(Rest, [{key, home} | Acc]);
parse_input(<<"\e[F", Rest/binary>>, Acc) -> parse_input(Rest, [{key, 'end'} | Acc]);
parse_input(<<"\e[5~", Rest/binary>>, Acc) -> parse_input(Rest, [{key, page_up} | Acc]);
parse_input(<<"\e[6~", Rest/binary>>, Acc) -> parse_input(Rest, [{key, page_down} | Acc]);
parse_input(<<"\e[3~", Rest/binary>>, Acc) -> parse_input(Rest, [delete | Acc]);
parse_input(<<"\e[Z", Rest/binary>>, Acc) -> parse_input(Rest, [{key, btab} | Acc]);  %% Shift+Tab

%% SGR Mouse events: \e[<button;col;rowM (press) or \e[<button;col;rowm (release)
parse_input(<<"\e[<", Rest/binary>>, Acc) ->
    case parse_mouse_sgr(Rest) of
        {ok, Event, Remaining} ->
            parse_input(Remaining, [Event | Acc]);
        incomplete ->
            {lists:reverse(Acc), <<"\e[<", Rest/binary>>}
    end;

%% Incomplete escape sequence - check if it looks like start of valid sequence
parse_input(<<"\e[", Rest/binary>> = Buffer, Acc) when byte_size(Rest) < 2 ->
    {lists:reverse(Acc), Buffer};

%% Standalone Escape key (no [ following, so not an escape sequence)
parse_input(<<"\e", Rest/binary>>, Acc) when byte_size(Rest) == 0 ->
    %% Just ESC alone - send it as escape event
    {lists:reverse([escape | Acc]), <<>>};
parse_input(<<"\e", C, Rest/binary>>, Acc) when C =/= $[ ->
    %% ESC followed by non-[ character - send escape and continue parsing
    parse_input(<<C, Rest/binary>>, [escape | Acc]);

%% Special keys (must come before control characters to avoid Tab being Ctrl+I)
parse_input(<<9, Rest/binary>>, Acc) -> parse_input(Rest, [tab | Acc]);
parse_input(<<13, Rest/binary>>, Acc) -> parse_input(Rest, [enter | Acc]);
parse_input(<<127, Rest/binary>>, Acc) -> parse_input(Rest, [backspace | Acc]);

%% Control characters
parse_input(<<0, Rest/binary>>, Acc) -> parse_input(Rest, [{ctrl, $@} | Acc]);  %% Ctrl+@/Space
parse_input(<<C, Rest/binary>>, Acc) when C >= 1, C =< 26 ->
    parse_input(Rest, [{ctrl, C + $a - 1} | Acc]);
parse_input(<<28, Rest/binary>>, Acc) -> parse_input(Rest, [{ctrl, $\\} | Acc]);
parse_input(<<29, Rest/binary>>, Acc) -> parse_input(Rest, [{ctrl, $]} | Acc]);
parse_input(<<30, Rest/binary>>, Acc) -> parse_input(Rest, [{ctrl, $^} | Acc]);
parse_input(<<31, Rest/binary>>, Acc) -> parse_input(Rest, [{ctrl, $_} | Acc]);

%% Regular characters (including UTF-8)
parse_input(<<C/utf8, Rest/binary>>, Acc) when C >= 32 ->
    parse_input(Rest, [{char, C} | Acc]);

%% Unknown byte - skip
parse_input(<<_, Rest/binary>>, Acc) ->
    parse_input(Rest, Acc).

%% Parse SGR mouse format: button;col;rowM or button;col;rowm
%% Button: 0=left, 1=middle, 2=right, 32+=motion, 64+=scroll
parse_mouse_sgr(Data) ->
    case binary:split(Data, [<<"M">>, <<"m">>]) of
        [Params, Rest] ->
            %% Determine if press or release based on terminator
            IsPress = case binary:match(Data, <<"M">>) of
                {Pos, _} ->
                    case binary:match(Data, <<"m">>) of
                        {Pos2, _} -> Pos < Pos2;
                        nomatch -> true
                    end;
                nomatch -> false
            end,
            case binary:split(Params, <<";">>, [global]) of
                [ButtonBin, ColBin, RowBin] ->
                    try
                        Button = binary_to_integer(ButtonBin),
                        Col = binary_to_integer(ColBin),
                        Row = binary_to_integer(RowBin),
                        ButtonType = case Button band 3 of
                            0 -> left;
                            1 -> middle;
                            2 -> right;
                            3 -> release
                        end,
                        EventType = if
                            Button >= 64 -> scroll;
                            Button >= 32 -> motion;
                            IsPress -> click;
                            true -> release
                        end,
                        Event = {mouse, EventType, ButtonType, Col, Row},
                        {ok, Event, Rest}
                    catch
                        _:_ -> incomplete
                    end;
                _ -> incomplete
            end;
        _ -> incomplete
    end.


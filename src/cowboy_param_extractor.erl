%%%-------------------------------------------------------------------
%%% @author Valery Meleshkin <valery.meleshkin@gmail.com>
%%% @copyright 2015
%%%-------------------------------------------------------------------

-module(cowboy_param_extractor).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([run/3, run/4]).
-export([as_non_neg_integer/0, as_atom/1, as_binary/0]).


-type mapping_element() 
 :: {qs_val,  Param :: binary(),
     StateI :: non_neg_integer(), validator()}
  | {binding, Param :: atom(),
     StateI :: non_neg_integer(), validator()}.
-type mapping() :: [mapping_element()].
%% A `validator' must `throw' to indicate an error
-type validator() :: fun((binary()) -> any()).
-type format_error_fun() :: fun((binary()) -> binary()).

-spec run(mapping(), cowboy_req:req(), State) ->
    {cowboy_req:req(), State} when State :: any().
run(Mapping, Req, State) ->
    IDF = fun(X) -> X end,
    run(Mapping, Req, IDF, State).

-spec run(mapping(), cowboy_req:req(), format_error_fun(), State) ->
    {cowboy_req:req(), State} when State :: any().
run(Mapping, Req, FormatErrorF, State)
  when is_function(FormatErrorF, 1) ->
    try
        {Req1, State1} = fold_extract(Mapping, Req, State),
        {false, Req1, State1}
    catch
        throw:{P, BinV, E} -> 
            ErrTxt = iolist_to_binary(
                       io_lib:format("Param '~s', submitted '~s', ~p",
                                     [P, BinV, E])),
            ReqE = cowboy_req:set_resp_body(
                     FormatErrorF(ErrTxt), Req),
            {true, ReqE, State}
    end.

%% ------------------------------------------------------------------
%% Validators
%% ------------------------------------------------------------------

as_binary() ->
    fun(Bin) when is_binary(Bin) -> 
            iolist_to_binary(http_uri:decode(binary_to_list(Bin)))
    end.

as_non_neg_integer() ->
    IntF = as_integer(),
    fun(Bin) ->
            case IntF(Bin) of
                I when I >= 0 -> I;
                _ -> throw({expected, non_negative})
            end
    end.

as_integer() ->
    fun(Bin) ->
            try binary_to_integer(Bin)
            catch error:badarg ->
                      throw({expected, integer})
            end
    end.

as_atom(Expected) ->
    Error = {expected, {oneof, Expected}},
    fun(Bin) ->
            try binary_to_existing_atom(Bin, utf8) of
                A -> 
                    case lists:member(A, Expected) of
                        true -> A;
                        false -> throw(Error)
                    end
            catch
                error:badarg -> throw(Error)
            end
    end.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

fold_extract(Mapping, Req, State) ->
    lists:foldl(
      fun({Type, Param, Sti, F}, {R, St}) 
            when (Type == qs_val) and is_binary(Param);
                 (Type == binding) and is_atom(Param) ->
              {BinV, R1} = cowboy_req:Type(Param, R),
              case {BinV, Type} of
                  {undefined, qs_val} ->
                      {R1, St};
                  {undefined, binding} ->
                      throw({Param, <<>>, mandatory});
                  {true, _} ->
                      throw({Param, <<>>, mandatory});
                  {Bin, _} when is_binary(Bin) ->
                      V = try F(Bin)
                          catch throw:Reason ->
                                    throw({Param, Bin, Reason})
                          end,
                      {R1, setelement(Sti, St, V)}
              end
      end, {Req, State}, Mapping).

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

-record(state, { user, attr, limit }).

routes() -> [{"/users/:user/attributes/:attr", ?MODULE, []}].
mapping() ->
    AllowedAttrs = [friends, messages],
    [
     {binding, user, #state.user, as_binary()},
     {binding, attr, #state.attr, as_atom(AllowedAttrs)},
     {qs_val, <<"limit">>, #state.limit, as_non_neg_integer()}
    ].

make_req(Path, QS) ->
    Req = cowboy_req:new(
            undefined,       % Sock
            ranch_tcp,       % Protocol
            undefined,       % Peer % {Host, Port}
            <<"GET">>,       % Method
            Path,            % Path
            QS,              % QS
            'HTTP/1.1',      % HTTP version
            [],              % Headers
            <<>>, undefined, % Host, Port
            <<>>,            % Buffer,
            false,           % Keep-Alive
            false,           % Compress
            undefiened       % On-Resp fun
           ),
    DispRules = cowboy_router:compile([{'_', routes()}]),
    {ok, Req1, _Env} = cowboy_router:execute(Req, [{dispatch, DispRules}]),
    Req1.

run_test(Path, QS) ->
    run(mapping(), make_req(Path, QS),
        fun(Err) -> ?debugFmt("Malformation report: ~s", [Err]), Err end,
        #state{}).

positive_test() ->
    {false, _,
     #state{ user = <<"foo">>,
             attr = messages,
             limit = 10
           }
    } = run_test(<<"/users/foo/attributes/messages">>, <<"limit=10">>),
    {false, _,
     #state{ user = <<"foo">>,
             attr = friends,
             limit = undefined
           }
    } = run_test(<<"/users/foo/attributes/friends">>, <<>>).

negative_test() ->
    {true, _, _} = run_test(<<"/users/banana/attributes/banana">>, <<>>),
    {true, _, _} = run_test(<<"/users/banana/attributes/messages">>, <<"limit=baz">>),
    {true, _, _} = run_test(<<"/users/banana/attributes/messages">>, <<"limit=-1">>).

-endif.

%% Copyright (c) 2013-2019 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

%% @doc TODO:
%% 1. Flapping Detection
%% 2. Conflict Detection?


%% @doc flapping detect algorithm
%% * Storing the results of the last 21 checks of the host or service
%% * Analyzing the historical check results and determine where state
%%   changes/transitions occur
%% * Using the state transitions to determine a percent state change value
%%   (a measure of change) for the host or service
%% * Comparing the percent state change value against low and high flapping thresholds
-module(emqx_flapping).

-include("emqx.hrl").
-include("logger.hrl").
-include("types.hrl").

-behaviour(gen_statem).

-export([start_link/1]).

%% This module is used to garbage clean the flapping records

%% gen_statem callbacks
-export([ terminate/3
        , code_change/4
        , init/1
        , initialized/3
        , callback_mode/0
        ]).

-define(FLAPPING_TAB, ?MODULE).

%% Mnesia bootstrap
-export([check/1]).


-record(flapping,
        { client_id       :: binary()
        , check_times = 0 :: pos_integer()
        , timestamp       :: erlang:timestamp()
        }).

check(ClientId) ->
    CheckTimes = #flapping.check_times,
    case ets:update_counter(?FLAPPING_TAB, ClientId, {CheckTimes, 1}) of
        CheckTimes -> ok;
        _ -> ok
    end.

update(ClientId, CheckTimes) ->
    ok.

%%--------------------------------------------------------------------
%%
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% gen_statem callbacks
%%--------------------------------------------------------------------
-spec(start_link(Config :: list() | map()) -> startlink_ret()).
start_link(Config) when is_list(Config) ->
    start_link(maps:from_list(Config));
start_link(Config) ->
    gen_statem:start_link({local, ?MODULE}, ?MODULE, Config, []).

init(Config) ->
    TabOpts = [public, set, {write_concurrency, true}, {read_concurrency, true}],
    ok = emqx_tables:new(?FLAPPING_TAB, TabOpts),
    {ok, initialized, #{time => maps:get(timer, Config, 3600000)}}.

callback_mode() -> [state_functions, state_enter].

initialized(enter, _OldState, #{time := Time}) ->
    Action = {state_timeout, Time, gc_flapping},
    {keep_state_and_data, Action};
initialized(state_timeout, gc_flapping, _StateData) ->
    gc_flapping(),
    repeat_state_and_data.

code_change(_Vsn, State, Data, _Extra) ->
    {ok, State, Data}.

terminate(_Reason, _StateName, _State) ->
    ok.

%%--------------------------------------------------------------------
%% state functions
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

%% do flapping gc in database
gc_flapping() ->
    ok.

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

-include_lib("emqx/include/logger.hrl").

-behaviour(gen_statem).

-export([start_link/0]).

%% This module is used to garbage clean the flapping records

%% gen_statem callbacks
-export([ terminate/3
        , code_change/4
        , init/1
        , callback_mode/0
        ]).

-define(TAB, ?MODULE).

%% Mnesia bootstrap
-export([mnesia/1]).

-boot_mnesia({mnesia, [boot]}).
-copy_mnesia({mnesia, [copy]}).

-record(flapping,
        { client_id       :: binary()
        , check_times     :: pos_integer()
        , timestamp       :: timestamp()
        }).

%%------------------------------------------------------------------------------
%% Mnesia bootstrap
%%------------------------------------------------------------------------------

mnesia(boot) ->
    ok = ekka_mnesia:create_table(?TAB, [
                {type, set},
                {ram_copies, [node()]},
                {record_name, flapping},
                {local_content, true},
                {attributes, record_info(fields, flapping)},
                {storage_properties, [{ets, [{read_concurrency, true},
                                             {write_concurrency, true}]}]}]);

mnesia(copy) ->
    ok = ekka_mnesia:copy_table(?TAB).

check(#{ client_id := ClientId }) ->
    ets:member(?TAB, _)

%%--------------------------------------------------------------------
%% gen_statem callbacks
%%--------------------------------------------------------------------

-spec(start_link() -> {ok, pid()} | ignore | {error, any()}).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
    erlang:process_flag(trap_exit, true),
    load_hooks(),
    {ok, service_running, #{}}.

callback_mode() -> [state_functions].

code_change(_Vsn, State, Data, _Extra) ->
    {ok, State, Data}.

terminate(_Reason, _StateName, _State) ->
    unload_hooks(),
    ok.

%%--------------------------------------------------------------------
%% state functions
%%--------------------------------------------------------------------


%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

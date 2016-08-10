% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
% http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

-module(couch_log_config_listener_test).


-include_lib("couch_log/include/couch_log.hrl").
-include_lib("eunit/include/eunit.hrl").


couch_log_config_test_() ->
    {setup,
        fun couch_log_test_util:start/0,
        fun couch_log_test_util:stop/1,
        [
            fun check_restart_listener/0,
            fun check_ignore_non_log/0
        ]
    }.


check_restart_listener() ->
    ?assertNotEqual(not_found, get_handler()),
    gen_event:delete_handler(config_event, get_handler(), testing),
    ?assertEqual(not_found, get_handler()),
    timer:sleep(1000),
    ?assertNotEqual(not_found, get_handler()).


check_ignore_non_log() ->
    Run = fun() ->
        couch_log_test_util:with_config_listener(fun() ->
            config:set("foo", "bar", "baz"),
            couch_log_test_util:wait_for_config()
        end)
    end,
    ?assertError(config_change_timeout, Run()).


get_handler() ->
    FoldFun = fun
        ({config_listener, {couch_log_config_listener, _}} = H, not_found) ->
            H;
        (_, Acc) ->
            Acc
    end,
    lists:foldl(FoldFun, not_found, gen_event:which_handlers(config_event)).

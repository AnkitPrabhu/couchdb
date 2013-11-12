#!/usr/bin/env escript
%% -*- erlang -*-
%%! -smp enable

% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

test_set_name() -> <<"couch_test_couch_upr">>.
num_set_partitions() -> 4.
num_docs() -> 1000.


main(_) ->
    test_util:init_code_path(),

    etap:plan(5),
    case (catch test()) of
        ok ->
            etap:end_tests();
        Other ->
            etap:diag(io_lib:format("Test died abnormally: ~p", [Other])),
            etap:bail(Other)
    end,
    %init:stop(),
    %receive after infinity -> ok end,
    ok.


test() ->
    couch_set_view_test_util:start_server(test_set_name()),
    setup_test(),

    TestFun = fun(Item, Acc) ->
        [Item|Acc]
    end,

    {ok, Pid} = couch_upr:start(),

    % First parameter is the partition, the second is the sequence number
    % to start at.
    {ok, Docs1} = couch_upr:enum_docs_since(Pid, 0, 4, 10, TestFun, []),
    etap:is(length(Docs1), 6, "Correct number of docs (6) in partition 0"),

    {ok, Docs2} = couch_upr:enum_docs_since(Pid, 1, 46, 165, TestFun, []),
    etap:is(length(Docs2), 119, "Correct number of docs (109) parition 1"),
    {ok, Docs3} = couch_upr:enum_docs_since(
        Pid, 2, 80, num_docs() div num_set_partitions(), TestFun, []),
    Expected3 = (num_docs() div num_set_partitions()) - 80,
    etap:is(length(Docs3), Expected3,
        io_lib:format("Correct number of docs (~p) parition 2", [Expected3])),
    {ok, Docs4} = couch_upr:enum_docs_since(Pid, 3, 0, 5, TestFun, []),
    etap:is(length(Docs4), 5, "Correct number of docs (5) parition 3"),

    % Try a too high sequence number to get a rollback response
    {rollback, RollbackSeq} = couch_upr:enum_docs_since(
        Pid, 0, 400, 450, TestFun, []),
    etap:is(RollbackSeq, num_docs() div num_set_partitions(),
        "Correct rollback sequence number"),

    couch_set_view_test_util:stop_server(),
    ok.

setup_test() ->
    couch_set_view_test_util:delete_set_dbs(test_set_name(), num_set_partitions()),
    couch_set_view_test_util:create_set_dbs(test_set_name(), num_set_partitions()),
    populate_set().


doc_id(I) ->
    iolist_to_binary(io_lib:format("doc_~8..0b", [I])).

create_docs(From, To) ->
    lists:map(
        fun(I) ->
            Cas = I,
            ExpireTime = 0,
            Flags = 0,
            RevMeta1 = <<Cas:64/native, ExpireTime:32/native, Flags:32/native>>,
            RevMeta2 = [[io_lib:format("~2.16.0b",[X]) || <<X:8>> <= RevMeta1 ]],
            RevMeta3 = iolist_to_binary(RevMeta2),
            {[
              {<<"meta">>, {[
                             {<<"id">>, doc_id(I)},
                             {<<"rev">>, <<"1-", RevMeta3/binary>>}
                            ]}},
              {<<"json">>, {[{<<"value">>, I}]}}
            ]}
        end,
        lists:seq(From, To)).

populate_set() ->
    etap:diag("Populating the " ++ integer_to_list(num_set_partitions()) ++
        " databases with " ++ integer_to_list(num_docs()) ++ " documents"),
    DocList = create_docs(1, num_docs()),
    ok = couch_set_view_test_util:populate_set_sequentially(
        test_set_name(),
        lists:seq(0, num_set_partitions() - 1),
        DocList).

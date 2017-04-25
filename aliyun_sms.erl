-module(aliyun_sms).
-export([seed/0, send/6]).
-export([test_sms/0]).

seed() ->
    <<A:32,B:32,C:32>> = crypto:strong_rand_bytes(12),
    random:seed({A, B, C}).

%% 当前时间转换UTC
format_utc_timestamp() ->  
    TS = os:timestamp(),  
    {{Year,Month,Day},{Hour,Minute,Second}} = calendar:now_to_universal_time(TS),  
    lists:flatten(io_lib:format("~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0wZ",
                                [Year,Month,Day,Hour,Minute,Second])).

rand_str(Len) ->
    AllowedChars = "0123456789abcdefghijklmnopqrstuvwxyz",
    lists:foldl(fun(_, Acc) -> [lists:nth(random:uniform(length(AllowedChars)),  AllowedChars)]  ++ Acc  end, [], lists:seq(1, Len)).

request(Url, Timeout) ->
    HttpOpts = [{timeout, Timeout}],                                   
    Opts = [{sync, true}, {body_format, binary}, {full_result, false}],
    httpc:request(get, {Url, []}, HttpOpts, Opts).                     

make_url(RecNum, SignName, TemplateCode, AccessKeyId, AccessSecret, ParamString) ->
    Format = "JSON",
    Version = "2016-09-27",
    SignatureMethod = "HMAC-SHA1",
    Timestamp = format_utc_timestamp(),
    SignatureVersion = "1.0",
    SignatureNonce = rand_str(16),
    Action = "SingleSendSms",
    QueryList = [{"Format", Format},
                 {"Version", Version},
                 {"AccessKeyId", AccessKeyId},
                 {"SignatureMethod", SignatureMethod},
                 {"Timestamp", Timestamp},
                 {"SignatureVersion", SignatureVersion},
                 {"SignatureNonce", SignatureNonce},
                 {"Action", Action},
                 {"SignName", SignName},
                 {"TemplateCode", TemplateCode},
                 {"RecNum", RecNum},
                 {"ParamString", ParamString}
                ],                   
    QueryList2 = lists:foldl(fun({K, V}, Acc) -> 
                                     case K =:= "SignName" of
                                         true ->
                                             % 中文特别处理
                                             [http_uri:encode(K) ++ "=" ++ 
                                              encode(unicode:characters_to_binary(V)) | Acc];
                                         false ->
                                             [http_uri:encode(K) ++ "=" ++ http_uri:encode(V) | Acc]
                                     end
                             end, [], QueryList),
    SortFun = fun(A, B) ->
                      B > A
              end,
    QueryList3 = lists:sort(SortFun, QueryList2),
    QueryList4 = string:join(QueryList3, "&"),
    QueryList5 = lists:append(["GET", "&%2F&", http_uri:encode(QueryList4)]),
    % 计算签名
    <<Mac:160/integer>> = crypto:hmac(sha, AccessSecret++"&", QueryList5),
    Signature = http_uri:encode(binary_to_list(base64:encode(<<Mac:160>>))),
    QueryList6 = lists:append([QueryList4, "&", "Signature=", Signature]),
    Url = "http://sms.aliyuncs.com/?",
    Url ++ QueryList6.

send(RecNum, SignName, TemplateCode, AccessKeyId, AccessSecret, ParamString) ->
    Url = make_url(RecNum, SignName, TemplateCode, AccessKeyId, AccessSecret, ParamString),
    io:format("url ~p~n", [Url]),
    case request(Url, 3000) of
        {ok, {200, _Ret}} ->
            io:format("ok:200 ~p~n", [_Ret]),
            ok;
        {ok, {_Status, _Ret}} ->
            io:format("ok:~p~n", [_Ret]),
            ok;
        {error, _Ret} ->
            {error, _Ret}
    end.

encode(S) when is_list(S) ->
        encode(unicode:characters_to_binary(S));
encode(<<C:8, Cs/binary>>) when C >= $a, C =< $z ->
        [C] ++ encode(Cs);
encode(<<C:8, Cs/binary>>) when C >= $A, C =< $Z ->
        [C] ++ encode(Cs);
encode(<<C:8, Cs/binary>>) when C >= $0, C =< $9 ->
        [C] ++ encode(Cs);
encode(<<C:8, Cs/binary>>) when C == $. ->
        [C] ++ encode(Cs);
encode(<<C:8, Cs/binary>>) when C == $- ->
        [C] ++ encode(Cs);
encode(<<C:8, Cs/binary>>) when C == $_ ->
        [C] ++ encode(Cs);
encode(<<C:8, Cs/binary>>) ->
        escape_byte(C) ++ encode(Cs);
encode(<<>>) ->
        "".

escape_byte(C) ->
        "%" ++ hex_octet(C).

hex_octet(N) when N =< 9 ->
        [$0 + N];
hex_octet(N) when N > 15 ->
        hex_octet(N bsr 4) ++ hex_octet(N band 15);
hex_octet(N) ->
        [N - 10 + $A].

%%----------------------------
test_sms() ->
    aliyun_sms:send("1350000****","****", "SMS_****", "LTA************", "YVr******************", "{\"code\":\"88\",\"expire\":\"5\"}"). 

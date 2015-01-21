# Cowboy Parameter Extractor and Validator

Small library that helps extract and validate params of request in a Cowboy REST handler.

## Usage example

Suppose you have a route `[{"/users/:user/attributes/:attr", your_handler, []}]`
that points to your `cowboy_rest` handler. Then using this library you can write 
`malformed_request` check as following:

```
-record(state, { user, attr, limit }).

%% ...

malformed_request(Req, #state{} = State) ->
    AllowedAttrs = [friends, messages],
    Mapping = [
     {binding, user, #state.user, as_binary()},
     {binding, attr, #state.attr, as_atom(AllowedAttrs)},
     {qs_val, <<"limit">>, #state.limit, as_non_neg_integer()}
    ],
    cowboy_param_extractor:run(Mapping, Req, State).

```

Error message that normally is set as a response body can be altered
via optional callback.

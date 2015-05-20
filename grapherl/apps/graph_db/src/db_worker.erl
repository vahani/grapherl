-module(db_worker).


-behaviour(gen_server).

%% Api functions
-export([start_link/1,
         store/2,
         retrive/1,
         dump_data/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include_lib("apps/grapherl/include/grapherl.hrl").
-include_lib("graph_db_records.hrl").

%-record(state, {db_mod, cache_mod}).

%%%===================================================================
%%% API functions
%%%===================================================================

%% store data point in cache db
store(MetricName, Data) ->
    poolboy:transaction(?DB_POOL,
                        fun(Worker) ->
                                gen_server:cast(Worker, {store, MetricName, Data})
                        end).

%% get data points for Metric from cache and databse.
retrive(MetricName) ->
    poolboy:transaction(?DB_POOL,
                        fun(Worker) ->
                                gen_server:call(Worker, {read_metric, MetricName})
                        end).

%% dump cache to databse after TIMEOUT
dump_data(MetricName) ->
    poolboy:tanscation(?DB_POOL,
                      fun(Worker) ->
                              gen_server:cast(Worker, {dump_to_disk, MetricName})
                      end).


%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Args) ->
    gen_server:start_link(?MODULE, [Args], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Args]) ->
    ?INFO("~p starting with args: ~p ~n", [?MODULE, Args]),
    case graph_utils:get_args(Args, [db_mod, cache_mod]) of
        {ok, [DbMod, CacheMod]} ->
            {ok, #state{db_mod=DbMod, cache_mod=CacheMod}};
        _ ->
            ?ERROR("ERROR(~p): no UDP socket found.~n", [?MODULE]),
            {stop, no_socket}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({read_metric, MetricName}, _From, #state{db_mod=Db, cache_mod=Cache}=State) ->
    {CacheData, State0} = Cache:read_all(MetricName, State),
    {DbData, State1}    = Db:read_all(MetricName, State0),
    {reply, lists:flatten([CacheData | DbData]), State1};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({store, MetricName, DataPoint}, #state{cache_mod=Cache}=State) ->
    {ok, State0} = Cache:insert(MetricName, DataPoint, State),
    {noreply, State0};

handle_cast({dump_to_disk, MetricName}, #state{db_mod=Db, cache_mod=Cache}=State) ->
    {Data, State0} = Cache:read_all(MetricName, State),
    {ok, State1}   = Db:insert_many(MetricName, Data, State0),
    {ok, State2}   = Cache:delete_all(MetricName, State1),
    {noreply, State2};

handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
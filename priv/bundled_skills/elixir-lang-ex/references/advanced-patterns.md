# LangEx Advanced Patterns

## Table of Contents

1. [Subgraphs](#subgraphs)
2. [Send Fan-Out (Map-Reduce)](#send-fan-out)
3. [Command Routing](#command-routing)
4. [Resilient LLM Wrapper](#resilient-llm-wrapper)
5. [Context Compaction](#context-compaction)
6. [Tool Annotations](#tool-annotations)
7. [Telemetry](#telemetry)
8. [Sequences](#sequences)
9. [Anthropic-Specific Features](#anthropic-specific-features)
10. [Postgres Durable Workflows](#postgres-durable-workflows)
11. [Full ReAct Agent with All Features](#full-react-agent)

## Subgraphs

Use a compiled graph as a node inside another graph. The inner graph receives shared state keys, executes its own nodes, and returns updates to the outer graph.

```elixir
inner =
  Graph.new(value: 0)
  |> Graph.add_node(:double, fn state -> %{value: state.value * 2} end)
  |> Graph.add_edge(:__start__, :double)
  |> Graph.add_edge(:double, :__end__)
  |> Graph.compile()

outer =
  Graph.new(value: 0, label: "")
  |> Graph.add_node(:sub, inner)
  |> Graph.add_node(:tag, fn _state -> %{label: "done"} end)
  |> Graph.add_edge(:__start__, :sub)
  |> Graph.add_edge(:sub, :tag)
  |> Graph.add_edge(:tag, :__end__)
  |> Graph.compile()

{:ok, %{value: 14, label: "done"}} = LangEx.invoke(outer, %{value: 7})
```

### Subgraph Schema Mapping

When a subgraph has a different schema than the outer graph, only **overlapping keys** are shared. The subgraph sees the outer state filtered to its own schema keys, executes, and returns updates only for its keys. Non-overlapping outer keys are preserved unchanged.

```elixir
# Inner graph only knows about :messages
inner = Graph.new(messages: {[], &Message.add_messages/2})
  |> ...
  |> Graph.compile()

# Outer graph has :messages (shared) + :status, :approved (outer-only)
outer = Graph.new(
  messages: {[], &Message.add_messages/2},
  status: nil,
  approved: false
)
|> Graph.add_node(:sub, inner)   # inner sees only :messages
|> ...
```

Use subgraphs to encapsulate reusable agent patterns (e.g., a research sub-agent, a code-review sub-agent) that compose into larger pipelines.

## Send Fan-Out (Complete Lifecycle)

`%LangEx.Types.Send{}` enables dynamic fan-out where a node spawns work across multiple target nodes with custom payloads. This is the map-reduce primitive in LangEx.

### %Send{} Struct

Only two fields, both required (`@enforce_keys`):

```elixir
%LangEx.Types.Send{
  node: atom(),   # target node to execute
  state: map()    # state passed to the target node (REPLACES graph state, not a merge)
}
```

### How Fan-Out Works

1. A dispatch node returns a **list of `%Send{}` structs** (not a map — they are mutually exclusive)
2. `%Send{state: payload}` **replaces** the graph state for that branch — the worker receives ONLY the Send payload, not the full graph state. Include any data the worker needs in the payload.
3. All fan-out branches execute in the **same super-step** (parallel via Task.Supervisor)
4. Each branch's return value is merged into the **main** graph state via reducers
5. **All branches must complete** before the next super-step begins (edges from the worker node fire once, after all branches)
6. The dispatch node does NOT need an explicit `add_edge` — `%Send{}` bypasses normal edge routing
7. **No error isolation** — if one branch crashes, the entire super-step fails. Wrap risky work in try/rescue inside worker nodes.
8. **Empty list `[]`** — valid return; no nodes are scheduled, the step completes normally and the next edge fires

### Complete Fan-Out Example

```elixir
alias LangEx.Types.Send

graph =
  Graph.new(
    tasks: [],
    results: {[], fn existing, new -> existing ++ List.wrap(new) end},
    total: {0, &Kernel.+/2}
  )
  |> Graph.add_node(:dispatch, fn state ->
    # Return a list of %Send{} — no map return, no edges needed FROM :dispatch
    # IMPORTANT: include everything the worker needs in Send state,
    # because the worker does NOT see the parent graph state
    Enum.map(state.tasks, fn task ->
      %Send{node: :worker, state: %{current_task: task}}
    end)
  end)
  |> Graph.add_node(:worker, fn state ->
    # state is ONLY what was in %Send{state: ...} — e.g. %{current_task: "a"}
    # state.tasks does NOT exist here (not passed in Send payload)
    result = process(state.current_task)
    # Return partial update — merged into MAIN graph state via reducers
    %{results: [result], total: 1}
  end)
  |> Graph.add_node(:aggregate, fn state ->
    # Runs AFTER all workers complete
    # state.results has ALL worker results (accumulated by reducer)
    # state.total is the sum across all branches
    summary = Enum.join(state.results, ", ")
    %{summary: summary}
  end)
  |> Graph.add_edge(:__start__, :dispatch)
  # No edge from :dispatch — %Send{} handles routing
  |> Graph.add_edge(:worker, :aggregate)    # fires once after ALL workers
  |> Graph.add_edge(:aggregate, :__end__)
  |> Graph.compile()

{:ok, result} = LangEx.invoke(graph, %{tasks: ["a", "b", "c"]})
# result.results => [result_a, result_b, result_c]  (order may vary)
# result.total => 3
```

### Key Points

- **`%Send{}` and maps are mutually exclusive** — a node returns `[%Send{}, ...]` OR `%{key: val}`, never both
- **Workers receive ONLY the Send state** — not the parent graph state. Pass everything the worker needs.
- **Worker returns merge into main graph state** — via reducers, accumulating across all branches
- **No `add_edge` from dispatch** — `%Send{}` bypasses normal edge routing
- **Edge from worker fires once** — after ALL branches complete
- **One crash kills all** — no per-branch error isolation; use try/rescue in workers for resilience
- **Empty `[]` is valid** — no nodes scheduled, step completes, next edge fires normally
- **Fan-out to different nodes** — each `%Send{}` can target a different node
- **State keys don't need to be in schema** — `apply_update` accepts any key, adds new ones with last-write-wins

## Command Routing

`%LangEx.Types.Command{}` lets a node return both a state update AND a routing directive:

```elixir
alias LangEx.Types.Command

Graph.add_node(:decide, fn state ->
  if state.score > 80 do
    %Command{update: %{status: "approved"}, goto: :finalize}
  else
    %Command{update: %{status: "needs_review"}, goto: :review}
  end
end)
```

Fields:
- `update` — map of state changes
- `goto` — atom or list of atoms for next node(s)
- `resume` — value for resuming interrupted graphs

`goto: :__end__` works — it terminates the graph immediately, returning `{:ok, state}`. Useful for early exits:

```elixir
%Command{update: %{reason: "below threshold"}, goto: :__end__}
```

A node can also combine `interrupt/1` with a Command return — after the interrupt returns the resume value, the node can return a Command to route based on the human decision:

```elixir
Graph.add_node(:review, fn state ->
  decision = LangEx.Interrupt.interrupt(%{item: state.item, context: state.context})
  case decision do
    "approve" -> %Command{update: %{approved: true}, goto: :execute}
    "reject" -> %Command{update: %{approved: false}, goto: :__end__}
  end
end)
```

## Resilient LLM Wrapper

`LangEx.LLM.Resilient` wraps any provider with retry logic, backoff, and observability:

```elixir
alias LangEx.LLM.Resilient

{:ok, response} = Resilient.chat(LangEx.LLM.OpenAI, messages,
  model: "gpt-4o",
  max_retries: 3,
  retry_base_ms: 3_000,
  on_retry: fn attempt, duration_ms, wait_ms, reason ->
    Logger.warning("LLM retry #{attempt}: #{inspect(reason)}, waiting #{wait_ms}ms")
  end,
  on_success: fn attempt, duration_ms, ai, usage ->
    Logger.info("LLM success on attempt #{attempt} in #{duration_ms}ms")
  end,
  on_error: fn attempt, duration_ms, reason ->
    Logger.error("LLM failed after #{attempt} attempts: #{inspect(reason)}")
  end,
  fallback: fn -> LangEx.Message.ai("I'm having trouble connecting. Please try again.") end
)
```

Options:
- `:max_retries` — default 3
- `:retry_base_ms` — base delay, default 3000 (linear backoff: base * (attempt + 1))
- `:retryable?` — custom `fn(error) -> boolean()` (default: retries 429, 5xx, transport errors)
- `:on_success`, `:on_retry`, `:on_error` — callback hooks
- `:fallback` — `fn -> Message.AI.t()` called after all retries exhausted

`chat_with_usage/3` — same but returns `{:ok, message, %{input_tokens: N, output_tokens: N, duration_ms: N}}`

### Using Resilient Inside a Graph Node

`ChatModel.node/1` does NOT use Resilient internally. To get retries inside a graph, call `Resilient.chat/3` directly in a custom node function:

```elixir
Graph.add_node(:llm, fn state ->
  messages = state.messages

  {:ok, response} = Resilient.chat(LangEx.LLM.Anthropic, messages,
    model: "claude-sonnet-4-20250514",
    max_retries: 3,
    retry_base_ms: 3_000,
    tools: my_tools,
    fallback: fn -> Message.ai("Service temporarily unavailable.") end
  )

  %{messages: [response]}
end)
```

This replaces `ChatModel.node/1` when you need retry logic. The tradeoff is you must manually manage the messages key reading/writing.

### Return Values

```elixir
# Success:
{:ok, %Message.AI{}} = Resilient.chat(provider, messages, opts)

# With usage tracking:
{:ok, %Message.AI{}, %{input_tokens: N, output_tokens: N, duration_ms: N}} =
  Resilient.chat_with_usage(provider, messages, opts)

# Retries exhausted WITH fallback — still returns {:ok, ...}:
{:ok, fallback_message} = Resilient.chat(provider, messages, fallback: fn -> Message.ai("unavailable") end)

# Retries exhausted WITHOUT fallback — returns error:
{:error, reason} = Resilient.chat(provider, messages, max_retries: 0)
```

Resilient-specific opts (`:max_retries`, `:retry_base_ms`, `:retryable?`, `:on_success`, `:on_retry`, `:on_error`, `:fallback`) are extracted. All remaining opts are forwarded to `provider.chat/2` — this includes `:model`, `:tools`, `:temperature`, `:api_key`, `:thinking`, etc.

### Manual Tool-Call Loop Inside a Node

When you need a full tool-calling loop inside a single node (e.g., inside a `%Send{}` fan-out worker), implement it manually since the graph-level ReAct loop (`:llm` -> `:tools` -> `:llm`) isn't available:

```elixir
defp run_tool_loop(messages, tools, opts, max_rounds \\ 10) do
  {:ok, response} = LangEx.LLM.Resilient.chat(LangEx.LLM.Anthropic, messages,
    Keyword.merge([tools: tools, max_retries: 3, retry_base_ms: 3_000], opts)
  )

  if response.tool_calls === [] or max_rounds <= 0 do
    response
  else
    tool_results =
      Enum.map(response.tool_calls, fn tc ->
        tool = Enum.find(tools, &(&1.name === tc.name))
        result = if tool, do: tool.function.(tc.args), else: "Unknown tool: #{tc.name}"
        Message.tool(to_string(result), tc.id)
      end)

    run_tool_loop(messages ++ [response | tool_results], tools, opts, max_rounds - 1)
  end
end
```

Use this pattern inside fan-out workers or any custom node that needs autonomous tool calling.

## Context Compaction

`LangEx.ContextCompaction` manages message history size by replacing old tool-call rounds with summaries:

```elixir
alias LangEx.ContextCompaction

# Default: 200KB budget
messages = ContextCompaction.compact_if_needed(messages)

# Custom budget
messages = ContextCompaction.compact_if_needed(messages, max_bytes: 100_000)

# Full options
messages = ContextCompaction.compact_if_needed(messages,
  max_bytes: 200_000,
  min_rounds_to_keep: 2,
  error_detector: &my_error_detector/1,
  compaction_notice: &my_notice_formatter/1
)
```

Functions:
- `compact_if_needed/2` — returns messages unchanged if under budget, replaces oldest rounds with summaries if over
- `messages_byte_size/1` — calculate total byte size
- `default_error_detector/1` — checks for "error"/"errors" JSON keys

Use this in long-running tool-calling agents to prevent context window overflow.

## Tool Annotations

`LangEx.ToolAnnotation` inspects tool results and appends recovery guidance for the LLM:

```elixir
alias LangEx.ToolAnnotation

# Use as a post-processing step
Graph.add_node(:annotate, &ToolAnnotation.annotate/1)
```

Options:
- `:empty_threshold` — byte size below which results are "empty" (default: 200)
- `:large_threshold` — byte size above which results get a "large result" note (default: 50,000)
- `:error_detector` — custom error detection function
- `:guidance_builder` — custom guidance generation function

Functions:
- `annotate/2` — returns `%{messages: updated}` if annotations needed, `%{}` otherwise
- `latest_tool_results/1` — extract trailing tool messages
- `tool_results_substantive?/2` — check if results are meaningful

## Telemetry

LangEx emits `:telemetry.span/3` events:

| Event prefix | Metadata |
|---|---|
| `[:lang_ex, :graph, :invoke]` | `.graph_id`, `.thread_id`, `.status` |
| `[:lang_ex, :graph, :step]` | `.step`, `.active_nodes` |
| `[:lang_ex, :node, :execute]` | `.node` |
| `[:lang_ex, :llm, :chat]` | `.provider`, `.model`, `.message_count`, `.status` |
| `[:lang_ex, :checkpoint, :save]` | `.checkpointer`, `.thread_id` |
| `[:lang_ex, :checkpoint, :load]` | `.checkpointer`, `.thread_id` |

Each prefix emits `:start`, `:stop`, and `:exception` variants. **Measurements:** `system_time`, `monotonic_time`, `duration` (nanoseconds — divide by 1_000_000 for ms).

```elixir
# Attach handlers ONCE at app startup (e.g., in Application.start/2)
:telemetry.attach_many("my-app-lang-ex", [
  [:lang_ex, :graph, :invoke, :stop],
  [:lang_ex, :node, :execute, :stop],
  [:lang_ex, :llm, :chat, :stop]
], fn event_name, measurements, metadata, _config ->
  ms = div(measurements.duration, 1_000_000)
  case event_name do
    [:lang_ex, :llm, :chat, :stop] ->
      Logger.info("LLM #{metadata.provider}:#{metadata.model} took #{ms}ms")
    [:lang_ex, :node, :execute, :stop] ->
      Logger.debug("Node #{metadata.node} took #{ms}ms")
    _ -> :ok
  end
end, nil)
```

## Sequences

Chain multiple nodes in order without manually adding edges between each:

```elixir
graph
|> Graph.add_node(:fetch, &fetch_data/1)
|> Graph.add_node(:transform, &transform_data/1)
|> Graph.add_node(:store, &store_data/1)
|> Graph.add_sequence([:fetch, :transform, :store])
# Equivalent to: add_edge(:fetch, :transform) |> add_edge(:transform, :store)
```

Still need to wire `:__start__` to the first node and last node to `:__end__`.

## Anthropic-Specific Features

`LangEx.LLM.Anthropic` supports:

- **Streaming via SSE** — enabled by default, prevents TCP idle timeouts
- **Extended thinking** — `thinking: true` activates Claude's thinking mode
- **Prompt caching** — `prompt_caching: true` (default) adds `cache_control` to system prompts and tools
- **Thinking callback** — `on_thinking: fn text -> IO.write(text) end`
- **Smart max_tokens** — 64K for Sonnet, 128K otherwise

```elixir
ChatModel.node(
  model: "claude-sonnet-4-20250514",
  thinking: true,
  on_thinking: fn text -> IO.write(text) end,
  tools: tools
)
```

## Postgres Durable Workflows

For workflows that pause for hours/days (manager approvals, async reviews):

```elixir
graph =
  Graph.new(ticket: nil, approved: false)
  |> Graph.add_node(:draft, fn state ->
    %{ticket: "Escalation: #{state.ticket}"}
  end)
  |> Graph.add_node(:approve, fn state ->
    decision = LangEx.Interrupt.interrupt(state.ticket)
    %{approved: decision}
  end)
  |> Graph.add_node(:finalize, fn state -> state end)
  |> Graph.add_edge(:__start__, :draft)
  |> Graph.add_edge(:draft, :approve)
  |> Graph.add_edge(:approve, :finalize)
  |> Graph.add_edge(:finalize, :__end__)
  |> Graph.compile(checkpointer: LangEx.Checkpointer.Postgres)

config = [repo: MyApp.Repo, thread_id: "escalation-#{ticket_id}"]

# Pauses — ticket goes to manager
{:interrupt, ticket_text, _state} = LangEx.invoke(graph, %{ticket: "Server down"}, config: config)

# Hours/days later — manager approves
{:ok, result} = LangEx.invoke(graph, %LangEx.Types.Command{resume: true}, config: config)
```

Postgres is preferred over Redis for durable workflows because state survives restarts and has transactional guarantees. Use schema prefix for multi-tenant isolation.

## Full ReAct Agent

Complete agent with tools, checkpointing, streaming, resilient LLM, context compaction, and telemetry:

```elixir
defmodule MyApp.Agent do
  alias LangEx.{Graph, Message, ChatModel, Tool, ToolNode, ContextCompaction}

  @tools [
    %Tool{
      name: "search",
      description: "Search for information",
      parameters: %{
        "type" => "object",
        "properties" => %{"query" => %{"type" => "string"}},
        "required" => ["query"]
      },
      function: fn %{"query" => q} -> MyApp.Search.run(q) end
    },
    %Tool{
      name: "calculate",
      description: "Evaluate a math expression",
      parameters: %{
        "type" => "object",
        "properties" => %{"expression" => %{"type" => "string"}},
        "required" => ["expression"]
      },
      function: fn %{"expression" => expr} -> MyApp.Math.eval(expr) end
    }
  ]

  def build do
    Graph.new(LangEx.MessagesState.schema())
    |> Graph.add_node(:compact, fn state ->
      %{messages: ContextCompaction.compact_if_needed(state.messages)}
    end)
    |> Graph.add_node(:llm, ChatModel.node(
      model: "claude-sonnet-4-20250514",
      tools: @tools
    ))
    |> Graph.add_node(:tools, ToolNode.node(@tools,
      handle_tool_errors: true,
      wrap_tool_call: fn request, execute ->
        Logger.info("#{__MODULE__}: calling tool #{request.tool.name}")
        execute.(request)
      end
    ))
    |> Graph.add_edge(:__start__, :compact)
    |> Graph.add_edge(:compact, :llm)
    |> Graph.add_conditional_edges(:llm, &ToolNode.tools_condition/1, %{
      tools: :tools,
      __end__: :__end__
    })
    |> Graph.add_edge(:tools, :compact)
    |> Graph.compile(checkpointer: LangEx.Checkpointer.Redis)
  end

  def chat(thread_id, user_input) do
    graph = build()
    input = %{messages: [Message.human(user_input)]}
    config = [thread_id: thread_id]

    case LangEx.invoke(graph, input, config: config) do
      {:ok, state} -> {:ok, List.last(state.messages).content}
      {:interrupt, payload, _state} -> {:interrupt, payload}
      {:error, reason} -> {:error, reason}
    end
  end

  def stream_chat(thread_id, user_input) do
    graph = build()
    input = %{messages: [Message.human(user_input)]}

    graph
    |> LangEx.stream(input, config: [thread_id: thread_id])
    |> Stream.each(fn
      {:node_end, :llm, update} ->
        if msg = List.last(update[:messages] || []) do
          send(self(), {:ai_message, msg.content})
        end
      _ -> :ok
    end)
    |> Stream.run()
  end
end
```

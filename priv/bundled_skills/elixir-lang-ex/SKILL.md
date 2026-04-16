---
name: elixir-lang-ex
description: Use when building graph-based agent orchestration, stateful multi-step LLM workflows, AI agent pipelines, or any system using the lang_ex library (LangGraph for Elixir). Trigger whenever the user mentions lang_ex, LangEx, LangGraph, graph-based agents, agent orchestration, StateGraph, conditional routing, human-in-the-loop workflows, tool-calling agents, checkpointing agent state, or building multi-step AI workflows in Elixir. Also trigger when you see imports of LangEx.Graph, LangEx.ChatModel, LangEx.ToolNode, or LangEx.Interrupt in existing code.
---

# LangEx: Graph-Based Agent Orchestration for Elixir

LangEx (v0.4.0) is a LangGraph-inspired library built on BEAM primitives. It provides a StateGraph builder, Pregel execution engine, checkpointing, human-in-the-loop interrupts, streaming, and built-in LLM adapters (OpenAI, Anthropic, Gemini).

**Hex:** `{:lang_ex, "~> 0.4.0"}`
**Source:** github.com/surgeventures/lang_ex

For advanced patterns (subgraphs, fan-out, resilient LLM, context compaction, telemetry), read `references/advanced-patterns.md`.

## Installation

```elixir
# mix.exs
def deps do
  [
    {:lang_ex, "~> 0.4.0"},
    {:redix, "~> 1.5"},       # optional: Redis checkpointing
    {:postgrex, "~> 0.19"},   # optional: Postgres checkpointing
    {:ecto_sql, "~> 3.12"}    # optional: Postgres checkpointing
  ]
end
```

API keys resolve in order: explicit opts > `config :lang_ex` > env vars (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`).

```elixir
# config/runtime.exs
config :lang_ex, :openai, api_key: System.get_env("OPENAI_API_KEY")
config :lang_ex, :anthropic, api_key: System.get_env("ANTHROPIC_API_KEY")
config :lang_ex, redis_url: System.get_env("REDIS_URL") || "redis://localhost:6379"
```

## Core Concepts

### Graph = Nodes + Edges + State Schema

Every LangEx workflow is a directed graph compiled into an executable form:

1. **State schema** — keyword list defining keys with defaults and optional reducers
2. **Nodes** — named functions `fn state -> %{partial_update} end`
3. **Edges** — fixed (`add_edge`) or conditional (`add_conditional_edges`)
4. **Compile** — produces a `CompiledGraph` that can be invoked or streamed

Special nodes: `:__start__` (entry) and `:__end__` (terminal).

### State Reducers

Each state key can have a reducer controlling how updates merge:

```elixir
# Simple key — last-write-wins
Graph.new(count: 0, label: "")

# Key with reducer — custom merge logic
Graph.new(
  messages: {[], &LangEx.Message.add_messages/2},  # appends, replaces by ID
  total: {0, &Kernel.+/2}                           # sums values
)
```

Nodes return partial maps. The engine merges them via reducers (or last-write-wins if no reducer).

## Pattern: Simple Router

Classify input and route to different handlers:

```elixir
alias LangEx.Graph
alias LangEx.Message

graph =
  Graph.new(messages: {[], &Message.add_messages/2}, intent: nil)
  |> Graph.add_node(:classify, fn state ->
    content = List.last(state.messages).content
    intent = if String.contains?(content, "weather"), do: "weather", else: "greeting"
    %{intent: intent}
  end)
  |> Graph.add_node(:weather, fn _state ->
    %{messages: [Message.ai("It's sunny today!")]}
  end)
  |> Graph.add_node(:greet, fn _state ->
    %{messages: [Message.ai("Hello there!")]}
  end)
  |> Graph.add_edge(:__start__, :classify)
  |> Graph.add_conditional_edges(:classify, &Map.get(&1, :intent), %{
    "weather" => :weather,
    "greeting" => :greet
  })
  |> Graph.add_edge(:weather, :__end__)
  |> Graph.add_edge(:greet, :__end__)
  |> Graph.compile()

{:ok, result} = LangEx.invoke(graph, %{messages: [Message.human("What's the weather?")]})
```

## Pattern: LLM + Tool Calling Agent

The canonical ReAct-style agent loop: LLM decides whether to call tools, ToolNode executes them, loop until done.

```elixir
alias LangEx.{Graph, Message, ChatModel, Tool, ToolNode}

# 1. Define tools
tools = [
  %Tool{
    name: "search",
    description: "Search the web for current information",
    parameters: %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string", "description" => "Search query"}
      },
      "required" => ["query"]
    },
    function: fn %{"query" => query} ->
      # Your search implementation
      "Results for: #{query}"
    end
  }
]

# 2. Build graph
graph =
  Graph.new(messages: {[], &Message.add_messages/2})
  |> Graph.add_node(:llm, ChatModel.node(model: "gpt-4o", tools: tools))
  |> Graph.add_node(:tools, ToolNode.node(tools))
  |> Graph.add_edge(:__start__, :llm)
  |> Graph.add_conditional_edges(:llm, &ToolNode.tools_condition/1, %{
    tools: :tools,
    __end__: :__end__
  })
  |> Graph.add_edge(:tools, :llm)
  |> Graph.compile()

# 3. Run
{:ok, result} = LangEx.invoke(graph, %{
  messages: [Message.human("What's the latest news about Elixir?")]
})
```

Key points:
- `ChatModel.node/1` reads from `:messages` key, calls LLM, appends AI response
- `ToolNode.node/1` reads last AI message's `tool_calls`, executes in parallel, appends tool results
- `ToolNode.tools_condition/1` returns `:tools` if pending tool calls, `:__end__` otherwise
- The loop continues until the LLM responds without tool calls

## Pattern: Checkpointed Conversation (Thread Memory)

Persist state across invocations using a thread ID:

```elixir
graph =
  Graph.new(messages: {[], &Message.add_messages/2})
  |> Graph.add_node(:llm, ChatModel.node(model: "claude-sonnet-4-20250514"))
  |> Graph.add_edge(:__start__, :llm)
  |> Graph.add_edge(:llm, :__end__)
  |> Graph.compile(checkpointer: LangEx.Checkpointer.Redis)

# First turn
config = [thread_id: "user-123"]
{:ok, _} = LangEx.invoke(graph, %{messages: [Message.human("Hi, I'm Alice")]}, config: config)

# Second turn — remembers context
{:ok, result} = LangEx.invoke(graph, %{messages: [Message.human("What's my name?")]}, config: config)
```

### Redis Checkpointer

Auto-starts `LangEx.Redix` when `:redix` dep is present. Keys: `lang_ex:cp:{thread_id}:{checkpoint_id}`.

```elixir
# TTL support
config = [thread_id: "t1", ttl: 3600]

# Custom Redis connection
config = [thread_id: "t1", conn: MyApp.Redix]
```

### Postgres Checkpointer

Requires migration:

```elixir
defmodule MyApp.Repo.Migrations.AddLangEx do
  use Ecto.Migration
  def up, do: LangEx.Migration.up()
  def down, do: LangEx.Migration.down()
end
```

Usage:

```elixir
graph = Graph.new(...) |> ... |> Graph.compile(checkpointer: LangEx.Checkpointer.Postgres)
config = [repo: MyApp.Repo, thread_id: "t1"]
{:ok, result} = LangEx.invoke(graph, input, config: config)
```

Schema prefix isolation: `LangEx.Migration.up(prefix: "private")`

| Feature | Redis | Postgres |
|---------|-------|----------|
| Best for | Fast iteration, ephemeral | Durable state, transactions |
| TTL | Built-in | Manual/DB policies |
| Setup | Just add `:redix` dep | Add deps + run migration |

## Pattern: Human-in-the-Loop Interrupts

Pause execution, surface a payload, resume with human input. Requires a checkpointer.

```elixir
graph =
  Graph.new(value: 0, approved: false)
  |> Graph.add_node(:check, fn state ->
    approval = LangEx.Interrupt.interrupt("Approve value #{state.value}?")
    %{approved: approval}
  end)
  |> Graph.add_node(:finalize, fn state -> %{value: state.value * 10} end)
  |> Graph.add_edge(:__start__, :check)
  |> Graph.add_edge(:check, :finalize)
  |> Graph.add_edge(:finalize, :__end__)
  |> Graph.compile(checkpointer: LangEx.Checkpointer.Redis)

# Invoke — pauses at :check
{:interrupt, "Approve value 42?", _state} =
  LangEx.invoke(graph, %{value: 42}, config: [thread_id: "approval-1"])

# Resume with human decision
{:ok, result} =
  LangEx.invoke(graph, %LangEx.Types.Command{resume: true}, config: [thread_id: "approval-1"])
# => %{value: 420, approved: true}
```

Flow: node calls `interrupt(payload)` -> engine saves checkpoint -> returns `{:interrupt, payload, state}` -> caller gets human input -> resumes with `%Command{resume: value}` -> `interrupt/1` returns the resume value.

`interrupt/1` accepts **any term** as payload — strings, maps, structs, tuples. The resume value can also be any term. Both are serialized through the checkpointer.

Conditional interrupts — only pause when needed:

```elixir
Graph.add_node(:maybe_approve, fn state ->
  if state.needs_approval do
    approved = LangEx.Interrupt.interrupt("Please review: #{state.summary}")
    %{approved: approved}
  else
    %{approved: true}
  end
end)
```

## Pattern: Streaming Execution Events

Get a lazy stream of events for real-time UI updates:

```elixir
graph
|> LangEx.stream(%{value: 0})
|> Enum.each(fn
  {:node_start, name} -> IO.puts("Starting #{name}...")
  {:node_end, name, update} -> IO.puts("Finished #{name}: #{inspect(update)}")
  {:step_start, step, active_nodes} -> IO.puts("Step #{step}: #{inspect(active_nodes)}")
  {:step_end, step, state} -> IO.inspect(state, label: "Step #{step}")
  {:interrupt, value} -> IO.puts("Interrupted: #{inspect(value)}")
  {:done, {:ok, result}} -> IO.inspect(result, label: "Final")
  _ -> :ok
end)
```

Events: `{:node_start, name}`, `{:node_end, name, update}`, `{:step_start, step, nodes}`, `{:step_end, step, state}`, `{:interrupt, value}`, `{:done, result}`.

## Pattern: Runtime Context Injection

Pass dependencies without baking them into closures — use 2-arity node functions:

```elixir
graph =
  Graph.new(greeting: "")
  |> Graph.add_node(:greet, fn state, context ->
    %{greeting: "Hello from #{context.provider}!"}
  end)
  |> Graph.add_edge(:__start__, :greet)
  |> Graph.add_edge(:greet, :__end__)
  |> Graph.compile()

{:ok, result} = LangEx.invoke(graph, %{}, context: %{provider: "OpenAI"})
```

## MessagesState Shorthand

Pre-built schema with `messages` key and `add_messages` reducer:

```elixir
# Instead of: Graph.new(messages: {[], &Message.add_messages/2}, intent: nil)
Graph.new(LangEx.MessagesState.schema(intent: nil, response: nil))
```

## ChatModels Registry

Model strings auto-resolve to providers:

```elixir
# Built-in resolution
ChatModel.node(model: "gpt-4o")            # -> LangEx.LLM.OpenAI
ChatModel.node(model: "claude-sonnet-4-20250514")  # -> LangEx.LLM.Anthropic

# Explicit provider
ChatModel.node(provider: LangEx.LLM.OpenAI, model: "gpt-4o")

# Register custom provider
LangEx.ChatModels.register_provider(:groq, MyApp.LLM.Groq)
LangEx.ChatModels.register_prefix("llama-", :groq)
ChatModel.node(model: "llama-3.3-70b")     # -> MyApp.LLM.Groq
```

Custom provider config:

```elixir
config :lang_ex, :providers,
  groq: %{env_key: "GROQ_API_KEY", default_model: "llama-3.3-70b"}
```

## Tool Definition

Tools are provider-agnostic structs with optional embedded functions:

```elixir
%LangEx.Tool{
  name: "get_weather",
  description: "Get current weather for a city",
  parameters: %{
    "type" => "object",
    "properties" => %{
      "city" => %{"type" => "string", "description" => "City name"}
    },
    "required" => ["city"]
  },
  # Arity-1: just args
  function: fn %{"city" => city} -> WeatherAPI.get(city) end
}

# Arity-2: args + context (includes state, store, tool_call_id)
%LangEx.Tool{
  name: "lookup_user",
  description: "Look up user by ID",
  parameters: %{"type" => "object", "properties" => %{"id" => %{"type" => "string"}}, "required" => ["id"]},
  function: fn %{"id" => id}, context -> MyApp.Users.get(id, context.state.tenant) end
}
```

## ToolNode Options

```elixir
ToolNode.node(tools)
ToolNode.node(tools, messages_key: :messages)
ToolNode.node(tools, handle_tool_errors: true)           # catch errors, return as tool message
ToolNode.node(tools, handle_tool_errors: "Tool failed")  # custom error string
ToolNode.node(tools, handle_tool_errors: fn err -> "Error: #{Exception.message(err)}" end)

# Interceptor pattern — wrap tool execution
ToolNode.node(tools, wrap_tool_call: fn request, execute ->
  Logger.info("Calling tool: #{request.tool.name}")
  result = execute.(request)
  Logger.info("Tool result: #{inspect(result)}")
  result
end)
```

## Custom LLM Provider

Implement the `LangEx.LLM` behaviour:

```elixir
defmodule MyApp.LLM.Groq do
  @behaviour LangEx.LLM

  @impl true
  def chat(messages, opts) do
    # Call Groq API, return {:ok, %Message.AI{}} or {:error, reason}
    {:ok, LangEx.Message.ai("response")}
  end

  # Optional: include token usage
  @impl true
  def chat_with_usage(messages, opts) do
    {:ok, LangEx.Message.ai("response"), %{input_tokens: 100, output_tokens: 50}}
  end
end

# Register at app startup
LangEx.ChatModels.register_provider(:groq, MyApp.LLM.Groq)
LangEx.ChatModels.register_prefix("llama-", :groq)
```

## Custom Checkpointer

Implement the `LangEx.Checkpointer` behaviour:

```elixir
defmodule MyApp.Checkpointer.S3 do
  @behaviour LangEx.Checkpointer

  @impl true
  def save(config, checkpoint), do: :ok

  @impl true
  def load(config), do: {:ok, checkpoint} | :none

  @impl true
  def list(config, opts \\ []), do: [checkpoint]
end
```

## Graph Builder API Reference

```elixir
Graph.new(schema)                                    # Create graph with state schema
Graph.add_node(graph, name, fn_or_subgraph)          # Add named node
Graph.add_edge(graph, from, to)                       # Fixed edge
Graph.add_conditional_edges(graph, source, routing_fn, mapping \\ nil)
Graph.add_sequence(graph, [:a, :b, :c])              # Chain: a->b->c
Graph.compile(graph, opts)                            # Compile (opts: checkpointer: module)

LangEx.invoke(graph, input, opts)                     # Execute -> {:ok, state} | {:interrupt, payload, state} | {:error, reason}
LangEx.stream(graph, input, opts)                     # Stream -> lazy stream of events
```

## Message Types and Struct Fields

Constructors:

```elixir
Message.human("user input")              # Human message
Message.ai("response")                   # AI message
Message.system("instructions")           # System message
Message.tool("result", tool_call_id)     # Tool result message

# add_messages reducer: appends, replaces by matching ID
```

Each message type is its own struct module (all derive `Jason.Encoder`):

```elixir
# Struct types — use for pattern matching:
%LangEx.Message.Human{content: String.t(), id: String.t() | nil}
%LangEx.Message.AI{content: String.t() | nil, id: String.t() | nil, tool_calls: [ToolCall.t()]}
%LangEx.Message.System{content: String.t(), id: String.t() | nil}
%LangEx.Message.Tool{content: String.t(), tool_call_id: String.t(), id: String.t() | nil}

# ToolCall struct:
%LangEx.Message.ToolCall{name: String.t(), args: map(), id: String.t() | nil}
```

Pattern matching on message types:

```elixir
# Distinguish message types in a list
Enum.each(state.messages, fn
  %LangEx.Message.Human{content: c} -> IO.puts("User: #{c}")
  %LangEx.Message.AI{content: c, tool_calls: []} -> IO.puts("AI: #{c}")
  %LangEx.Message.AI{tool_calls: calls} -> IO.puts("AI tool calls: #{length(calls)}")
  %LangEx.Message.Tool{content: c} -> IO.puts("Tool result: #{c}")
  %LangEx.Message.System{} -> :skip
end)

# Get the last AI message specifically
last_ai = Enum.find(Enum.reverse(state.messages), &match?(%LangEx.Message.AI{}, &1))
last_ai.content     # => "Here's my analysis..."
last_ai.tool_calls  # => [%Message.ToolCall{name: "search", args: %{"q" => "..."}, id: "tc_123"}]
```

## ChatModel.node/1 Options (Complete)

```elixir
ChatModel.node(
  model: "gpt-4o",                    # Model string (auto-resolves provider)
  provider: LangEx.LLM.OpenAI,        # Explicit provider module (alternative to :model)
  messages_key: :messages,             # State key for message list (default: :messages)
  tools: [%Tool{...}],                # Tool definitions for function calling

  # All other opts are forwarded to provider.chat/2:
  api_key: "sk-...",                   # API key override
  temperature: 0.7,                    # Sampling temperature
  max_tokens: 4096,                    # Max response tokens

  # Anthropic-specific (forwarded to LangEx.LLM.Anthropic):
  thinking: true,                      # Enable extended thinking
  on_thinking: fn text -> IO.write(text) end,  # Thinking callback
  prompt_caching: true                 # Prompt caching (default: true)
)
```

**System prompts:** `ChatModel.node/1` does not accept a `:system` option. Prepend a `Message.system/1` to the messages list in a prior node or in the initial input:

```elixir
# Option A: Add system message in a setup node
|> Graph.add_node(:setup, fn _state ->
  %{messages: [Message.system("You are a helpful assistant specialized in DevOps.")]}
end)
|> Graph.add_edge(:__start__, :setup)
|> Graph.add_edge(:setup, :llm)

# Option B: Include in initial input
LangEx.invoke(graph, %{messages: [
  Message.system("You are a helpful assistant."),
  Message.human("Hello!")
]})
```

## Pattern: LLM Call Inside a Custom Node

When you need LLM output AND custom logic (routing, classification, parsing) in the same node, call the provider directly instead of using `ChatModel.node/1`:

```elixir
alias LangEx.LLM.Resilient

Graph.add_node(:classify, fn state ->
  messages = [
    Message.system("Classify the ticket urgency as: critical, high, medium, low. Reply with just the word."),
    List.last(state.messages)
  ]

  {:ok, response} = Resilient.chat(LangEx.LLM.Anthropic, messages,
    model: "claude-sonnet-4-20250514",
    max_retries: 3,
    retry_base_ms: 3_000
  )

  urgency = response.content |> String.trim() |> String.downcase()
  %{urgency: urgency}
end)
```

This pattern is useful when:
- A node needs to classify/parse LLM output and return structured state updates
- You want to combine an LLM call with a `%Command{}` for routing
- You need to call the LLM with a different tool set than what `ChatModel.node` provides

## Pattern: LLM + Command Routing (Classify-then-Route)

Combine a direct LLM call with `%Command{}` to update state AND control routing in one node:

```elixir
alias LangEx.Types.Command

Graph.add_node(:classify_and_route, fn state ->
  messages = [
    Message.system("Classify this content as: safe, flagged, or dangerous. Reply with just the word."),
    Message.human(state.content)
  ]

  {:ok, response} = LangEx.LLM.Anthropic.chat(messages, model: "claude-sonnet-4-20250514")
  classification = response.content |> String.trim() |> String.downcase()

  case classification do
    "safe" -> %Command{update: %{classification: "safe"}, goto: :auto_approve}
    "flagged" -> %Command{update: %{classification: "flagged"}, goto: :human_review}
    "dangerous" -> %Command{update: %{classification: "dangerous"}, goto: :escalate}
  end
end)
```

**`Command.goto` and edges:** When a node returns `%Command{goto: :target}`, execution routes to `:target` regardless of edges. You do NOT need `add_edge` from the Command-returning node — `goto` overrides the topology. You still need edges FROM the target nodes onward. `goto: :__end__` terminates the graph immediately, returning `{:ok, state}`.

## Conditional Edges: Routing Value Types

The routing function can return **atoms or strings** — both work. The mapping keys must match the return type:

```elixir
# String routing (recommended when values come from LLM/user input)
|> Graph.add_conditional_edges(:classify, &Map.get(&1, :intent), %{
  "weather" => :weather,
  "greeting" => :greet
})

# Atom routing (recommended for internal logic)
|> Graph.add_conditional_edges(:decide, fn state ->
  if state.score > 80, do: :approve, else: :review
end, %{
  approve: :approve_node,
  review: :review_node
})

# Remapping :__end__ — redirect terminal routing to another node
|> Graph.add_conditional_edges(:llm, &ToolNode.tools_condition/1, %{
  tools: :tools,
  __end__: :summarize    # instead of ending, go to :summarize
})
```

## ToolNode.ToolCallRequest (wrap_tool_call interceptor)

The `request` in `wrap_tool_call: fn request, execute ->` is a `%ToolCallRequest{}`:

```elixir
request.tool_call  # %Message.ToolCall{name: "search", args: %{...}, id: "tc_123"}
request.tool       # %LangEx.Tool{name: "search", ...} or nil if unregistered
request.state      # current graph state map
request.store      # persistent store or nil
```

## Common Mistakes

- Forgetting to add `:__start__` and `:__end__` edges — every graph needs an entry from `:__start__` and at least one path to `:__end__`
- Using interrupts without a checkpointer — interrupts require checkpoint persistence
- Returning full state from nodes instead of partial updates — nodes should return only changed keys
- Missing the `tools` option on `ChatModel.node/1` — without it, the LLM won't request tool calls
- Confusing `ChatModel.node/1` with `ToolNode.node/1` — ChatModel calls the LLM, ToolNode executes tool functions
- Not wiring the tool loop — after `:tools` node, edge back to `:llm` for the ReAct loop
- Passing `:system` option to `ChatModel.node/1` — it doesn't accept system prompts; prepend `Message.system/1` to the messages list instead
- Assuming `%Send{}` workers see full graph state — workers receive ONLY the `%Send{state: ...}` payload, not the parent state
- Mixing `%Send{}` with map returns — they are mutually exclusive; a node returns one or the other
- Adding `add_edge` from a `%Send{}`-returning dispatch node — unnecessary, `%Send{}` bypasses edges
- Bare-matching `{:ok, response} =` on `Resilient.chat/3` without fallback — if retries exhaust, it returns `{:error, reason}`. Use a fallback or handle both tuples

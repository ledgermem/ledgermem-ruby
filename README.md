# ledgermem

Official Ruby SDK for [LedgerMem](https://proofly.dev) — auditable memory for AI agents.

## Install

```bash
gem install ledgermem
```

Or in a `Gemfile`:

```ruby
gem "ledgermem", "~> 0.1"
```

Requires Ruby 3.0+.

## Quickstart

```ruby
require "ledgermem"

client = Ledgermem::Client.new(
  api_key: "lm_live_...",
  workspace_id: "ws_123"
)

mem = client.memories.add(content: "User prefers dark mode.")
result = client.search(query: "dark mode", limit: 5)

puts mem["id"], result["hits"].length
```

Configuration falls back to env vars: `LEDGERMEM_API_KEY`, `LEDGERMEM_WORKSPACE_ID`, `LEDGERMEM_API_URL`.

## API

| Method                     | Endpoint                  |
| -------------------------- | ------------------------- |
| `client.search`            | `POST /v1/search`         |
| `client.memories.add`      | `POST /v1/memories`       |
| `client.memories.update`   | `PATCH /v1/memories/:id`  |
| `client.memories.delete`   | `DELETE /v1/memories/:id` |
| `client.memories.list`     | `GET /v1/memories`        |

## License

MIT

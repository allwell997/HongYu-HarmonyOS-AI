# HongYu Sync Bridge

A DeepSeek Harness Host plugin that runs a local LAN HTTP bridge for the HongYu HarmonyOS app.

## What it does

- Starts `0.0.0.0:17860` (configurable through environment variables).
- Authenticates requests with a random pairing token.
- Stores synced text conversations in `~/.dsh/hongyu-sync/conversations.json`.
- Writes Markdown copies under `~/.dsh/hongyu-sync/exports/`.
- Registers the `hongyu_sync` tool:
  - `status` — show LAN URLs, port, pairing token, counts, data directory.
  - `list` — list synced conversations.
  - `read` — read one synced conversation.
  - `export_current` — export the current DSH conversation to the sync store for the phone to pull.

## Phone setup

In the HongYu app open **Settings → DSH Sync**, enter the computer's LAN IP, port `17860`, and the pairing token returned by `hongyu_sync` action `status`.

Then use **Test connection** and **Sync now**. The phone pushes its text conversations and pulls DSH-exported conversations.

## Environment overrides

| Variable | Default |
|---|---|
| `HONGYU_SYNC_HOST` | `0.0.0.0` |
| `HONGYU_SYNC_PORT` | `17860` |
| `HONGYU_SYNC_TOKEN` | generated into `token.txt` |
| `HONGYU_SYNC_DIR` | `~/.dsh/hongyu-sync` |

## Limitations

- Text-only; images/files are represented as placeholders.
- Not a native DSH Session mirror. `export_current` writes a conversation copy into the bridge store.
- No cloud relay, auth provider, or multi-user support.
- Allow TCP 17860 through the firewall and keep both devices on the same LAN.

## HTTP API

```text
GET  /health              no auth
GET  /api/info            Bearer token
GET  /api/conversations   Bearer token
POST /api/sync            Bearer token
```

`POST /api/sync` body:

```json
{
  "deviceName": "HarmonyOS phone",
  "conversations": [
    {
      "id": "conversation-id",
      "title": "Title",
      "createdAt": 1760000000000,
      "updatedAt": 1760000000000,
      "messages": [
        { "id": "m1", "role": "user", "content": "Hello", "createdAt": 1760000000000 }
      ]
    }
  ]
}
```

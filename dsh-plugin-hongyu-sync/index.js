/**
 * HongYu Sync Bridge — a DeepSeek Harness Host plugin.
 *
 * Runs a small LAN HTTP server so the HongYu HarmonyOS app can push/pull text
 * conversations, and exposes a `hongyu_sync` tool for pairing info, reading
 * synced chats, and exporting the current DSH conversation to the phone.
 */
import { createServer } from 'node:http'
import { randomBytes, timingSafeEqual } from 'node:crypto'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { homedir, networkInterfaces } from 'node:os'
import { join } from 'node:path'

const VERSION = '1.0.0'
const SERVICE = 'hongyu-sync'
const MAX_BODY_BYTES = 10 * 1024 * 1024
const MAX_CONVERSATIONS = 1000
const MAX_MESSAGES_PER_CONVERSATION = 500

const DATA_DIR = process.env.HONGYU_SYNC_DIR?.trim() || join(homedir(), '.dsh', 'hongyu-sync')
const STORE_PATH = join(DATA_DIR, 'conversations.json')
const EXPORT_DIR = join(DATA_DIR, 'exports')
const TOKEN_PATH = join(DATA_DIR, 'token.txt')
const PORT = parsePort(process.env.HONGYU_SYNC_PORT)
const HOST = process.env.HONGYU_SYNC_HOST?.trim() || '0.0.0.0'

let token = ''
let store = { version: 1, conversations: [] }
let readyPromise
let bridgeError = ''
let markdownSeq = 0
let queue = Promise.resolve()

function parsePort(raw) {
  const value = Number.parseInt(raw ?? '', 10)
  return Number.isInteger(value) && value > 0 && value < 65536 ? value : 17860
}

function log(message) {
  console.info(`[hongyu-sync] ${message}`)
}

function logError(message, error) {
  console.error(`[hongyu-sync] ${message}`, error)
}

function serialized(task) {
  const run = queue.then(task, task)
  queue = run.then(() => undefined, () => undefined)
  return run
}

async function ensureReady() {
  if (!readyPromise) {
    readyPromise = initialize()
  }
  return readyPromise
}

async function initialize() {
  await mkdir(DATA_DIR, { recursive: true })
  await mkdir(EXPORT_DIR, { recursive: true })
  token = await loadToken()
  store = await loadStore()
}

async function loadToken() {
  const fromEnv = process.env.HONGYU_SYNC_TOKEN?.trim()
  if (fromEnv) {
    return fromEnv
  }
  try {
    const existing = (await readFile(TOKEN_PATH, 'utf8')).trim()
    if (existing) {
      return existing
    }
  } catch {
    // First run.
  }
  const generated = randomBytes(18).toString('base64url')
  await writeFile(TOKEN_PATH, `${generated}\n`, { encoding: 'utf8', mode: 0o600 })
  return generated
}

async function loadStore() {
  try {
    const text = await readFile(STORE_PATH, 'utf8')
    const parsed = JSON.parse(text)
    const conversations = Array.isArray(parsed?.conversations) ? parsed.conversations : []
    return {
      version: 1,
      conversations: conversations.map(normalizeStoredConversation).filter(Boolean),
    }
  } catch (error) {
    if (error?.code !== 'ENOENT') {
      logError('Failed to load store; starting from an empty store.', error)
    }
    return { version: 1, conversations: [] }
  }
}

function normalizeStoredConversation(raw) {
  if (!raw || typeof raw.id !== 'string' || !Array.isArray(raw.messages)) {
    return null
  }
  const messages = raw.messages
    .filter((message) => message && typeof message.content === 'string')
    .map((message) => ({
      id: typeof message.id === 'string' ? message.id : makeId('message'),
      role: message.role === 'assistant' ? 'assistant' : 'user',
      content: message.content,
      createdAt: numberOr(message.createdAt, Date.now()),
    }))
  if (messages.length === 0) return null
  return {
    id: raw.id,
    title: typeof raw.title === 'string' && raw.title.trim() ? raw.title.trim() : '未命名对话',
    source: raw.source === 'dsh' ? 'dsh' : 'phone',
    createdAt: numberOr(raw.createdAt, messages[0].createdAt),
    updatedAt: numberOr(raw.updatedAt, messages[messages.length - 1].createdAt),
    messages,
  }
}

async function saveStore() {
  await writeFile(STORE_PATH, JSON.stringify(store, null, 2), 'utf8')
}

async function saveConversationMarkdown(conversation) {
  await mkdir(EXPORT_DIR, { recursive: true })
  const safe = conversation.id.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 120) || makeId('chat')
  const path = join(EXPORT_DIR, `${safe}.md`)
  await writeFile(path, renderMarkdown(conversation), 'utf8')
  return path
}

function renderMarkdown(conversation) {
  const source = conversation.source === 'dsh' ? 'DeepSeek Harness' : '鸿语手机 App'
  const lines = [
    `# ${conversation.title}`,
    '',
    `> 来源：${source} · 消息数：${conversation.messages.length} · 更新时间：${new Date(conversation.updatedAt).toISOString()}`,
    '',
  ]
  for (const message of conversation.messages) {
    lines.push(`## ${message.role === 'user' ? '用户' : '助手'}`, '', message.content, '')
  }
  return lines.join('\n')
}

function makeId(prefix) {
  return `${prefix}-${Date.now().toString(36)}-${(++markdownSeq).toString(36)}`
}

function numberOr(value, fallback) {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

function normalizeIncoming(raw) {
  if (!raw || typeof raw !== 'object' || typeof raw.id !== 'string' || raw.id.trim() === '') {
    return null
  }
  if (!Array.isArray(raw.messages)) {
    return null
  }
  const messages = []
  for (const message of raw.messages.slice(0, MAX_MESSAGES_PER_CONVERSATION)) {
    if (!message || typeof message !== 'object') continue
    if (message.role !== 'user' && message.role !== 'assistant') continue
    if (typeof message.content !== 'string') continue
    const content = message.content.trim()
    if (!content) continue
    messages.push({
      id: typeof message.id === 'string' && message.id ? message.id : makeId('message'),
      role: message.role,
      content: content.slice(0, 200000),
      createdAt: numberOr(message.createdAt, Date.now()),
    })
  }
  if (messages.length === 0) return null
  const now = Date.now()
  const title = typeof raw.title === 'string' && raw.title.trim()
    ? raw.title.trim().slice(0, 120)
    : (messages.find((message) => message.role === 'user')?.content.replace(/\s+/g, ' ').slice(0, 32) || '同步对话')
  return {
    id: raw.id.slice(0, 200),
    title,
    source: raw.source === 'dsh' ? 'dsh' : 'phone',
    createdAt: numberOr(raw.createdAt, messages[0].createdAt),
    updatedAt: numberOr(raw.updatedAt, now),
    messages,
  }
}

function mergeConversations(incoming) {
  const byId = new Map(store.conversations.map((conversation) => [conversation.id, conversation]))
  let imported = 0
  let updated = 0
  for (const conversation of incoming) {
    const existing = byId.get(conversation.id)
    if (!existing) {
      byId.set(conversation.id, conversation)
      imported += 1
    } else if (conversation.updatedAt > existing.updatedAt) {
      byId.set(conversation.id, conversation)
      updated += 1
    }
  }
  const merged = [...byId.values()]
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, MAX_CONVERSATIONS)
  store = { version: 1, conversations: merged }
  return { imported, updated, conversations: merged }
}

function authorized(req) {
  const header = req.headers.authorization
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) {
    return false
  }
  const provided = Buffer.from(header.slice('Bearer '.length))
  const expected = Buffer.from(token)
  return provided.length === expected.length && timingSafeEqual(provided, expected)
}

function sendJson(res, status, value) {
  const body = JSON.stringify(value)
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Length': Buffer.byteLength(body),
  })
  res.end(body)
}

async function readJsonBody(req) {
  const chunks = []
  let size = 0
  for await (const chunk of req) {
    size += chunk.length
    if (size > MAX_BODY_BYTES) {
      const error = new Error('Request body is too large.')
      error.status = 413
      throw error
    }
    chunks.push(chunk)
  }
  if (chunks.length === 0) return {}
  const text = Buffer.concat(chunks).toString('utf8')
  if (!text.trim()) return {}
  try {
    return JSON.parse(text)
  } catch {
    const error = new Error('Request body must be valid JSON.')
    error.status = 400
    throw error
  }
}

function lanUrls() {
  const urls = []
  const interfaces = networkInterfaces()
  for (const entries of Object.values(interfaces)) {
    for (const entry of entries ?? []) {
      if ((entry.family === 'IPv4' || entry.family === 4) && !entry.internal) {
        urls.push(`http://${entry.address}:${PORT}`)
      }
    }
  }
  return [...new Set(urls)]
}

function textOfContent(content) {
  if (typeof content === 'string') return content.trim()
  if (!Array.isArray(content)) return ''
  const parts = []
  for (const block of content) {
    if (typeof block === 'string') {
      parts.push(block)
      continue
    }
    if (!block || typeof block !== 'object') continue
    if (block.type === 'text' && typeof block.text === 'string') {
      parts.push(block.text)
    } else if (block.type === 'image' || block.type === 'image_url' ||
      block.type === 'input_image' || block.type === 'file') {
      parts.push('[图片/文件]')
    }
  }
  return parts.join('\n').trim()
}

function eventsToConversation(events, sessionId) {
  const messages = []
  let firstUser = ''
  for (const event of events) {
    if (!event || typeof event.type !== 'string') continue
    const data = event.data && typeof event.data === 'object' ? event.data : {}
    if (event.type === 'user/message') {
      const source = data.source && typeof data.source === 'object' ? data.source : undefined
      if (source && typeof source.kind === 'string' && source.kind !== 'user') continue
      const text = textOfContent(data.content)
      if (!text) continue
      if (!firstUser) firstUser = text
      messages.push({
        id: typeof data.id === 'string' && data.id ? data.id : `dsh-${event.seq}`,
        role: 'user',
        content: text,
        createdAt: numberOr(event.time, Date.now()),
      })
    } else if (event.type === 'assistant/message') {
      const content = data.message && typeof data.message === 'object' ? data.message.content : undefined
      const text = textOfContent(content)
      if (!text) continue
      messages.push({
        id: typeof data.id === 'string' && data.id ? data.id : `dsh-a-${event.seq}`,
        role: 'assistant',
        content: text,
        createdAt: numberOr(event.time, Date.now()),
      })
    }
  }
  if (messages.length === 0) {
    return null
  }
  const title = firstUser.replace(/\s+/g, ' ').slice(0, 36) || `DSH 对话 ${new Date().toLocaleString()}`
  return {
    id: `dsh_${sessionId}`,
    title,
    source: 'dsh',
    createdAt: messages[0].createdAt,
    updatedAt: Date.now(),
    messages,
  }
}

function formatStatus() {
  const urls = lanUrls()
  const lines = [
    '鸿语同步桥已启动。',
    `服务版本：${VERSION}`,
    `监听：${HOST}:${PORT}`,
    `局域网地址：${urls.length > 0 ? urls.join('、') : '未检测到局域网 IPv4 地址'}`,
    `配对码：${token}`,
    `数据目录：${DATA_DIR}`,
    `同步对话：${store.conversations.length} 个，共 ${store.conversations.reduce((sum, item) => sum + item.messages.length, 0)} 条消息`,
    '在鸿语 App → 设置 → DSH 同步中填写电脑 IP、端口和配对码。',
    '手机和电脑需要在同一 Wi-Fi；Windows 首次启动可能弹出防火墙提示，请允许专用网络访问。',
  ]
  if (bridgeError) {
    lines.push(`⚠ HTTP 服务错误：${bridgeError}`)
  }
  return lines.join('\n')
}

function formatList() {
  if (store.conversations.length === 0) {
    return '同步库为空。先在手机 App 中执行一次同步。'
  }
  const lines = [`同步库共 ${store.conversations.length} 个对话（最多显示最近 30 个）：`]
  for (const conversation of store.conversations.slice(0, 30)) {
    const source = conversation.source === 'dsh' ? 'DSH' : '手机'
    lines.push(`- [${source}] ${conversation.title}（id: ${conversation.id}，${conversation.messages.length} 条，${new Date(conversation.updatedAt).toLocaleString()}）`)
  }
  lines.push('使用 action=read 和对应 id 读取全文。')
  return lines.join('\n')
}

function formatConversation(conversation) {
  const lines = [
    `# ${conversation.title}`,
    `来源：${conversation.source === 'dsh' ? 'DeepSeek Harness' : '鸿语手机 App'}`,
    `更新时间：${new Date(conversation.updatedAt).toLocaleString()}`,
    '',
  ]
  let used = 0
  for (const message of conversation.messages) {
    const role = message.role === 'user' ? '用户' : '助手'
    const content = message.content.length > 6000 ? `${message.content.slice(0, 6000)}\n…（已截断）` : message.content
    if (used + content.length > 28000) {
      lines.push('…（内容过长，已截断，可查看同步目录中的 Markdown 文件）')
      break
    }
    lines.push(`## ${role}`, content, '')
    used += content.length
  }
  return lines.join('\n')
}

function createBridgeServer() {
  return createServer(async (req, res) => {
    try {
      if (!req.url) {
        sendJson(res, 400, { ok: false, error: 'Missing URL.' })
        return
      }
      const url = new URL(req.url, 'http://localhost')
      if (req.method === 'GET' && url.pathname === '/health') {
        sendJson(res, 200, { ok: true, service: SERVICE, version: VERSION })
        return
      }
      if (req.method === 'GET' && url.pathname === '/') {
        sendJson(res, 200, {
          ok: true,
          service: SERVICE,
          version: VERSION,
          message: 'HongYu Sync Bridge is running. Use the phone app or the hongyu_sync DSH tool.',
        })
        return
      }

      await ensureReady()
      if (!authorized(req)) {
        sendJson(res, 401, { ok: false, error: 'Invalid or missing pairing token.' })
        return
      }

      if (req.method === 'GET' && url.pathname === '/api/info') {
        sendJson(res, 200, {
          ok: true,
          service: SERVICE,
          version: VERSION,
          conversations: store.conversations.length,
          totalMessages: store.conversations.reduce((sum, item) => sum + item.messages.length, 0),
          dataDir: DATA_DIR,
        })
        return
      }

      if (req.method === 'GET' && url.pathname === '/api/conversations') {
        sendJson(res, 200, { ok: true, conversations: store.conversations })
        return
      }

      if (req.method === 'POST' && url.pathname === '/api/sync') {
        const body = await readJsonBody(req)
        const rawList = Array.isArray(body?.conversations) ? body.conversations : []
        const incoming = []
        for (const raw of rawList.slice(0, 300)) {
          const conversation = normalizeIncoming(raw)
          if (conversation) incoming.push(conversation)
        }
        const result = await serialized(async () => {
          const merged = mergeConversations(incoming)
          await saveStore()
          for (const conversation of merged.conversations) {
            if (incoming.some((item) => item.id === conversation.id)) {
              await saveConversationMarkdown(conversation)
            }
          }
          return merged
        })
        sendJson(res, 200, {
          ok: true,
          imported: result.imported,
          updated: result.updated,
          total: result.conversations.length,
          conversations: result.conversations,
        })
        return
      }

      sendJson(res, 404, { ok: false, error: 'Unknown endpoint.' })
    } catch (error) {
      logError('Request failed', error)
      sendJson(res, typeof error?.status === 'number' ? error.status : 500, {
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      })
    }
  })
}

export const name = 'dsh-plugin-hongyu-sync'
export const inject = ['tools']

export function apply(ctx) {
  ctx.effect(() => {
    const server = createBridgeServer()
    server.on('error', (error) => {
      bridgeError = error instanceof Error ? error.message : String(error)
      logError('Bridge HTTP server failed', error)
    })
    server.listen(PORT, HOST, () => {
      log(`Bridge listening on http://${HOST}:${PORT}`)
      ensureReady().catch((error) => logError('Bridge initialization failed', error))
    })
    return () => {
      try {
        server.close()
      } catch (error) {
        logError('Failed to close bridge HTTP server', error)
      }
    }
  }, 'hongyu-sync: HTTP bridge')

  ctx.effect(() => ctx.tools.register({
    name: 'hongyu_sync',
    description:
      'Manage the HongYu HarmonyOS phone sync bridge on this computer. '
      + 'Use action=status to show the LAN URL, port, pairing token and synced-chat counts; '
      + 'action=list to list synced conversations; action=read with id to read one; '
      + 'action=export_current to copy the current DSH conversation into the bridge so the phone can pull it. '
      + 'The bridge only syncs text; images are represented as placeholders.',
    parameters: {
      type: 'object',
      properties: {
        action: {
          type: 'string',
          enum: ['status', 'list', 'read', 'export_current'],
          description: 'One of: status, list, read, export_current.',
        },
        id: {
          type: 'string',
          description: 'Conversation id, required for action=read.',
        },
      },
      required: ['action'],
      additionalProperties: false,
    },
    output: {
      schema: { type: 'string' },
      render: (_args, value) => [{ type: 'text', text: String(value) }],
    },
    execute: async (args, exec) => {
      await ensureReady()
      const action = String(args?.action ?? '').trim()
      if (action === 'status') {
        return formatStatus()
      }
      if (action === 'list') {
        return formatList()
      }
      if (action === 'read') {
        const id = typeof args?.id === 'string' ? args.id : ''
        if (!id) throw new Error('action=read requires an id')
        const conversation = store.conversations.find((item) => item.id === id)
        if (!conversation) throw new Error(`No synced conversation with id "${id}"`)
        return formatConversation(conversation)
      }
      if (action === 'export_current') {
        const session = exec.agent?.session
        if (!session) throw new Error('export_current requires a calling DSH session')
        const events = typeof session.snapshotEvents === 'function'
          ? session.snapshotEvents()
          : Array.from(session.events ?? [])
        const conversation = eventsToConversation(events, session.id)
        if (!conversation) throw new Error('当前对话没有可导出的文字消息')
        const exportPath = await serialized(async () => {
          mergeConversations([conversation])
          await saveStore()
          return await saveConversationMarkdown(conversation)
        })
        return `已导出当前对话「${conversation.title}」到手机同步库，共 ${conversation.messages.length} 条消息。\nMarkdown：${exportPath}\n在手机 App 中点击「立即同步」即可拉取。`
      }
      throw new Error('Unknown action. Use status, list, read, or export_current.')
    },
  }), 'hongyu-sync: tool')
}

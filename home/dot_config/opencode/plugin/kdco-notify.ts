/**
 * notify
 * Native OS notifications for OpenCode
 *
 * Philosophy: "Notify the human when the AI needs them back, not for every micro-event."
 *
 * Features:
 * - Auto-detects terminal emulator (Ghostty, Kitty, iTerm, WezTerm, etc.)
 * - Suppresses notifications when terminal is focused (like Ghostty does)
 * - Click notification to focus terminal
 * - Parent session only by default (no spam from sub-tasks)
 *
 * Uses node-notifier which bundles native binaries:
 * - macOS: terminal-notifier (native NSUserNotificationCenter)
 * - Windows: SnoreToast (native toast notifications)
 * - Linux: notify-send (native desktop notifications)
 */

import * as fs from "node:fs/promises"
import * as os from "node:os"
import * as path from "node:path"
import type { Plugin } from "@opencode-ai/plugin"
import type { Event } from "@opencode-ai/sdk"
// @ts-expect-error - installed at runtime by OCX
import detectTerminal from "detect-terminal"
// @ts-expect-error - installed at runtime by OCX
import notifier from "node-notifier"
import type { OpencodeClient } from "./kdco-primitives/types"

interface SlackConfig {
	/** Enable Slack notifications (default: false) */
	enabled: boolean
	/** Slack incoming webhook URL */
	webhookUrl: string
}

interface NotifyConfig {
	/** Enable native OS notifications (default: true) */
	native: boolean
	/** Notify for child/sub-session events (default: false) */
	notifyChildSessions: boolean
	/** Sound configuration per event type */
	sounds: {
		idle: string
		error: string
		permission: string
		question?: string
	}
	/** Quiet hours configuration */
	quietHours: {
		enabled: boolean
		start: string // "HH:MM" format
		end: string // "HH:MM" format
	}
	/** Override terminal detection (optional) */
	terminal?: string
	/** Slack webhook configuration */
	slack?: SlackConfig
}

interface TerminalInfo {
	name: string | null
	bundleId: string | null
	processName: string | null
}

const DEFAULT_CONFIG: NotifyConfig = {
	native: true,
	notifyChildSessions: false,
	sounds: {
		idle: "Glass",
		error: "Basso",
		permission: "Submarine",
	},
	quietHours: {
		enabled: false,
		start: "22:00",
		end: "08:00",
	},
}

// Terminal name to macOS process name mapping (for focus detection)
const TERMINAL_PROCESS_NAMES: Record<string, string> = {
	ghostty: "Ghostty",
	kitty: "kitty",
	iterm: "iTerm2",
	iterm2: "iTerm2",
	wezterm: "WezTerm",
	alacritty: "Alacritty",
	terminal: "Terminal",
	apple_terminal: "Terminal",
	hyper: "Hyper",
	warp: "Warp",
	vscode: "Code",
	"vscode-insiders": "Code - Insiders",
}

// ==========================================
// CONFIGURATION
// ==========================================

async function loadConfig(): Promise<NotifyConfig> {
	const configPath = path.join(os.homedir(), ".config", "opencode", "kdco-notify.json")

	try {
		const content = await fs.readFile(configPath, "utf8")
		const userConfig = JSON.parse(content) as Partial<NotifyConfig>

		// Merge with defaults
		return {
			...DEFAULT_CONFIG,
			...userConfig,
			sounds: {
				...DEFAULT_CONFIG.sounds,
				...userConfig.sounds,
			},
			quietHours: {
				...DEFAULT_CONFIG.quietHours,
				...userConfig.quietHours,
			},
			slack: userConfig.slack,
		}
	} catch {
		// Config doesn't exist or is invalid, use defaults
		return DEFAULT_CONFIG
	}
}

// ==========================================
// TERMINAL DETECTION (macOS)
// ==========================================

async function runOsascript(script: string): Promise<string | null> {
	if (process.platform !== "darwin") return null

	try {
		const proc = Bun.spawn(["osascript", "-e", script], {
			stdout: "pipe",
			stderr: "pipe",
		})
		const output = await new Response(proc.stdout).text()
		return output.trim()
	} catch {
		return null
	}
}

async function getBundleId(appName: string): Promise<string | null> {
	return runOsascript(`id of application "${appName}"`)
}

async function getFrontmostApp(): Promise<string | null> {
	return runOsascript(
		'tell application "System Events" to get name of first application process whose frontmost is true',
	)
}

async function detectTerminalInfo(config: NotifyConfig): Promise<TerminalInfo> {
	// Use config override if provided
	const terminalName = config.terminal || detectTerminal() || null

	if (!terminalName) {
		return { name: null, bundleId: null, processName: null }
	}

	// Get process name for focus detection
	const processName = TERMINAL_PROCESS_NAMES[terminalName.toLowerCase()] || terminalName

	// Dynamically get bundle ID from macOS (no hardcoding!)
	const bundleId = await getBundleId(processName)

	return {
		name: terminalName,
		bundleId,
		processName,
	}
}

async function isTerminalFocused(terminalInfo: TerminalInfo): Promise<boolean> {
	if (!terminalInfo.processName) return false
	if (process.platform !== "darwin") return false

	const frontmost = await getFrontmostApp()
	if (!frontmost) return false

	// Case-insensitive comparison
	return frontmost.toLowerCase() === terminalInfo.processName.toLowerCase()
}

// ==========================================
// QUIET HOURS CHECK
// ==========================================

function isQuietHours(config: NotifyConfig): boolean {
	if (!config.quietHours.enabled) return false

	const now = new Date()
	const currentMinutes = now.getHours() * 60 + now.getMinutes()

	const [startHour, startMin] = config.quietHours.start.split(":").map(Number)
	const [endHour, endMin] = config.quietHours.end.split(":").map(Number)

	const startMinutes = startHour * 60 + startMin
	const endMinutes = endHour * 60 + endMin

	// Handle overnight quiet hours (e.g., 22:00 - 08:00)
	if (startMinutes > endMinutes) {
		return currentMinutes >= startMinutes || currentMinutes < endMinutes
	}

	return currentMinutes >= startMinutes && currentMinutes < endMinutes
}

// ==========================================
// PARENT SESSION DETECTION
// ==========================================

async function isParentSession(client: OpencodeClient, sessionID: string): Promise<boolean> {
	try {
		const session = await client.session.get({ path: { id: sessionID } })
		// No parentID means this IS the parent/root session
		return !session.data?.parentID
	} catch {
		// If we can't fetch, assume it's a parent to be safe (notify rather than miss)
		return true
	}
}

// ==========================================
// NOTIFICATION SENDER
// ==========================================

interface NotificationOptions {
	title: string
	message: string
	sound: string
	terminalInfo: TerminalInfo
}

function sendNotification(config: NotifyConfig, options: NotificationOptions): void {
	if (!config.native) return

	const { title, message, sound, terminalInfo } = options

	// Base notification options
	const notifyOptions: Record<string, unknown> = {
		title,
		message,
		sound,
	}

	// macOS-specific: click notification to focus terminal
	if (process.platform === "darwin" && terminalInfo.bundleId) {
		notifyOptions.activate = terminalInfo.bundleId
	}

	notifier.notify(notifyOptions)
}

// ==========================================
// SLACK NOTIFICATIONS
// ==========================================

const SLACK_EVENT_EMOJI: Record<string, string> = {
	idle: ":white_check_mark:",
	error: ":rotating_light:",
	permission: ":raised_hand:",
	question: ":question:",
}

const SLACK_EVENT_COLOR: Record<string, string> = {
	idle: "#36a64f",
	error: "#cc0000",
	permission: "#ff9900",
	question: "#3399ff",
}

async function sendSlackNotification(
	config: NotifyConfig,
	eventType: string,
	title: string,
	message: string,
): Promise<void> {
	if (!config.slack?.enabled || !config.slack?.webhookUrl) return

	const emoji = SLACK_EVENT_EMOJI[eventType] || ":bell:"
	const color = SLACK_EVENT_COLOR[eventType] || "#808080"

	const payload = {
		attachments: [
			{
				color,
				blocks: [
					{
						type: "section",
						text: {
							type: "mrkdwn",
							text: `${emoji} *${title}*\n${message}`,
						},
					},
				],
				fallback: `${title}: ${message}`,
			},
		],
	}

	try {
		await fetch(config.slack.webhookUrl, {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify(payload),
		})
	} catch {
		// Silently fail - don't let Slack issues break native notifications
	}
}

// ==========================================
// EVENT HANDLERS
// ==========================================

async function handleSessionIdle(
	client: OpencodeClient,
	sessionID: string,
	config: NotifyConfig,
	terminalInfo: TerminalInfo,
): Promise<void> {
	// Check if we should notify for this session
	if (!config.notifyChildSessions) {
		const isParent = await isParentSession(client, sessionID)
		if (!isParent) return
	}

	// Check quiet hours
	if (isQuietHours(config)) return

	// Check if terminal is focused (suppress notification if user is already looking)
	if (await isTerminalFocused(terminalInfo)) return

	// Get session info for context
	let sessionTitle = "Task"
	try {
		const session = await client.session.get({ path: { id: sessionID } })
		if (session.data?.title) {
			sessionTitle = session.data.title.slice(0, 50)
		}
	} catch {
		// Use default title
	}

	sendNotification(config, {
		title: "Ready for review",
		message: sessionTitle,
		sound: config.sounds.idle,
		terminalInfo,
	})
	await sendSlackNotification(config, "idle", "Ready for review", sessionTitle)
}

async function handleSessionError(
	client: OpencodeClient,
	sessionID: string,
	error: string | undefined,
	config: NotifyConfig,
	terminalInfo: TerminalInfo,
): Promise<void> {
	// Check if we should notify for this session
	if (!config.notifyChildSessions) {
		const isParent = await isParentSession(client, sessionID)
		if (!isParent) return
	}

	// Check quiet hours
	if (isQuietHours(config)) return

	// Check if terminal is focused (suppress notification if user is already looking)
	if (await isTerminalFocused(terminalInfo)) return

	const errorMessage = error?.slice(0, 100) || "Something went wrong"

	sendNotification(config, {
		title: "Something went wrong",
		message: errorMessage,
		sound: config.sounds.error,
		terminalInfo,
	})
	await sendSlackNotification(config, "error", "Something went wrong", errorMessage)
}

async function handlePermissionUpdated(
	config: NotifyConfig,
	terminalInfo: TerminalInfo,
): Promise<void> {
	// Always notify for permission events - AI is blocked waiting for human
	// No parent check needed: permissions always need human attention

	// Check quiet hours
	if (isQuietHours(config)) return

	// Check if terminal is focused (suppress notification if user is already looking)
	if (await isTerminalFocused(terminalInfo)) return

	sendNotification(config, {
		title: "Waiting for you",
		message: "OpenCode needs your input",
		sound: config.sounds.permission,
		terminalInfo,
	})
	await sendSlackNotification(config, "permission", "Waiting for you", "OpenCode needs your input")
}

async function handleQuestionAsked(
	config: NotifyConfig,
	terminalInfo: TerminalInfo,
): Promise<void> {
	// Guard: quiet hours only (no focus check for questions - tmux workflow)
	if (isQuietHours(config)) return

	const sound = config.sounds.question ?? config.sounds.permission

	sendNotification(config, {
		title: "Question for you",
		message: "OpenCode needs your input",
		sound,
		terminalInfo,
	})
	await sendSlackNotification(config, "question", "Question for you", "OpenCode needs your input")
}

// ==========================================
// PLUGIN EXPORT
// ==========================================

export const NotifyPlugin: Plugin = async (ctx) => {
	const { client } = ctx

	// Load config once at startup
	const config = await loadConfig()

	// Detect terminal once at startup (cached for performance)
	const terminalInfo = await detectTerminalInfo(config)

	return {
		"tool.execute.before": async (input: { tool: string; sessionID: string; callID: string }) => {
			if (input.tool === "question") {
				await handleQuestionAsked(config, terminalInfo)
			}
		},
		event: async ({ event }: { event: Event }): Promise<void> => {
			switch (event.type) {
				case "session.idle": {
					const sessionID = event.properties.sessionID
					if (sessionID) {
						await handleSessionIdle(client as OpencodeClient, sessionID, config, terminalInfo)
					}
					break
				}
				case "session.error": {
					const sessionID = event.properties.sessionID
					const error = event.properties.error
					const errorMessage = typeof error === "string" ? error : error ? String(error) : undefined
					if (sessionID) {
						await handleSessionError(
							client as OpencodeClient,
							sessionID,
							errorMessage,
							config,
							terminalInfo,
						)
					}
					break
				}

				case "permission.updated": {
					await handlePermissionUpdated(config, terminalInfo)
					break
				}
			}
		},
	}
}

export default NotifyPlugin

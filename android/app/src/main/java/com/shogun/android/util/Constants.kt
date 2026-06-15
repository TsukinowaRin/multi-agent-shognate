package com.shogun.android.util

/** SharedPreferences keys — single source of truth to prevent typo bugs. */
object PrefsKeys {
    const val PREFS_NAME = "shogun_prefs"
    const val SSH_HOST = "ssh_host"
    const val SSH_PORT = "ssh_port"
    const val SSH_USER = "ssh_user"
    const val SSH_KEY_PATH = "ssh_key_path"
    const val SSH_PASSWORD = "ssh_password"
    const val LAST_WIRELESS_HOST = "last_wireless_host"
    const val LAST_WIRELESS_PORT = "last_wireless_port"
    const val PROJECT_PATH = "project_path"
    const val SHOGUN_SESSION = "shogun_session"
    const val AGENTS_SESSION = "agents_session"
    const val NOTIFICATION_ENABLED = "notification_enabled"
    const val NTFY_TOPIC = "ntfy_topic"
    const val NOTIFY_CMD_COMPLETE = "notify_cmd_complete"
    const val NOTIFY_CMD_FAILURE = "notify_cmd_failure"
    const val NOTIFY_ACTION_REQUIRED = "notify_action_required"
    const val NOTIFY_DASHBOARD_UPDATE = "notify_dashboard_update"
    const val NOTIFY_STREAK_UPDATE = "notify_streak_update"
    const val NOTIFY_AGENT_RESPONSE = "notify_agent_response"
}

object Defaults {
    const val USB_SSH_HOST = "127.0.0.1"
    const val USB_SSH_PORT = 2222
    const val USB_SSH_PORT_STR = "2222"
    const val WIRELESS_SSH_PORT = 22
    const val WIRELESS_SSH_PORT_STR = "22"
    const val PAIRING_PORT = 8765
    const val PAIRING_PORT_STR = "8765"
    const val SSH_HOST = USB_SSH_HOST
    const val SSH_PORT = USB_SSH_PORT
    const val SSH_PORT_STR = USB_SSH_PORT_STR
    const val SHOGUN_SESSION = "agent:shogun"
    const val AGENTS_SESSION = "shogunate:goza"
    const val NTFY_TOPIC = "sho-y0uhey"
    const val TMUX = "/usr/bin/tmux"

    fun resolveShogunTarget(value: String): String {
        return resolveTarget(value, SHOGUN_SESSION, "main")
    }

    fun resolveAgentsTarget(value: String): String {
        return resolveTarget(value, AGENTS_SESSION, "0")
    }

    fun shogunTargetAssignment(value: String): String {
        return targetAssignment(resolveShogunTarget(value))
    }

    fun agentsTargetAssignment(value: String): String {
        return targetAssignment(resolveAgentsTarget(value))
    }

    fun shogunTargetExistsCommand(value: String): String {
        return targetExistsCommand(resolveShogunTarget(value))
    }

    fun agentsTargetExistsCommand(value: String): String {
        return targetExistsCommand(resolveAgentsTarget(value))
    }

    fun shellQuote(value: String): String = "'" + value.replace("'", "'\\''") + "'"

    private fun resolveTarget(value: String, blankDefault: String, legacyWindow: String): String {
        val trimmed = value.trim()
        if (trimmed.isBlank()) return blankDefault
        return if (trimmed.startsWith("agent:") || trimmed.contains(":") || trimmed.contains(".")) {
            trimmed
        } else {
            "$trimmed:$legacyWindow"
        }
    }

    private fun targetAssignment(resolvedTarget: String): String {
        if (!resolvedTarget.startsWith("agent:")) {
            return "target=${shellQuote(resolvedTarget)}"
        }
        val agentId = resolvedTarget.removePrefix("agent:").trim()
        return "target=\$($TMUX list-panes -a -F '#{pane_id} #{@agent_id}' 2>/dev/null | awk -v agent=${shellQuote(agentId)} '\$2 == agent {print \$1; exit}')"
    }

    private fun targetExistsCommand(resolvedTarget: String): String {
        return "${targetAssignment(resolvedTarget)}; [ -n \"\$target\" ] && $TMUX list-panes -t \"\$target\" >/dev/null 2>&1"
    }
}

package com.shogun.android.ui

import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.util.Locale

fun roleDisplayName(id: String): String {
    val raw = id.trim()
    val normalized = raw.lowercase(Locale.ROOT)
    return when {
        normalized == "shogun" -> "将軍"
        normalized == "karo" -> "家老"
        normalized.matches(Regex("""karo\d+""")) -> "家老${normalized.removePrefix("karo")}"
        normalized == "gunshi" -> "軍師"
        normalized == "gunkan" -> "軍監"
        normalized.matches(Regex("""ashigaru\d+""")) -> "足軽${normalized.removePrefix("ashigaru")}号"
        else -> raw
    }
}

fun transcriptTimeLabel(time: String): String {
    val value = time.trim()
    if (value.isBlank()) return ""
    val localTime = runCatching { OffsetDateTime.parse(value).toLocalTime() }
        .getOrElse {
            runCatching { LocalDateTime.parse(value).toLocalTime() }.getOrNull() ?: return ""
        }
    return "%02d:%02d".format(Locale.ROOT, localTime.hour, localTime.minute)
}

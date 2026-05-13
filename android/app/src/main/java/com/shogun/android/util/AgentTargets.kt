package com.shogun.android.util

data class AgentTarget(
    val id: String,
    val label: String,
    val modelName: String = "",
    val cliName: String = ""
)

object AgentTargets {
    val default = AgentTarget("shogun", "将軍")

    fun parseBridgeList(output: String): List<AgentTarget> {
        val parsed = output
            .lineSequence()
            .mapNotNull { line ->
                val cols = line.split('\t')
                val id = cols.getOrNull(0)?.trim().orEmpty()
                if (id.isBlank()) return@mapNotNull null
                AgentTarget(
                    id = id,
                    label = displayLabel(id),
                    modelName = cols.getOrNull(1)?.trim().orEmpty(),
                    cliName = cols.getOrNull(2)?.trim().orEmpty()
                )
            }
            .distinctBy { it.id }
            .sortedWith(compareBy<AgentTarget> { sortBucket(it.id) }.thenBy { sortNumber(it.id) }.thenBy { it.id })
            .toList()
        return parsed.ifEmpty { listOf(default) }
    }

    fun displayLabel(agentId: String): String = when {
        agentId == "shogun" -> "将軍"
        agentId == "gunshi" -> "軍師"
        agentId == "karo" -> "家老"
        agentId.matches(Regex("""karo\d+""")) -> "家老${agentId.removePrefix("karo")}"
        agentId.matches(Regex("""ashigaru\d+""")) -> "足軽${agentId.removePrefix("ashigaru")}"
        else -> agentId
    }

    private fun sortBucket(agentId: String): Int = when {
        agentId == "shogun" -> 0
        agentId == "karo" || agentId.startsWith("karo") -> 1
        agentId == "gunshi" -> 2
        agentId.startsWith("ashigaru") -> 3
        else -> 9
    }

    private fun sortNumber(agentId: String): Int {
        val digits = agentId.takeLastWhile { it.isDigit() }
        return digits.toIntOrNull() ?: 0
    }
}

package com.shogun.android.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AgentTargetsTest {
    @Test
    fun `bridge list is sorted by shogunate role order`() {
        val output = listOf(
            "ashigaru2\tOpenCode\topencode",
            "gunshi\tCodex\tcodex",
            "shogun\tCodex\tcodex",
            "karo2\tClaude\tclaude",
            "ashigaru1\tGemini\tgemini",
            "karo1\tCodex\tcodex"
        ).joinToString("\n")

        val targets = AgentTargets.parseBridgeList(output)

        assertEquals(listOf("shogun", "karo1", "karo2", "gunshi", "ashigaru1", "ashigaru2"), targets.map { it.id })
        assertEquals("将軍", targets[0].label)
        assertEquals("家老2", targets[2].label)
        assertEquals("足軽1", targets[4].label)
    }

    @Test
    fun `empty bridge list falls back to shogun`() {
        val targets = AgentTargets.parseBridgeList("")

        assertEquals(1, targets.size)
        assertEquals("shogun", targets[0].id)
    }

    @Test
    fun `connection profile parses generated json`() {
        val profile = ConnectionProfiles.parse(
            """
            {
              "type": "shogunate-android-connection-profile",
              "mode": "tailscale",
              "host": "100.64.1.2",
              "port": "22",
              "user": "muro",
              "projectPath": "/mnt/d/git_workspace/multi-agent-shognate/multi-agent-shognate",
              "shogunSession": "shogun",
              "agentsSession": "multiagent"
            }
            """.trimIndent()
        )

        assertEquals("100.64.1.2", profile?.host)
        assertEquals("22", profile?.port)
        assertEquals("muro", profile?.user)
        assertEquals("multiagent", profile?.agentsSession)
    }

    @Test
    fun `connection profile rejects missing required fields`() {
        assertNull(ConnectionProfiles.parse("""{"host":"127.0.0.1"}"""))
    }

    @Test
    fun `connection profile parses deep link`() {
        val profile = ConnectionProfiles.parse(
            "shogunate://connect?host=100.64.1.2&port=22&user=muro&projectPath=%2Frepo%2Fmulti-agent-shognate&shogunSession=shogun&agentsSession=multiagent"
        )

        assertEquals("100.64.1.2", profile?.host)
        assertEquals("22", profile?.port)
        assertEquals("muro", profile?.user)
        assertEquals("/repo/multi-agent-shognate", profile?.projectPath)
    }
}

package com.shogun.android.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class ShogunateCampProfileTest {
    @Test
    fun stableIdDependsOnConnectionAndProject() {
        val first = ShogunateCampProfile.stableId("pc", "2223", "muro", "/work/a")
        val second = ShogunateCampProfile.stableId("pc", "2223", "muro", "/work/b")

        assertNotEquals(first, second)
    }

    @Test
    fun createTrimsFieldsAndKeepsTargets() {
        val profile = ShogunateCampProfile.create(
            name = " 開発陣 ",
            host = " 100.71.16.5 ",
            port = " 2223 ",
            user = " muro ",
            keyPath = " /keys/app ",
            password = "",
            projectPath = " /work/project ",
            shogunTarget = "agent:shogun",
            agentsTarget = "shogunate-project:goza"
        )

        assertEquals("開発陣", profile.displayName)
        assertEquals("100.71.16.5", profile.host)
        assertEquals("2223", profile.port)
        assertEquals("muro", profile.user)
        assertEquals("/keys/app", profile.keyPath)
        assertEquals("/work/project", profile.projectPath)
        assertEquals("agent:shogun", profile.shogunTarget)
        assertEquals("shogunate-project:goza", profile.agentsTarget)
    }
}

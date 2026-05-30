package com.shogun.android.util

import org.junit.Assert.assertEquals
import org.junit.Test

class DefaultsTest {
    @Test
    fun resolveShogunTargetAcceptsFullTmuxTarget() {
        assertEquals("shogunate:goza", Defaults.resolveShogunTarget("shogunate:goza"))
    }

    @Test
    fun resolveShogunTargetKeepsLegacySessionNameBehavior() {
        assertEquals("shogun:main", Defaults.resolveShogunTarget("shogun"))
    }

    @Test
    fun resolveAgentsTargetAcceptsFullTmuxTarget() {
        assertEquals("shogunate:goza", Defaults.resolveAgentsTarget("shogunate:goza"))
    }

    @Test
    fun resolveAgentsTargetKeepsLegacySessionNameBehavior() {
        assertEquals("multiagent:0", Defaults.resolveAgentsTarget("multiagent"))
    }
}

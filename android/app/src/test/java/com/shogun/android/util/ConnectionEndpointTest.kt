package com.shogun.android.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class ConnectionEndpointTest {
    @Test
    fun acceptsDnsName() {
        val endpoint = normalizeConnectionEndpoint("pc.tailnet.ts.net")

        assertEquals("pc.tailnet.ts.net", endpoint.host)
        assertNull(endpoint.port)
    }

    @Test
    fun acceptsHostPort() {
        val endpoint = normalizeConnectionEndpoint("pc.tailnet.ts.net:2223")

        assertEquals("pc.tailnet.ts.net", endpoint.host)
        assertEquals("2223", endpoint.port)
    }

    @Test
    fun acceptsHttpsUrlAndIgnoresPath() {
        val endpoint = normalizeConnectionEndpoint("https://example.com:2223/shogunate/setup")

        assertEquals("example.com", endpoint.host)
        assertEquals("2223", endpoint.port)
    }

    @Test
    fun acceptsSshUrlWithUser() {
        val endpoint = normalizeConnectionEndpoint("ssh://muro@example.com:22/mnt/d/project")

        assertEquals("example.com", endpoint.host)
        assertEquals("22", endpoint.port)
    }

    @Test
    fun acceptsIpAddress() {
        val endpoint = normalizeConnectionEndpoint("100.71.16.5")

        assertEquals("100.71.16.5", endpoint.host)
        assertNull(endpoint.port)
    }

    @Test
    fun rejectsBlankInput() {
        assertThrows(IllegalArgumentException::class.java) {
            normalizeConnectionEndpoint("   ")
        }
    }
}

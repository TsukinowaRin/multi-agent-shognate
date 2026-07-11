package com.shogun.android.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class RoleNamesTest {
    @Test
    fun roleDisplayNameMapsKnownRolesToJapanese() {
        assertEquals("将軍", roleDisplayName("shogun"))
        assertEquals("家老", roleDisplayName("karo"))
        assertEquals("家老2", roleDisplayName("karo2"))
        assertEquals("軍師", roleDisplayName("gunshi"))
        assertEquals("軍監", roleDisplayName("gunkan"))
        assertEquals("足軽7号", roleDisplayName("ashigaru7"))
    }

    @Test
    fun roleDisplayNameKeepsUnknownIds() {
        assertEquals("observer", roleDisplayName("observer"))
        assertEquals("", roleDisplayName(" "))
    }

    @Test
    fun transcriptTimeLabelExtractsHourAndMinuteFromIsoTime() {
        assertEquals("09:05", transcriptTimeLabel("2026-07-11T09:05:33Z"))
        assertEquals("23:41", transcriptTimeLabel("2026-07-11T23:41:03+09:00"))
        assertEquals("01:02", transcriptTimeLabel("2026-07-11T01:02:03"))
    }

    @Test
    fun transcriptTimeLabelReturnsBlankForInvalidInput() {
        assertEquals("", transcriptTimeLabel(""))
        assertEquals("", transcriptTimeLabel("not a timestamp"))
        assertEquals("", transcriptTimeLabel("2026-07-11 09:05:33"))
    }
}

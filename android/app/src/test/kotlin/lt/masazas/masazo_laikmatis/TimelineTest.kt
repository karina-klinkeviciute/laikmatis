package lt.masazas.masazo_laikmatis

import org.junit.Assert.*
import org.junit.Test

class TimelineTest {
    @Test fun allPresetsAnnounceAtTheirIntervalAndFinishOnce() {
        for (preset in Timeline.PRESETS) {
            val timer = Timeline()
            timer.start(preset, 1000)
            assertNull(timer.tick(1000 + timer.interval - 1))
            assertEquals(timer.duration - timer.interval, timer.tick(1000 + timer.interval))
            assertNull(timer.tick(1000 + timer.interval + 1))
            assertEquals(0L, timer.tick(1000 + timer.duration))
            assertEquals("finished", timer.phase)
            assertNull(timer.tick(2000 + timer.duration))
        }
    }
    @Test fun pauseDoesNotConsumeTimeAndResumeKeepsIntervalPosition() {
        val timer = Timeline()
        timer.start("left_one", 0)
        timer.pause(30000)
        assertEquals(1770000L, timer.remaining(500000))
        timer.resume(500000)
        assertNull(timer.tick(529999))
        assertEquals(1740000L, timer.tick(530000))
    }
    @Test fun aDelayedTickSkipsStaleMessages() {
        val timer = Timeline()
        timer.start("right_one", 0)
        assertEquals(3415000L, timer.tick(185000))
        assertNull(timer.tick(185100))
        assertEquals(3360000L, timer.tick(240000))
    }
    @Test fun stopPreventsCompletionAndCanStartAnotherPreset() {
        val timer = Timeline()
        timer.start("left_one", 0); timer.stop()
        assertNull(timer.tick(3600000))
        timer.start("right_two", 3600000)
        assertEquals(3600000L, timer.remaining(3600000))
        assertEquals(300000L, timer.interval)
    }
    @Test fun grammarIncludesLithuanianExceptions() {
        assertEquals("Liko 1 minutė", minutePhrase(1))
        assertEquals("Liko 2 minutės", minutePhrase(2))
        assertEquals("Liko 11 minučių", minutePhrase(11))
        assertEquals("Liko 21 minutė", minutePhrase(21))
        assertEquals("Liko 30 minučių", minutePhrase(30))
    }
}

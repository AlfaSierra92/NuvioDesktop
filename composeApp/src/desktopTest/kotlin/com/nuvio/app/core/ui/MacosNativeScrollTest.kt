package com.nuvio.app.core.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performMouseInput
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.nuvio.app.features.player.desktop.DesktopHostOs
import kotlin.test.Test
import kotlin.test.assertEquals

@OptIn(ExperimentalTestApi::class)
class MacosNativeScrollTest {
    @Test
    fun `home smooth scrolling setting preserves native macOS precision deltas`() {
        if (DesktopHostOs.current != DesktopHostOs.MACOS) return
        runComposeUiTest {
            val home = LazyListState(firstVisibleItemIndex = 10)
            val native = LazyListState(firstVisibleItemIndex = 10)
            setContent {
                Column {
                    LazyColumn(
                        state = home,
                        modifier = Modifier.height(200.dp).fillMaxWidth().testTag("home")
                            .smoothVerticalWheelScroll(home, enabled = true),
                    ) {
                        items(200) { Box(Modifier.fillMaxWidth().height(40.dp)) }
                    }
                    LazyColumn(
                        state = native,
                        modifier = Modifier.height(200.dp).fillMaxWidth().testTag("native"),
                    ) {
                        items(200) { Box(Modifier.fillMaxWidth().height(40.dp)) }
                    }
                }
            }
            for (delta in listOf(0.25f, 0.5f, -0.25f, -0.5f)) {
                onNodeWithTag("home").performMouseInput {
                    moveTo(center)
                    advanceEventTime(500)
                    scroll(delta)
                }
                waitForIdle()
                onNodeWithTag("native").performMouseInput {
                    moveTo(center)
                    advanceEventTime(500)
                    scroll(delta)
                }
                waitForIdle()
                runOnIdle {
                    assertEquals(native.firstVisibleItemIndex, home.firstVisibleItemIndex)
                    assertEquals(native.firstVisibleItemScrollOffset, home.firstVisibleItemScrollOffset)
                }
            }
        }
    }
}

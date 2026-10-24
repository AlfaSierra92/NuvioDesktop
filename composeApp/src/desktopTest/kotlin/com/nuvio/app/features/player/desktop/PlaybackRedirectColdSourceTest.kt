package com.nuvio.app.features.player.desktop

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class PlaybackRedirectColdSourceTest {
    @Test
    fun `temporary preparation failures retry automatically and open only the final media link`() = runBlocking {
        MockWebServer().use { server ->
            repeat(2) { server.enqueue(MockResponse().setResponseCode(503)) }
            server.enqueue(MockResponse().setResponseCode(307)
                .addHeader("Location", "https://media.example.test/ready.mkv"))
            server.start()
            val source = server.url("/api/v1/debrid/playback/preparing").toString()

            val result = PlaybackRedirectResolver.resolveForPlayback(source, emptyMap())

            assertEquals(3, server.requestCount)
            assertEquals(PlaybackRedirectResolution.Outcome.Pinned, result.outcome)
            assertEquals("https://media.example.test/ready.mkv", result.playbackUrl)
            assertTrue(PlaybackRedirectResolver.canOpenPlaybackUrl(source, result.playbackUrl))
        }
    }

    @Test
    fun `exhausted automatic retries never allow the original resolver URL to open`() = runBlocking {
        MockWebServer().use { server ->
            repeat(3) { server.enqueue(MockResponse().setResponseCode(504)) }
            server.start()
            val source = server.url("/api/v1/debrid/playback/unavailable").toString()

            val result = PlaybackRedirectResolver.resolveForPlayback(source, emptyMap())

            assertEquals(3, server.requestCount)
            assertEquals(PlaybackRedirectResolution.Outcome.Failed, result.outcome)
            assertFalse(PlaybackRedirectResolver.canOpenPlaybackUrl(source, result.playbackUrl))
            assertFalse(PlaybackRedirectResolver.canOpenPlaybackUrl(source, ""))
            assertFalse(PlaybackRedirectResolver.canOpenPlaybackUrl(source, "https://other.example/api/v1/usenet/play"))
            assertFalse(PlaybackRedirectResolver.canOpenPlaybackUrl(source, "https://other.example/static/downloading.mp4"))
        }
    }

    @Test
    fun `authentication and rate limit errors do not trigger blind retries`() = runBlocking {
        for (status in listOf(401, 403, 429)) {
            MockWebServer().use { server ->
                server.enqueue(MockResponse().setResponseCode(status))
                server.start()
                val source = server.url("/api/v1/debrid/playback/refused").toString()
                val result = PlaybackRedirectResolver.resolveForPlayback(source, emptyMap())
                assertEquals(1, server.requestCount)
                assertEquals(status, result.httpErrorStatus)
                assertFalse(PlaybackRedirectResolver.canOpenPlaybackUrl(source, result.playbackUrl))
            }
        }
    }

    @Test
    fun `cacheable dynamic redirects still open the direct media URL`() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(307)
                .addHeader("Location", "https://media.example.test/episode.mkv")
                .addHeader("Cache-Control", "max-age=600"))
            server.start()
            val source = server.url("/api/v1/debrid/playback/cacheable").toString()
            val result = PlaybackRedirectResolver.resolveForPlayback(source, emptyMap())
            assertEquals(PlaybackRedirectResolution.Outcome.Pinned, result.outcome)
            assertTrue(PlaybackRedirectResolver.canOpenPlaybackUrl(source, result.playbackUrl))
        }
    }

    @Test
    fun `a previous nonredirect response cannot bypass resolution on the next play`() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("preparing"))
            server.enqueue(MockResponse().setResponseCode(307)
                .addHeader("Location", "https://media.example.test/episode.mkv"))
            server.start()
            val source = server.url("/api/v1/debrid/playback/changed").toString()
            val first = PlaybackRedirectResolver.resolveForPlayback(source, emptyMap())
            assertFalse(PlaybackRedirectResolver.canOpenPlaybackUrl(source, first.playbackUrl))
            val second = PlaybackRedirectResolver.resolveForPlayback(source, emptyMap())
            assertTrue(PlaybackRedirectResolver.canOpenPlaybackUrl(source, second.playbackUrl))
            assertEquals(2, server.requestCount)
        }
    }

    @Test
    fun `leaving playback interrupts a pending resolver request without waiting for its timeout`() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            server.start()
            val source = server.url("/api/v1/debrid/playback/cancelled").toString()
            val job = launch { PlaybackRedirectResolver.resolveForPlayback(source, emptyMap()) }
            // Let the IO coroutine reach the server without blocking this event loop.
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                assertNotNull(server.takeRequest(3, TimeUnit.SECONDS))
            }
            withTimeout(2_000) { job.cancelAndJoin() }
            assertEquals(1, server.requestCount)
        }
    }

    @Test
    fun `cold playback redirect can take longer than the ordinary probe budget`() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(
                MockResponse().setResponseCode(307)
                    .addHeader("Location", "https://media.example.test/episode.mkv")
                    .addHeader("Cache-Control", "no-store")
                    .setHeadersDelay(5, TimeUnit.SECONDS),
            )
            server.start()
            val source = server.url("/api/v1/debrid/playback/cold-file").toString()

            val resolution = PlaybackRedirectResolver.resolve(source, emptyMap(), forceProbe = true)

            assertEquals(PlaybackRedirectResolution.Outcome.Pinned, resolution.outcome)
            assertEquals("https://media.example.test/episode.mkv", resolution.playbackUrl)
            assertEquals(1, server.requestCount)
            assertEquals("bytes=0-0", server.takeRequest().getHeader("Range"))
        }
    }

    @Test
    fun `transient playback preparation failure does not disable pinning for the next play`() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(503))
            server.enqueue(
                MockResponse().setResponseCode(307)
                    .addHeader("Location", "https://media.example.test/ready.mkv")
                    .addHeader("Cache-Control", "no-store"),
            )
            server.start()
            val source = server.url("/api/v1/usenet/cold-file").toString()

            assertEquals(
                PlaybackRedirectResolution.Outcome.Failed,
                PlaybackRedirectResolver.resolve(source, emptyMap(), forceProbe = true).outcome,
            )
            val retry = PlaybackRedirectResolver.resolve(source, emptyMap())

            assertEquals(PlaybackRedirectResolution.Outcome.Pinned, retry.outcome)
            assertEquals("https://media.example.test/ready.mkv", retry.playbackUrl)
            assertEquals(2, server.requestCount)
        }
    }
}

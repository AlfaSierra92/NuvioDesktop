package com.nuvio.app.features.player.desktop

import java.io.File
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assume.assumeTrue
import kotlin.test.Test
import kotlin.test.assertTrue

/** Opt-in real endpoint probe. Supply private URL/headers through a JSON file, never CLI arguments. */
class PlaybackWebDavIntegrationTest {
    @Test
    fun resolveConfiguredWebDavStream(): Unit = runBlocking {
        val configPath = System.getenv("NUVIO_WEBDAV_TEST_CONFIG")
        assumeTrue("No real WebDAV test configuration supplied", !configPath.isNullOrBlank())
        val config = Json.parseToJsonElement(File(configPath!!).readText()).jsonObject
        val url = config.getValue("url").jsonPrimitive.content
        val headers = config["headers"]?.jsonObject?.mapValues { it.value.jsonPrimitive.content }.orEmpty()
        val started = System.nanoTime()
        val resolution = PlaybackRedirectResolver.resolve(url, headers, forceProbe = true)
        val elapsedMs = (System.nanoTime() - started) / 1_000_000
        println("WebDAV real probe: outcome=${resolution.outcome} hops=${resolution.hops} elapsedMs=$elapsedMs")
        assertTrue(elapsedMs < 5_500, "Real probe exceeded its startup budget")
        assertTrue(resolution.outcome != PlaybackRedirectResolution.Outcome.Placeholder, "Provider returned a status clip")
        // Optional handoff to the native playback harness. The destination must already exist
        // with private permissions so URL and authorization headers never become world-readable.
        config["resolvedConfigPath"]?.jsonPrimitive?.content?.let { destination ->
            val output = File(destination)
            check(output.isFile)
            output.writeText(buildJsonObject {
                config.forEach { (key, value) -> put(key, value) }
                put("url", JsonPrimitive(resolution.playbackUrl))
            }.toString())
        }
    }
}

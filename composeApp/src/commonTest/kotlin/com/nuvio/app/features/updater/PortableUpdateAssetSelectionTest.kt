package com.nuvio.app.features.updater

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PortableUpdateAssetSelectionTest {
    @Test
    fun `selects the portable zip used by fork releases`() {
        val selected = selectBestPortableUpdateAsset(
            listOf(
                asset("checksums.txt", "text/plain"),
                asset("Nuvio.zip", "application/x-zip-compressed"),
            ),
            supportedAbis = listOf("x64", "windows"),
        )

        assertEquals("Nuvio.zip", selected?.name)
    }

    @Test
    fun `does not treat installers as portable updates`() {
        val selected = selectBestPortableUpdateAsset(
            listOf(
                asset("Nuvio.msi", "application/octet-stream"),
                asset("Nuvio.exe", "application/octet-stream"),
            ),
            supportedAbis = listOf("x64", "windows"),
        )

        assertNull(selected)
    }

    @Test
    fun `parses github sha256 digest into lowercase hex`() {
        val hex = "a".repeat(64)
        val parsed = GitHubAssetDto(
            name = "Nuvio.zip",
            browserDownloadUrl = "https://example.test/Nuvio.zip",
            digest = "sha256:${hex.uppercase()}",
        ).sha256Hex()

        assertEquals(hex, parsed)
    }

    @Test
    fun `ignores missing malformed or non-sha256 digests`() {
        fun digestOf(value: String?) = GitHubAssetDto(
            name = "Nuvio.zip",
            browserDownloadUrl = "https://example.test/Nuvio.zip",
            digest = value,
        ).sha256Hex()

        assertNull(digestOf(null))
        assertNull(digestOf("sha512:${"a".repeat(128)}")) // wrong algorithm
        assertNull(digestOf("sha256:not-hex"))
        assertNull(digestOf("sha256:${"a".repeat(63)}")) // too short
    }

    @Test
    fun `mac selects only DMG for the running architecture`() {
        val assets = listOf(
            asset("Nuvio-windows-arm64.zip", "application/zip"),
            asset("Nuvio-macos-x64.dmg", "application/octet-stream"),
            asset("Nuvio-macos-universal.dmg", "application/octet-stream"),
            asset("Nuvio-macos-arm64.dmg", "application/octet-stream"),
        )
        assertEquals("Nuvio-macos-arm64.dmg", selectBestPortableUpdateAsset(assets, listOf("macos", "arm64"))?.name)
        assertEquals("Nuvio-macos-x64.dmg", selectBestPortableUpdateAsset(assets, listOf("macos", "x64"))?.name)
        assertEquals("Nuvio-macos-universal.dmg", selectBestPortableUpdateAsset(assets.dropLast(1), listOf("macos", "arm64"))?.name)
    }

    @Test
    fun `wrong OS and CPU never fall back to an incompatible installer`() {
        assertNull(selectBestPortableUpdateAsset(listOf(asset("Nuvio-windows-arm64.zip", "application/zip")), listOf("macos", "arm64")))
        assertNull(selectBestPortableUpdateAsset(listOf(asset("Nuvio-macos-x64.dmg", "application/octet-stream")), listOf("macos", "arm64")))
        assertNull(selectBestPortableUpdateAsset(listOf(asset("Nuvio-macos-arm64.zip", "application/zip")), listOf("windows", "arm64")))
        assertNull(selectBestPortableUpdateAsset(listOf(asset("Nuvio-windows-arm64.zip", "application/zip")), listOf("windows", "x64")))
    }

    private fun asset(name: String, contentType: String) =
        GitHubAssetDto(
            name = name,
            browserDownloadUrl = "https://example.test/$name",
            contentType = contentType,
        )
}

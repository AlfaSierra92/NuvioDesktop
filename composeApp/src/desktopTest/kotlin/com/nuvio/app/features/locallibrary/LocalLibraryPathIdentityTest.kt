package com.nuvio.app.features.locallibrary

import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.assertEquals

class LocalLibraryPathIdentityTest {
    @Test
    fun windowsPathsKeepTheirOwnRulesAndPosixPathsKeepLiteralBackslashes() {
        assertTrue("d:\\Media\\Anime\\file.mkv".isInsideDirectory("D:/media/anime"))
        assertFalse("/missing/Media/file.mkv".isInsideDirectory("/missing/media"))
        assertTrue("/missing/Media/file.mkv".isInsideDirectory("/missing/Media"))
        assertFalse("/missing/Media/file.mkv".isInsideDirectory("/missing/Med"))
        assertFalse("/missing/Media\\Other/file.mkv".isInsideDirectory("/missing/Media"))
    }

    @Test
    fun sourceLocationPreservesBackslashesInPosixFolderNames() {
        val item = LocalMediaItem(key = "test", folderId = "folder", type = LocalFolderType.SERIES,
            isAnime = false, title = "Show", files = listOf(
                LocalMediaFile(path = "/Media/Show\\alternate/first.mkv"),
                LocalMediaFile(path = "/Media/Show\\alternate/second.mkv"),
            ))
        assertEquals("/Media/Show\\alternate", item.sourceLocation)
    }

    @Test
    fun differentlySpelledExistingDirectoriesUseTheActualFilesystemIdentity() {
        val root = Files.createTempDirectory("nuvio-case-test").toFile()
        try {
            val media = root.resolve("Media").apply { mkdirs() }
            val alias = root.resolve("media")
            val same = runCatching { Files.isSameFile(media.toPath(), alias.toPath()) }.getOrDefault(false)
            assertEquals(same, (media.path + "/film.mkv").isInsideDirectory(alias.path))
        } finally { root.deleteRecursively() }
    }
}

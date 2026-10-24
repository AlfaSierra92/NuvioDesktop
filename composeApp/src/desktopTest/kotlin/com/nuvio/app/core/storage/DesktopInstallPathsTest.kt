package com.nuvio.app.core.storage

import java.nio.file.Path
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class DesktopInstallPathsTest {
    @Test
    fun macosPortableDataLivesBesideTheBundle() {
        val bundle = Path.of("/Applications/Nuvio d'Antonio.app")
        val launcher = bundle.resolve("Contents/MacOS/Nuvio HTPC")
        assertEquals(bundle, macosAppBundle(launcher))
        assertEquals(Path.of("/Applications/Nuvio d'Antonio.portable"), desktopPortableInstallRoot(launcher, "Mac OS X"))
        assertNull(desktopPortableInstallRoot(Path.of("/tmp/development/launcher"), "Mac OS X"))
        assertNull(macosAppBundle(bundle.resolve("Contents/Resources/launcher")))
    }

    @Test
    fun installedMacosDataNeverUsesWindowsEnvironment() {
        val home = Path.of("/Users/Antonio")
        assertEquals(home.resolve("Library/Application Support/NuvioHTPC"),
            desktopInstalledDataDirectory("Mac OS X", home) { error("Mac must not consult Windows environment") })
    }

    @Test
    fun windowsAndLinuxInstalledLocationsArePreserved() {
        val home = Path.of("/users/Antonio")
        val launcher = Path.of("/install/Nuvio.exe")
        assertEquals(launcher.parent, desktopPortableInstallRoot(launcher, "Windows 11"))
        assertEquals(Path.of("/local-app-data/NuvioHTPC"),
            desktopInstalledDataDirectory("Windows 11", home) { if (it == "LOCALAPPDATA") "/local-app-data" else null })
        assertEquals(home.resolve("AppData/Local/NuvioHTPC"), desktopInstalledDataDirectory("Windows 11", home) { null })
        assertEquals(Path.of("/xdg/nuviohtpc"),
            desktopInstalledDataDirectory("Linux", home) { if (it == "XDG_CONFIG_HOME") "/xdg" else null })
    }
}

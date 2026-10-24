# Residui Windows nel port macOS di Nuvio HTPC

Audit del 24 ottobre 2026 sul working tree corrente, incluse le modifiche locali già presenti.

## Ambito e limiti

Richiesta interpretata come inventario delle funzionalità ereditate da Windows da completare o correggere su macOS. Ricerca trasversale nei sorgenti e lettura mirata dei rami di piattaforma, dei chiamanti, delle impostazioni, dei bridge JNI, dei controlli HTML/JS e della configurazione di build. Inventario Kotlin: 840 file commonMain, 9 fullCommonMain, 305 desktopMain, 307 commonTest, 150 desktopTest. Le dipendenze vendorizzate non sono state sottoposte a una revisione riga per riga.

È un audit statico: non sono stati avviati test di riproduzione, spegnimento, cambio account, migrazioni o aggiornamenti. “Confermato” indica evidenza nel sorgente; non significa riproduzione manuale di ogni effetto. Nessuna correzione applicativa applicata. Le priorità P1/P2/P3 indicano rispettivamente difetti da affrontare prima, funzionalità incomplete e rifiniture/parità opzionale.

## Elenco degli interventi

### 1. Riavvio dopo cambio account e import impostazioni — P1

**Stato:** Difetto confermato nel codice.

`relaunchAfterExit()` scrive un batch e avvia sempre `cmd.exe`, senza distinguere il sistema operativo. Su una .app con `jpackage.app-path` valido arriva a un comando Windows inesistente; in sviluppo ritorna false e può mascherare il problema. Il cambio account salva la nuova scelta prima di richiedere il riavvio; l’import copia il backup pendente prima di richiamare questa funzione. Un errore qui può lasciare il cambiamento registrato ma il processo ancora nel vecchio stato.

**Riferimenti:** [DesktopRelaunch.kt:13](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/DesktopRelaunch.kt:13), [DesktopAccountSlots.kt:265](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/core/storage/DesktopAccountSlots.kt:265), [DesktopSettingsBackup.desktop.kt:396](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/settings/DesktopSettingsBackup.desktop.kt:396).

**Intervento e verifica:** Implementare il riavvio macOS con attesa della terminazione e rilancio della .app; gestire gli errori prima di dichiarare riuscita l’operazione. Verificare cambio account e import sulla .app installata, con TorrServer attivo e percorsi con spazi/accenti.

### 2. Modalità portable e migrazione dei dati — P1

**Stato:** Difetto confermato nel codice.

`PortableMode.isSupported` accetta qualunque launcher jpackage. `portableInstallRoot()` usa il genitore del launcher: nel layout .app standard coincide con Contents/MacOS. `appDataInstallDir()` continua invece a costruire AppData/Local/NuvioHTPC. La migrazione portable non usa quindi la cartella macOS Library/Application Support/NuvioHTPC. Anche il riavvio richiesto dal toggle dipende dal batch del punto precedente.

**Riferimenti:** [PortableMode.desktop.kt:7](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/core/storage/PortableMode.desktop.kt:7), [DesktopStorage.kt:339](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/core/storage/DesktopStorage.kt:339), [DesktopStorage.kt:346](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/core/storage/DesktopStorage.kt:346), [AccountSettingsPage.kt:475](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/commonMain/kotlin/com/nuvio/app/features/settings/AccountSettingsPage.kt:475).

**Intervento e verifica:** Definire un layout portable macOS esterno al bundle e condividere la risoluzione della directory dati con quella ordinaria; finché manca, non dichiarare il supporto. Verificare andata e ritorno senza perdere account, impostazioni e cache.

### 3. Rilevamento e avvio dei player esterni — P2

**Stato:** Porting incompleto confermato.

Le definizioni di mpv e VLC cercano solo nomi .exe e percorsi Windows. MPC, PotPlayer ed Energy restano nel catalogo anche su Mac. La selezione manuale usa FILES_ONLY e il launcher richiede un file eseguibile: non gestisce una .app come applicazione. Il fallback di sistema esiste, ma per URL HTTP può aprire il browser e non offre la stessa integrazione di resume, header e sottotitoli.

**Riferimenti:** [ExternalPlayerPlatform.desktop.kt:55](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/ExternalPlayerPlatform.desktop.kt:55), [ExternalPlayerPlatform.desktop.kt:454](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/ExternalPlayerPlatform.desktop.kt:454), [ExternalPlayerPlatform.desktop.kt:503](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/ExternalPlayerPlatform.desktop.kt:503).

**Intervento e verifica:** Creare definizioni per macOS con binari mpv/VLC e bundle applicativi; decidere come supportare IINA. Rilevare anche /opt/homebrew/bin e /usr/local/bin senza dipendere dal PATH ereditato dal Finder. Verificare URL, sottotitoli, header e ripresa.

### 4. Tracking di mpv esterno — P2

**Stato:** Difetto confermato nel codice.

`prepareExternalPlayerChannel()` crea sempre un endpoint \\.\pipe\nuvio-mpv-…; `MpvIpcReader` comunica con RandomAccessFile. Anche la ricerca di mpv.conf usa APPDATA e portable_config con separatori Windows. Se mpv viene configurato manualmente su Mac, questo canale non è il trasporto Unix necessario.

**Riferimenti:** [ExternalPlayerMonitor.desktop.kt:66](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/ExternalPlayerMonitor.desktop.kt:66), [ExternalPlayerMonitor.desktop.kt:176](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/ExternalPlayerMonitor.desktop.kt:176), [ExternalPlayerMonitor.desktop.kt:233](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/ExternalPlayerMonitor.desktop.kt:233).

**Intervento e verifica:** Usare socket Unix con timeout, percorsi di configurazione macOS e pulizia dell’endpoint; mantenere le named pipe per Windows. Verificare pausa, seek, durata e aggiornamento del progresso, non soltanto l’avvio del processo.

### 5. Game Mode: importazione e avvio giochi Mac — P2

**Stato:** Porting incompleto confermato.

Il picker propone .exe/.lnk/.url; lo scanner cerca esclusivamente file .exe e collegamenti Windows. Un bundle .app è una directory e `launch()` richiede `isFile`, perciò non viene trattato come gioco avviabile. Il ramo `open` per gli URL di protocollo esiste già: i link steam:// non vanno confusi con l’importazione di giochi .app.

**Riferimenti:** [GameLauncher.kt:13](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/games/GameLauncher.kt:13), [GameLauncher.kt:86](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/games/GameLauncher.kt:86), [GameFolderScanner.kt:169](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/games/GameFolderScanner.kt:169), [GameLaunchTarget.kt:36](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/games/GameLaunchTarget.kt:36).

**Intervento e verifica:** Supportare bundle .app, eseguibili Unix e collegamenti appropriati; usare open per i bundle e distinguere il processo launcher dal gioco se si vuole monitorarne la chiusura.

### 6. Casting: discovery ffmpeg/ffprobe e remux Dolby Vision — P2

**Stato:** Difetto confermato nel codice.

Il resolver cerca sempre ffmpeg.exe e ffprobe.exe, anche nel PATH del Mac. I fallback sono WinGet, ProgramFiles, Scoop e C:\ffmpeg. `dolbyVisionRemuxAvailable()` dipende da questo resolver: con una normale installazione macOS la funzione risulta indisponibile. Il casting diretto ha un percorso separato e non risulta interamente bloccato da questo difetto.

**Riferimenti:** [Ffmpeg.kt:15](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/cast/Ffmpeg.kt:15), [DeviceCastPlatform.desktop.kt:38](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/cast/DeviceCastPlatform.desktop.kt:38).

**Intervento e verifica:** Risolvere nomi e percorsi per OS, includendo i prefissi Homebrew e il contesto Finder. Verificare rilevamento, remux e ripresa del casting con ffprobe disponibile.

### 7. Collegamenti esterni nuvio:// — P2

**Stato:** Integrazione macOS assente nel codice esaminato.

`DesktopUrlScheme` registra solo il protocollo nel registro Windows. Main riceve il link dagli argomenti della command line. La configurazione Info.plist non dichiara CFBundleURLTypes/CFBundleURLSchemes e non risulta registrato un OpenURIHandler. Il parser condiviso e l’inoltro single-instance esistono: manca l’ingresso nativo macOS.

**Riferimenti:** [DesktopUrlScheme.kt:19](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/DesktopUrlScheme.kt:19), [Main.kt:462](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/Main.kt:462), [build.gradle.kts:1952](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/build.gradle.kts:1952).

**Intervento e verifica:** Dichiarare lo schema nel bundle e inoltrare gli eventi URL macOS al parser esistente. Provare link a contenuti e watch party sia a processo chiuso sia con app già aperta.

### 8. Picture-in-Picture: interazioni dal video — P2

**Stato:** Lacuna confermata; comportamento completo da provare.

La finestra piccola e always-on-top è gestita anche con AWT. Tuttavia i comandi dei controlli HTML per trascinamento e resize arrivano a funzioni che ritornano subito fuori da Windows; anche lo stile compact è solo Windows. Il PiP non è quindi totalmente assente, ma manca l’equivalente macOS delle interazioni personalizzate.

**Riferimenti:** [DesktopWindowChrome.kt:49](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/desktop/DesktopWindowChrome.kt:49), [DesktopWindowChrome.kt:86](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/desktop/DesktopWindowChrome.kt:86), [NativePlayerController.kt:1281](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/desktop/NativePlayerController.kt:1281), [Main.kt:727](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/Main.kt:727).

**Intervento e verifica:** Implementare move/resize e stile con NSWindow oppure un fallback AWT coerente. Provare drag dal video, bordi, più monitor e ritorno dal fullscreen.

### 9. Anteprime locali sulla barra temporale — P2

**Stato:** Funzione ancora esclusiva di Windows.

`requestSeekThumbnail()` nel bridge macOS è una funzione vuota. Il JSON dei controlli e `nativePreviewsSupported` disabilitano le anteprime native sul Mac. Le impostazioni espongono già Off/Seekr: le anteprime remote Seekr sono distinte e non vanno indicate come mancanti.

**Riferimenti:** [player_bridge.mm:2826](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/native/macos/player_bridge.mm:2826), [NativePlayerController.kt:2402](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/desktop/NativePlayerController.kt:2402), [PlayerScreenRuntimeEffects.kt:1245](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/commonMain/kotlin/com/nuvio/app/features/player/PlayerScreenRuntimeEffects.kt:1245).

**Intervento e verifica:** Portare il worker di estrazione frame e la consegna delle immagini ai controlli WebKit. Verificare hover ripetuti, sorgenti locali/rete e cancellazione alla chiusura.

### 10. Sincronizzazione sottotitoli basata sull’audio — P2

**Stato:** Funzione ancora esclusiva di Windows.

`supportsSpeechSpots` è true solo su Windows. Le JNI decodeSpeechSpot e speechSourceBytesPerSecond non sono esportate dal bridge Mac, e `runAudioReferencedSubtitleSync()` restituisce NoReference quando manca la capacità. La sincronizzazione con timeline dei sottotitoli incorporati segue invece un altro percorso e rimane disponibile nel codice condiviso.

**Riferimenti:** [NativePlayerController.kt:1739](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/desktop/NativePlayerController.kt:1739), [AutomaticSubtitleSync.desktop.kt:141](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/AutomaticSubtitleSync.desktop.kt:141).

**Intervento e verifica:** Implementare estrazione di brevi campioni PCM e stima bitrate sul Mac, poi abilitare la capacità. Verificare audio sync con un file senza sottotitoli incorporati di riferimento.

### 11. Controller e navigazione con gamepad — P2

**Stato:** Funzione ancora esclusiva di Windows.

`gamepadSupported()` restituisce true solo su Windows e il poller esclude gli altri OS. Il bridge macOS non implementa pollGamepads. Il mapping e l’iniezione delle azioni sono riutilizzabili, ma manca l’acquisizione degli input nativi.

**Riferimenti:** [GamepadBindings.desktop.kt:6](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/input/GamepadBindings.desktop.kt:6), [GamepadInput.kt:166](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/input/GamepadInput.kt:166).

**Intervento e verifica:** Aggiungere un backend macOS per controller mantenendo i mapping esistenti. Verificare connessione/disconnessione, dead zone, ripetizione e focus tra Compose e WebKit.

### 12. AutoCrop / rilevamento bande nere — P2

**Stato:** Funzione ancora esclusiva di Windows.

Il JSON dichiara autoCropSupported solo su Windows e il modello condiviso normalizza AutoCrop a Fit sul Mac. `setResizeMode()` del bridge macOS implementa keepaspect/panscan per Fit, Fill e Zoom, senza rilevamento dinamico delle bande.

**Riferimenti:** [NativePlayerController.kt:2390](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/desktop/NativePlayerController.kt:2390), [PlayerLayout.kt:203](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/commonMain/kotlin/com/nuvio/app/features/player/PlayerLayout.kt:203), [player_bridge.mm:1908](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/native/macos/player_bridge.mm:1908).

**Intervento e verifica:** Portare il rilevamento e la gestione del crop, mantenendo la capacità disabilitata finché non è pronta. Provare cambi di aspect ratio e ripristino quando si disattiva.

### 13. Media session del sistema — P2

**Stato:** Implementazione macOS vuota.

`setMediaSessionMetadata()` è esportata anche su Mac ma ha corpo vuoto; il commento conferma l’assenza dell’equivalente della sessione SMTC Windows. Non pubblica quindi titolo, episodio e artwork tramite questa integrazione. L’assenza della media session non dimostra da sola l’assenza di tutti i tasti multimediali quando la finestra è attiva.

**Riferimenti:** [player_bridge.mm:3012](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/native/macos/player_bridge.mm:3012), [NativePlayerController.kt:488](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/desktop/NativePlayerController.kt:488).

**Intervento e verifica:** Implementare Now Playing e i comandi remoti macOS; verificare titolo/artwork, play/pause, chiusura della sessione e comando con app in background.

### 14. Runtime QuickJS con patch JNI — P2, da valutare

**Stato:** Differenza confermata; impatto sul Mac da misurare.

La selezione della libreria corretta con local frame JNI è limitata a Windows e distribuisce libquickjs.dll. Il Mac usa il runtime della dipendenza Maven. Il README documenta riferimenti locali trattenuti dall’implementazione originale, con particolare impatto sul native-image Windows; non basta per affermare un crash o un leak permanente già riprodotto sul Mac. Il test della patch viene saltato se manca la proprietà della libreria.

**Riferimenti:** [QuickJsNativeLibrary.kt:24](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/plugins/QuickJsNativeLibrary.kt:24), [README.md:14](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/native/quickjs-kt/README.md:14), [QuickJsBindingLocalRefTest.kt:22](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopTest/kotlin/com/nuvio/app/features/plugins/QuickJsBindingLocalRefTest.kt:22).

**Intervento e verifica:** Eseguire stress test degli scraper su HotSpot/macOS; decidere se compilare la dylib con la stessa patch oppure aggiornare la dipendenza a una versione corretta verificata.

### 15. Confronto dei percorsi nella libreria locale — P2 su volumi case-sensitive

**Stato:** Assunzione Windows confermata.

`commonDirectoryPath()` e `isInsideDirectory()` confrontano i segmenti ignorando sempre maiuscole/minuscole e trattano sempre il backslash come separatore. I commenti li motivano ancora con “Windows-only build”. Su un volume macOS case-sensitive cartelle distinte possono essere associate alla stessa radice; anche alcuni confronti dello scanner giochi usano lowercase.

**Riferimenti:** [LocalLibraryModels.kt:425](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/commonMain/kotlin/com/nuvio/app/features/locallibrary/LocalLibraryModels.kt:425), [LocalLibraryModels.kt:450](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/commonMain/kotlin/com/nuvio/app/features/locallibrary/LocalLibraryModels.kt:450), [LocalLibraryRepository.kt:208](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/commonMain/kotlin/com/nuvio/app/features/locallibrary/LocalLibraryRepository.kt:208).

**Intervento e verifica:** Rendere la politica dei percorsi coerente con il filesystem e normalizzare sul livello desktop. Verificare /Media e /media come cartelle distinte su un volume case-sensitive.

### 16. Scorciatoia incolla URL e inviti — P3

**Stato:** Adattamento macOS incompleto.

Il gestore globale che incolla un URL di streaming o un invito watch-party controlla soltanto Ctrl+V. Non riconosce Command+V per questa azione. È distinto dall’incolla normale nei campi di testo e dalle scorciatoie fullscreen, che hanno già adattamenti Mac.

**Riferimenti:** [Main.kt:964](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/Main.kt:964).

**Intervento e verifica:** Usare il modificatore di menu del sistema per questa azione e non intercettare le combinazioni Command nei dispatcher di tasti singoli. Provare sia Home sia un campo di testo attivo.

### 17. Aggiornamenti automatici, trailer e testi Windows — P3 / parità funzionale

**Stato:** Limiti espliciti e pulizia.

L’updater Mac riconosce .dmg e lo apre; lo swap automatico e i delta restano Windows-only. I trailer adattivi preferiscono soltanto 1080p fuori da Windows. Alcune stringhe comuni descrivono Nuvio.exe, AppData, dispositivo audio Windows e percorsi C:\Shaders. Sono differenze di funzionalità/testo, non prova di un errore del player di base.

**Riferimenti:** [AppUpdaterPlatform.desktop.kt:125](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/updater/AppUpdaterPlatform.desktop.kt:125), [AppUpdaterPlatform.desktop.kt:228](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/updater/AppUpdaterPlatform.desktop.kt:228), [TrailerExtractionPlatform.desktop.kt:25](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/trailer/TrailerExtractionPlatform.desktop.kt:25), [strings.xml:857](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/commonMain/composeResources/values/strings.xml:857).

**Intervento e verifica:** Decidere se realizzare un updater Mac con installazione automatica; rivalutare 1440p/2160p dopo test; separare i testi per piattaforma e aggiornare la documentazione dei percorsi.

### 18. Nuvio Engine nativo — P2

`NuvioEngineLibrary` dichiara soltanto `nuvio_engine.dll` e la disponibilità richiede Windows. La build CMake include gli header JNI da `include/win32`; il task di build è `buildWindowsNuvioEngine`. È quindi assente la distribuzione di una libreria motore macOS caricabile. Il selettore P2P passa esplicitamente a TorrServer quando il motore non è disponibile.

**Riferimenti:** [NuvioEngineLibrary.kt:14](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/engine/internal/NuvioEngineLibrary.kt:14), [P2pStreamingEngine.desktop.kt:92](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/p2p/P2pStreamingEngine.desktop.kt:92), [CMakeLists.txt:72](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/native/nuvio-engine/CMakeLists.txt:72).

**Intervento:** aggiungere build e bundle di una dylib per architettura, selezione corretta degli header JNI e loader per OS; verificare il motore nativo e il fallback TorrServer separatamente.

### 19. SVP / VapourSynth — P2

`DesktopAnimeSvp` cerca vsscript.dll nella directory del runtime. Il runtime Python/VapourSynth/SVP preparato dalla build è Windows; il bridge Mac ignora animeSvpFilter e il toggle dei controlli è disabilitato fuori da Windows. Gli shader Anime4K e l’interpolazione mpv non equivalgono al runtime SVP.

**Riferimenti:** [DesktopAnimeSvp.kt:33](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/desktop/DesktopAnimeSvp.kt:33), [player_bridge.mm:2533](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/native/macos/player_bridge.mm:2533), [NativePlayerController.kt:992](/Users/antoniosolida/Desktop/NuvioDesktop/composeApp/src/desktopMain/kotlin/com/nuvio/app/features/player/desktop/NativePlayerController.kt:992).

**Intervento:** decidere se supportare un’installazione SVP macOS esterna o una distribuzione compatibile; aggiungere ricerca delle librerie e integrazione nativa, senza riusare la catena di DLL Windows.

## Funzioni Windows da conservare separate

- NVIDIA RTX Super Resolution, RTX True HDR, lettura del registro NVIDIA e Direct3D sono integrazioni specifiche dell’hardware/API Windows. Il port Mac deve escluderle dalla capacità esposta; non è opportuno tradurre le chiamate al registro o a D3D in chiamate fittizie sul Mac. Un’eventuale alternativa Apple sarebbe una funzione distinta.
- Il fullscreen borderless Win32, gli interventi sul root pane, il watchdog, AppUserModelID, Start Menu e il launch shield sono già protetti per OS. Su Mac esiste un percorso fullscreen diverso: la loro assenza nel bridge Mac non è da sola un bug.
- GraalVM native-image, gli script .ps1/.ahk, packaging MSI, training CDS e la distribuzione delle DLL sono task/tool Windows con guardie: non sono tutti da portare per far funzionare la .app JVM.

## Adattamenti già presenti, esclusi dall’elenco dei mancanti

- Backend Metal della UI e caricamento del bridge nativo macOS.
- Riproduzione, eventi di caricamento/avvio, volume/mute, tracce, sottotitoli e controlli WebKit.
- Gestione HDR con policy specifica macOS e opzioni di buffer distinte per sistema.
- Scroll nativo Mac, percorsi ordinari in Library/Application Support e packaging .app/.dmg con runtime del player relocabile.
- Discord IPC con socket Unix; non usa più esclusivamente le named pipe Windows.
- TorrServer con selezione di OS/architettura e permessi eseguibili; il P2P non è totalmente assente sul Mac.
- Keep-awake del display tramite IOPMAssertion, lettura idle e richiesta di spegnimento Mac. Non sono residui da sostituire con shutdown.exe.
- Seekr remoto e AutoSync basato sui sottotitoli incorporati, distinti dai worker mancanti ai punti 9 e 10.
- Shader GLSL: il separatore dei percorsi è già scelto per OS, nonostante un commento iniziale ancora dica Windows-only.

## Controllo del contratto JNI e copertura

Nel bridge Kotlin sono dichiarati 58 metodi nativi; 17 non sono esportati dal sorgente del bridge macOS. Tutti e 17 sono esplicitamente esclusi dal test JNI Mac come Windows-only: non è corretto presentarli tutti come crash di linkage attuali. Tra i metodi esportati, requestSeekThumbnail e setMediaSessionMetadata hanno invece corpi vuoti sul Mac. Il test con handle zero controlla il collegamento, ma non dimostra il funzionamento di queste funzionalità.

Le verifiche aggiuntive più utili sono test sulla .app reale per riavvio/import/account, migrazione portable, discovery e IPC dei player esterni, game bundle .app, ingresso URL tramite Launch Services, interazioni PiP e discovery ffmpeg dal Finder. Per QuickJS serve una misura dedicata prima di attribuire al Mac i problemi osservati su GraalVM Windows.

## Ordine di lavoro suggerito

1. Riavvio e modalità portable, perché toccano il cambio di stato e la posizione dei dati.
2. Player esterni/IPC, Game Mode, ffmpeg e ingresso nuvio://.
3. PiP, anteprime locali, audio sync e media session.
4. Backend gamepad, Nuvio Engine e possibile SVP Mac secondo la parità desiderata.
5. Percorsi case-sensitive, QuickJS con misure, scorciatoie, testi, trailer e updater.


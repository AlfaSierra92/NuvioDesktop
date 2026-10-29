# Stato del port macOS di Nuvio HTPC

Aggiornato al 26 ottobre 2026. Questo documento sostituisce l'elenco operativo
dell'audit del 24–25 ottobre: molti punti descritti allora come mancanti sono
stati implementati. I dettagli storici restano nella cronologia Git; le guide
correnti sono nell'[indice della documentazione](README.md).

## Stato attuale

| Area | Implementazione e riferimenti |
|---|---|
| UI e player | Compose usa il percorso Metal; il [bridge macOS](../composeApp/src/desktopMain/native/macos/player_bridge.mm) integra libmpv e controlli WebKit, proprietà, tracce, volume ed eventi di caricamento/avvio. |
| Ciclo di vita e riavvio | Avvio, single instance e percorsi di riavvio sono nel [desktop Kotlin](../composeApp/src/desktopMain/kotlin/com/nuvio/app/); cambio account/import e portable richiedono il riavvio previsto dal flusso. |
| Dati e portable | [DesktopStorage](../composeApp/src/desktopMain/kotlin/com/nuvio/app/core/storage/DesktopStorage.kt) e [DesktopInstallPaths](../composeApp/src/desktopMain/kotlin/com/nuvio/app/core/storage/DesktopInstallPaths.kt): root NuvioHTPC, dati portable fuori dal bundle, migrazione macOS/Linux limitata ai precedenti dati del fork. |
| Player esterni | Discovery di mpv/VLC, risoluzione dei bundle `.app` e tracking mpv tramite socket Unix; gli altri player dipendono dal supporto esposto per OS. |
| Giochi | Selezione nativa di bundle/eseguibili, lancio dei bundle e gestione dei percorsi; normalizzazione del nome da percorsi Windows anche su macOS. |
| Casting | Discovery ffmpeg/ffprobe e percorsi DLNA; richiede verifica sul dispositivo reale e gli eseguibili esterni quando utilizzati. |
| Link applicazione | [DesktopUrlScheme](../composeApp/src/desktopMain/kotlin/com/nuvio/app/DesktopUrlScheme.kt) e bundle registrano `nuviohtpc://`; il parser comune accetta ancora stringhe legacy, senza registrare lo schema dell'originale. |
| PiP, anteprime e AutoCrop | Percorsi nativi implementati; il feature harness esercita ripristino della finestra, JPEG e rilevamento/ripristino delle bande. |
| Sottotitoli e audio | Sincronizzazione tramite campioni dell'audio multimediale con limiti/cancellazione; non richiede cattura del microfono. |
| Media session | Now Playing e comandi remoti, con pulizia della sessione nel ciclo di vita del player. |
| Controller | Backend GameController; il funzionamento con controller/ricevitori specifici richiede prova hardware. |
| QuickJS | [Runtime JNI con patch](../composeApp/src/desktopMain/native/quickjs-kt/README.md), build e distribuzione della dylib macOS. |
| Nuvio Engine | [Build dylib e JNI Darwin](../composeApp/src/desktopMain/native/nuvio-engine/README.md), dipendenze separate da quelle del player e fallback TorrServer. |
| SVP | Discovery di runtime esterno compatibile; non è incluso né installato automaticamente. |

## Correzioni del 26 ottobre

- Il player passava gli header come stringa separata da virgole. Lo User-Agent
  predefinito contiene una virgola: server HTTP rigorosi ricevevano una richiesta
  malformata e rispondevano `400 Bad Request`. Il bridge passa ora una lista nativa
  a libmpv sia per il player sia per i decoder di probe, preservando virgole e backslash.
- Il pacchetto usa `com.nuvio.htpc.desktop` e `nuviohtpc://`, con directory
  temporanee specifiche del fork. È stata rimossa la pulizia che poteva eliminare
  binari TorrServer dalla directory temporanea dell'originale.
- Sono presenti le descrizioni per rete locale, cartelle protette, volumi di rete,
  dischi rimovibili e Apple Events. I selettori nativi coprono anche backup,
  import/export, giochi e player esterni. Le `.app` sono selezionabili come bundle.
- La firma viene applicata dopo staging nativo e modifiche ai jar/build-info,
  quindi verificata sul bundle definitivo. Una firma ad hoc valida non equivale
  a una firma Developer ID o a notarizzazione.
- Il fallimento dello spegnimento facoltativo mantiene aperta l'app e indica dove
  riabilitare Automazione se il consenso è stato negato.
- Ripristinato il pulsante **Info** nella barra del player per la diagnostica mpv;
  mantiene lo stato allineato a menu e scorciatoia. SVP segue la propria disponibilità
  anche su macOS, senza dipendere dal flag delle estensioni video Windows.
- La ricerca delle impostazioni include i controller supportati su macOS. L'editor
  giochi mostra un esempio `.app`, l'apertura dei log usa Finder e il riconoscimento
  del nome di una libreria Steam gestisce anche percorsi Windows importati.
- La compilazione legge il canale aggiornamenti da Application Support su macOS,
  dalla posizione Windows su Windows e da XDG su Linux.

## Verifica estesa del 26 ottobre

La verifica del port include la suite desktop completa e un controllo dei confini
OS nei processi esterni, caricamento nativo, dati, aggiornamenti, giochi, controller,
casting e controlli del player. I test iniziali hanno rilevato 24 fallimenti su
3.176 test: diversi confronti assumevano inglese/USA su un sistema italiano,
altri usavano separatori Windows o presumevano che lo scrolling assorbisse sempre
il clic. Queste precondizioni sono state rese esplicite o adattate alla piattaforma;
la lingua dell'app rimane configurabile.

Esito della riesecuzione completa con `:composeApp:desktopTest`: **3.180 test,
zero fallimenti/errori, 2 esclusi** (harness manuale della sincronizzazione
sottotitoli e WebDAV con configurazione esterna). Gli opt-in che terminano senza
una configurazione non dimostrano il funzionamento di un provider o dispositivo
reale. Il feature harness nativo e il test HTTP della `.app` sono terminati con
successo separatamente dalla suite JVM.

| Area | Tipo di verifica |
|---|---|
| Dati, profili, backup, riavvio, link | Suite desktop; directory di test separate dai dati ordinari. |
| Cataloghi, libreria locale, giochi, download e IPTV | Suite desktop con fixture e server di test; nessun account/provider reale richiesto. |
| Player macOS | Feature harness sul bridge/libmpv reale: PiP, colore a video in pausa, anteprime JPEG, campioni audio, AutoCrop, Now Playing e recupero da warning audio. |
| Streaming HTTP | Server locale rigoroso: header con virgole/backslash, URL diretti e redirect, avanzamento verificato anche nella `.app` completa. |
| Controlli WebKit | Pulsante Info e sincronizzazione, variazioni disponibilità SVP, blocco comandi RTX su Mac. |
| Controller, player esterni, Discord e casting | Test di mapping, comandi/processi, socket e protocolli; periferiche e servizi esterni richiedono prove separate. |
| Aggiornamenti | Selezione DMG per architettura e percorsi preferenze; nessun aggiornamento installato automaticamente durante l'audit. |

Nel bundle finale sono passati tre cicli di entrata/uscita PiP con video in
avanzamento e chiusura nativa pulita, insieme a tre cicli HDR. Una seconda prova
con sorgente sintetica HEVC/PQ a 10 bit ha verificato rilevamento HDR, tonemap SDR
e coerenza tra metadati mpv e codifica del layer. Questo verifica il percorso
software; non misura luminanza o fedeltà cromatica di un display HDR fisico.
La build `createDistributable` e `codesign --verify --deep --strict` sono passate.

Anche i test opt-in con focus reale sono stati eseguiti separatamente:
`GamepadInjectionRouteTest` e `SyntheticTextInputRouteTest`, **3 test superati**,
senza saltare il percorso di focus. Verificano eventi sintetici fino ai dispatcher
AWT/Compose e al campo di testo; non sostituiscono un controller fisico.
Le notifiche degli episodi sono disabilitate dalla policy desktop: lo stub desktop
non è presentato come funzione disponibile. L'assenza del checkout Nuvio Engine
usa il fallback TorrServer previsto dalla build.

## Evidenze e limiti

Le verifiche effettuate durante le correzioni del 26 ottobre includono:

- 19 test mirati su link, policy degli URL LAN, percorsi e riconoscimento dei dati legacy.
- 25 test mirati su backup, avvio giochi e risoluzione dei bundle dopo le correzioni dei selettori.
- Server HTTP rigoroso con video sintetico: header integri e avanzamento del video,
  sia diretto sia dopo redirect; prova superata anche con la `.app` completa.
- Compilazione del pacchetto e verifica `codesign --verify --deep --strict`, delle
  sette descrizioni privacy e degli entitlement di Automazione/runtime.

Queste prime verifiche erano mirate; la successiva suite completa è riportata
sopra. Nessuna delle due sostituisce le prove dei provider e delle periferiche
specifiche. I comandi riproducibili sono in [Testing](Testing.md).

Restano da distinguere dalle prove automatiche:

- consenso rete/cartelle da Finder con la firma e l'installazione effettive;
- streaming dal server LAN/provider dell'utente, autenticazione e configurazione TLS;
- Intel, display HDR, passthrough receiver, controller fisici e dispositivi DLNA;
- compatibilità e qualità SVP con librerie proprietarie installate;
- prestazioni su cataloghi grandi e swarm torrent reali;
- parità completa di scorciatoie, trailer e aggiornamento automatico su tutte le piattaforme.

La separazione del bundle e dei file **non garantisce l'isolamento delle sessioni
Supabase**, ancora affidate al session manager desktop predefinito per gli avvii
ordinari. Una directory dati temporanea non cambia quel confine. Vedere
[Configuration](Configuration.md#authentication-and-coexistence).

## Integrazioni da mantenere specifiche per piattaforma

Direct3D, RTX Video, XInput, registro di sistema, HWND/named pipe e strumenti
GraalVM/Windows non vanno presentati come API macOS. Il port usa Metal,
GameController, percorsi POSIX e socket Unix dove implementato. Il collegamento
JNI con handle nullo controlla gli export, non l'effettiva riproduzione o il
funzionamento di un dispositivo fisico.

Per installazione, permessi e diagnostica usare la [guida macOS](macOS.md),
anziché i vecchi numeri di linea o percorsi assoluti dell'audit originario.

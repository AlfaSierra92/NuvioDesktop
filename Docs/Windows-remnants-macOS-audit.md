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

## Evidenze e limiti

Le verifiche effettuate durante le correzioni del 26 ottobre includono:

- 19 test mirati su link, policy degli URL LAN, percorsi e riconoscimento dei dati legacy.
- 25 test mirati su backup, avvio giochi e risoluzione dei bundle dopo le correzioni dei selettori.
- Server HTTP rigoroso con video sintetico: header integri e avanzamento del video,
  sia diretto sia dopo redirect; prova superata anche con la `.app` completa.
- Compilazione del pacchetto e verifica `codesign --verify --deep --strict`, delle
  sette descrizioni privacy e degli entitlement di Automazione/runtime.

Questi sono risultati di suite mirate e test sintetici, non una certificazione
dell'intera suite o di tutti i provider. I comandi riproducibili sono in
[Testing](Testing.md). L'esito di ogni nuova esecuzione va registrato separatamente.

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

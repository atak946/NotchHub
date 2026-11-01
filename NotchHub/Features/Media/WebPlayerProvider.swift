import Foundation
import Synchronization

/// Chromium-family browsers whose AppleScript dictionary can run JavaScript in a tab.
enum MediaBrowser: String, CaseIterable, Sendable {
    case chrome
    case arc
    case brave
    case edge

    var bundleIdentifier: String {
        switch self {
        case .chrome: "com.google.Chrome"
        case .arc: "company.thebrowser.Browser"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        }
    }

    static var bundleIdentifiers: [String] { allCases.map(\.bundleIdentifier) }
}

/// Opt-in for scanning browser tabs: the first scan makes macOS ask for Automation access to each browser.
enum WebPlayerSettings {
    static let enabledKey = "detectsBrowserMedia"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }
}

/// The tab a web player was last read from, so commands reach the same tab.
struct BrowserTabLocator: Equatable, Sendable {
    let bundleIdentifier: String
    let tabID: String
}

/// YouTube and YouTube Music in a browser tab, read and driven through `execute javascript`.
///
/// Each poll scans the running browsers' tabs whose URL matches the site and reads the page's `<video>` and
/// Media Session metadata. Needs "Allow JavaScript from Apple Events" (View › Developer) in the browser.
final class WebPlayerProvider: MediaProvider {
    let source: MediaSource

    private let browsers: [MediaBrowser]
    private let runner: any ScriptRunner
    private let appChecker: any RunningApplicationChecking
    private let downloader: any ArtworkDownloading
    private let isEnabled: @Sendable () -> Bool
    private let lastTab = Mutex<BrowserTabLocator?>(nil)

    init(
        source: MediaSource,
        browsers: [MediaBrowser] = MediaBrowser.allCases,
        runner: any ScriptRunner = AppleScriptRunner.shared,
        appChecker: any RunningApplicationChecking = WorkspaceRunningApplicationChecker(),
        downloader: any ArtworkDownloading = URLSessionArtworkDownloader(),
        isEnabled: @escaping @Sendable () -> Bool = { WebPlayerSettings.isEnabled() }
    ) {
        precondition(source.isWebPlayer, "WebPlayerProvider only drives web players")
        self.source = source
        self.browsers = browsers
        self.runner = runner
        self.appChecker = appChecker
        self.downloader = downloader
        self.isEnabled = isEnabled
    }

    func isRunning() async -> Bool {
        await !runningBridges().isEmpty
    }

    func fetchNowPlaying() async throws -> NowPlaying? {
        let script = WebPlayerScripts.scan(urlPrefixes: WebPlayerScripts.urlPrefixes(for: source), javaScript: WebPlayerScripts.read(source))
        var candidates: [(BrowserTabLocator, NowPlaying)] = []
        var firstError: ScriptError?
        for bridge in await runningBridges() {
            do {
                guard let text = try await bridge.run(script)?.text,
                      let reading = WebPlayerScripts.splitTab(text),
                      let track = NowPlayingParser.parse(reading.line, source: source)
                else { continue }
                candidates.append((BrowserTabLocator(bundleIdentifier: bridge.bundleIdentifier, tabID: reading.tabID), track))
            } catch let error as ScriptError {
                firstError = firstError ?? WebPlayerScripts.classify(error)
            }
        }
        let previous = lastTab.withLock { $0 }
        guard let chosen = candidates.first(where: { $0.1.isPlaying })
            ?? candidates.first(where: { $0.0 == previous })
            ?? candidates.first
        else {
            lastTab.withLock { $0 = nil }
            if let firstError { throw firstError }
            return nil
        }
        lastTab.withLock { $0 = chosen.0 }
        return chosen.1
    }

    func playPause() async throws { try await command(WebPlayerScripts.playPause(source)) }
    func next() async throws { try await command(WebPlayerScripts.next(source)) }
    func previous() async throws { try await command(WebPlayerScripts.previous(source)) }
    func seek(to position: TimeInterval) async throws { try await command(WebPlayerScripts.seek(to: position)) }
    func setLiked(_ liked: Bool) async throws { try await command(WebPlayerScripts.setLiked(liked)) }
    func setRepeatMode(_ mode: RepeatMode) async throws { try await command(WebPlayerScripts.setRepeatMode(mode)) }
    func setVolume(_ volume: Double) async throws { try await command(WebPlayerScripts.setVolume(volume)) }
    func setPlaybackRate(_ rate: Double) async throws { try await command(WebPlayerScripts.setPlaybackRate(rate)) }
    func togglePictureInPicture() async throws { try await command(WebPlayerScripts.togglePictureInPicture) }

    func fetchArtwork(for track: NowPlaying) async throws -> Data? {
        guard let url = track.artworkURL else { return nil }
        return try await downloader.download(url)
    }

    // MARK: Private

    private func runningBridges() async -> [AppleScriptBridge] {
        guard isEnabled() else { return [] }
        var running: [AppleScriptBridge] = []
        for browser in browsers {
            guard await appChecker.isRunning(bundleIdentifier: browser.bundleIdentifier) else { continue }
            running.append(AppleScriptBridge(bundleIdentifier: browser.bundleIdentifier, runner: runner, appChecker: appChecker))
        }
        return running
    }

    /// Sends JavaScript to the tab last read; does nothing when no tab has been read yet.
    private func command(_ javaScript: String) async throws {
        guard isEnabled(), let tab = lastTab.withLock({ $0 }) else { return }
        let bridge = AppleScriptBridge(bundleIdentifier: tab.bundleIdentifier, runner: runner, appChecker: appChecker)
        do {
            _ = try await bridge.run(WebPlayerScripts.inTab(tab.tabID, javaScript: javaScript))
        } catch let error as ScriptError {
            throw WebPlayerScripts.classify(error)
        }
    }
}

/// AppleScript and page JavaScript for the web players. The JavaScript uses single quotes only so it can sit
/// inside an AppleScript string after `appleScriptString` escaping.
enum WebPlayerScripts {
    /// The page's main `<video>` and YouTube's player element, whose API keeps the site's own UI in sync.
    private static let prelude = """
    var v=document.querySelector('#movie_player video')||document.querySelector('video');\
    var p=document.getElementById('movie_player');
    """

    static func urlPrefixes(for source: MediaSource) -> [String] {
        switch source {
        case .youtube: ["https://www.youtube.com/watch", "https://youtube.com/watch"]
        case .youtubeMusic: ["https://music.youtube.com/"]
        case .spotify, .music: []
        }
    }

    // MARK: Reading

    /// Emits one `NowPlayingParser` line (with every extra field) or an empty string when no video is loaded.
    static func read(_ source: MediaSource) -> String {
        let music = source == .youtubeMusic
        return wrap("""
        if(!v||!(v.currentSrc||v.src))return '';\
        var s=String.fromCharCode(31);\
        var m=navigator.mediaSession&&navigator.mediaSession.metadata;\
        var state=v.ended?'stopped':(v.paused?'paused':'playing');\
        var title=(m&&m.title)||document.title.replace(/ - YouTube( Music)?$/,'');\
        var art='';\
        if(m&&m.artwork&&m.artwork.length){art=m.artwork[m.artwork.length-1].src;}\
        var vol=p&&p.getVolume?p.getVolume():v.volume*100;\
        if(v.muted||(p&&p.isMuted&&p.isMuted()))vol=0;\
        var liked='',rep='',nextTitle='',nextArtist='';\
        \(music ? musicExtras : "")\
        return [state,title,(m&&m.artist)||'',(m&&m.album)||'',isFinite(v.duration)?v.duration:0,v.currentTime,art,\
        liked,'',rep,Math.round(vol),v.playbackRate,nextTitle,nextArtist].join(s);
        """)
    }

    /// Like status, repeat mode and the next queue item from YouTube Music's player bar.
    private static let musicExtras = """
    var bar=document.querySelector('ytmusic-player-bar');\
    var lb=bar&&bar.querySelector('ytmusic-like-button-renderer');\
    if(lb){liked=String(lb.getAttribute('like-status')==='LIKE');}\
    var rm=bar&&bar.getAttribute('repeat-mode');\
    rep=rm==='ALL'?'all':(rm==='ONE'?'one':(rm==='NONE'?'off':''));\
    var items=Array.prototype.slice.call(document.querySelectorAll('ytmusic-player-queue ytmusic-player-queue-item'));\
    var i=items.findIndex(function(e){return e.hasAttribute('selected');});\
    if(i>=0&&items[i+1]){\
    var t=items[i+1].querySelector('.song-title'),b=items[i+1].querySelector('.byline');\
    nextTitle=t?t.textContent.trim():'';\
    nextArtist=b?b.textContent.split('•')[0].trim():'';}
    """

    // MARK: Commands

    static func playPause(_ source: MediaSource) -> String {
        switch source {
        case .youtubeMusic:
            wrap("var b=document.querySelector('#play-pause-button');if(b){b.click();}else if(v){v.paused?v.play():v.pause();}")
        default:
            wrap("if(p&&p.getPlayerState){p.getPlayerState()===1?p.pauseVideo():p.playVideo();}else if(v){v.paused?v.play():v.pause();}")
        }
    }

    static func next(_ source: MediaSource) -> String {
        switch source {
        case .youtubeMusic: wrap("var b=document.querySelector('ytmusic-player-bar .next-button');if(b)b.click();")
        default: wrap("if(p&&p.nextVideo){p.nextVideo();}else{var b=document.querySelector('.ytp-next-button');if(b)b.click();}")
        }
    }

    /// YouTube Music restarts the track itself past a few seconds; on YouTube a visible previous button means a
    /// playlist, otherwise the video restarts.
    static func previous(_ source: MediaSource) -> String {
        switch source {
        case .youtubeMusic: wrap("var b=document.querySelector('ytmusic-player-bar .previous-button');if(b)b.click();")
        default: wrap("""
            var b=document.querySelector('.ytp-prev-button');\
            if(b&&b.offsetParent&&v&&v.currentTime<3){b.click();}else if(p&&p.seekTo){p.seekTo(0,true);}else if(v){v.currentTime=0;}
            """)
        }
    }

    static func seek(to position: TimeInterval) -> String {
        let target = AppleScriptBridge.literal(position)
        return wrap("if(p&&p.seekTo){p.seekTo(\(target),true);}else if(v){v.currentTime=\(target);}")
    }

    static func setLiked(_ liked: Bool) -> String {
        wrap("""
        var lb=document.querySelector('ytmusic-player-bar ytmusic-like-button-renderer');\
        if(lb&&(lb.getAttribute('like-status')==='LIKE')!==\(liked)){\
        var b=lb.querySelector('#button-shape-like button')||lb.querySelector('.like');if(b)b.click();}
        """)
    }

    /// YouTube Music's repeat button cycles off → all → one; click until the bar reports the target.
    static func setRepeatMode(_ mode: RepeatMode) -> String {
        let target = switch mode {
        case .off: "NONE"
        case .all: "ALL"
        case .one: "ONE"
        }
        return wrap("""
        var bar=document.querySelector('ytmusic-player-bar');var b=bar&&bar.querySelector('.repeat');\
        for(var i=0;b&&i<3&&bar.getAttribute('repeat-mode')!=='\(target)';i++){b.click();}
        """)
    }

    static func setVolume(_ volume: Double) -> String {
        let percent = Int((min(max(volume, 0), 1) * NowPlayingParser.volumeScale).rounded())
        return wrap("""
        if(p&&p.setVolume){p.setVolume(\(percent));if(\(percent)>0&&p.unMute)p.unMute();}\
        else if(v){v.volume=\(percent)/100;v.muted=\(percent)===0;}
        """)
    }

    static func setPlaybackRate(_ rate: Double) -> String {
        let value = AppleScriptBridge.literal(rate)
        return wrap("if(p&&p.setPlaybackRate){p.setPlaybackRate(\(value));}else if(v){v.playbackRate=\(value);}")
    }

    /// Best effort: Chromium may refuse Picture in Picture without a user gesture in the page.
    static let togglePictureInPicture = wrap(
        "if(document.pictureInPictureElement){document.exitPictureInPicture();}else if(v){v.requestPictureInPicture();}"
    )

    // MARK: AppleScript

    /// Scans every tab whose URL starts with one of `urlPrefixes`; returns "tabID<US>reading" for the first playing
    /// tab, else the first tab with a video. Re-raises a JavaScript error only when no tab could be read.
    static func scan(urlPrefixes: [String], javaScript: String) -> String {
        let matches = urlPrefixes.map { "tabURL starts with \(appleScriptString($0))" }.joined(separator: " or ")
        return """
        set sep to character id 31
        set found to ""
        set failureMessage to ""
        set failureNumber to 0
        repeat with w in windows
        repeat with t in tabs of w
        set tabURL to ""
        try
        set tabURL to (URL of t) as text
        end try
        if \(matches) then
        try
        tell t to set reading to (execute javascript \(appleScriptString(javaScript)))
        if reading is not missing value and reading is not "" then
        set candidate to ((id of t) as text) & sep & reading
        if reading starts with "playing" then return candidate
        if found is "" then set found to candidate
        end if
        on error errorMessage number errorNumber
        if failureMessage is "" then
        set failureMessage to errorMessage
        set failureNumber to errorNumber
        end if
        end try
        end if
        end repeat
        end repeat
        if found is "" and failureMessage is not "" then error failureMessage number failureNumber
        return found
        """
    }

    static func inTab(_ tabID: String, javaScript: String) -> String {
        """
        repeat with w in windows
        repeat with t in tabs of w
        if ((id of t) as text) is \(appleScriptString(tabID)) then
        tell t to execute javascript \(appleScriptString(javaScript))
        return ""
        end if
        end repeat
        end repeat
        """
    }

    /// Splits the scan result into the tab id and the parser line.
    static func splitTab(_ text: String) -> (tabID: String, line: String)? {
        guard let index = text.firstIndex(of: NowPlayingParser.separator) else { return nil }
        let tabID = String(text[..<index])
        guard !tabID.isEmpty else { return nil }
        return (tabID, String(text[text.index(after: index)...]))
    }

    /// Chromium refuses `execute javascript` with a message naming JavaScript and Apple Events (localized, but
    /// "JavaScript" survives translation) unless the developer setting is on.
    static func classify(_ error: ScriptError) -> ScriptError {
        if case .executionFailed(_, let message) = error, message.localizedCaseInsensitiveContains("JavaScript") {
            return .javaScriptDisabled
        }
        return error
    }

    static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func wrap(_ body: String) -> String {
        "(function(){" + prelude + body + "})()"
    }
}

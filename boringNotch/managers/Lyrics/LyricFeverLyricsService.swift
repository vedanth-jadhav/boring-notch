//
//  LyricFeverLyricsService.swift
//  boringNotch
//
//  Provider flow ported from Lyric Fever.
//

import CryptoKit
import Foundation

final class LyricFeverLyricsService {
    static let shared = LyricFeverLyricsService()

    private let spotifyProvider = LyricFeverSpotifyLyricProvider()
    private let lrclibProvider = LyricFeverLRCLIBLyricProvider()
    private let netEaseProvider = LyricFeverNetEaseLyricProvider()

    // MARK: - Cache
    private var lyricsCache: [String: [BoringLyricLine]] = [:]
    private let cacheQueue = DispatchQueue(label: "com.boringnotch.lyrics-cache", qos: .userInitiated)

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSApplicationWillTerminateNotification"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.clearCache()
        }
    }

    deinit {
        clearCache()
    }

    private func cacheKey(title: String, artist: String, album: String, trackID: String?) -> String {
        [title, artist, album, trackID ?? ""]
            .joined(separator: "\u{1F}")
    }

    func clearCache() {
        cacheQueue.sync { lyricsCache.removeAll() }
    }

    func fetchLyrics(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        trackID: String? = nil,
        bundleIdentifier: String? = nil
    ) async -> [BoringLyricLine] {
        let cleanedTitle = Self.cleanedTrackTitle(title)
        let cleanedArtist = Self.cleanedArtist(artist)
        let cleanedAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTrackID = trackID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let durationMS = Int(max(0, duration * 1000))

        guard !cleanedTitle.isEmpty else { return [] }

        // Fast cache lookup (no await, no network)
        let cKey = cacheKey(title: cleanedTitle, artist: cleanedArtist, album: cleanedAlbum, trackID: cleanedTrackID)
        if let cached = cacheQueue.sync(execute: { lyricsCache[cKey] }), cached.count > 1 {
            return cached
        }

        // Fast parallel fetch across all applicable providers — take the first valid result.
        let providers = networkLyricProviders(trackID: cleanedTrackID, bundleIdentifier: bundleIdentifier)
        guard !providers.isEmpty else { return [] }

        let result: [BoringLyricLine]? = await withTaskGroup(of: [BoringLyricLine]?.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let lyrics = try await provider.fetchNetworkLyrics(
                            trackName: cleanedTitle,
                            trackID: cleanedTrackID ?? "",
                            currentlyPlayingArtist: cleanedArtist,
                            currentAlbumName: cleanedAlbum
                        )
                        let processed = lyrics.processed(withSongName: cleanedTitle, duration: durationMS)
                        let lines = processed.lyrics
                            .filter { !$0.words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            .map { BoringLyricLine(startTime: $0.startTimeMS / 1000, words: $0.words) }
                            .sorted { $0.startTime < $1.startTime }

                        return lines.count > 1 ? lines : nil
                    } catch is CancellationError {
                        return nil
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                if let lines = result {
                    group.cancelAll()
                    return lines
                }
            }

            return nil
        }

        if let lines = result {
            cacheQueue.sync { lyricsCache[cKey] = lines }
            return lines
        }

        return []
    }

    private func networkLyricProviders(trackID: String?, bundleIdentifier: String?) -> [LyricFeverLyricProvider] {
        var providers: [LyricFeverLyricProvider] = []

        if bundleIdentifier == "com.spotify.client",
           let trackID,
           trackID.count == 22,
           spotifyProvider.canFetch {
            providers.append(spotifyProvider)
        }

        providers.append(lrclibProvider)
        providers.append(netEaseProvider)
        return providers
    }

    static func cleanedTrackTitle(_ title: String) -> String {
        var cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers = ["official", "lyric", "audio", "video", "visualizer", "remaster"]

        if let range = cleaned.range(of: " - ") ?? cleaned.range(of: " \u{2013} ") ?? cleaned.range(of: " \u{2014} ") {
            let suffix = cleaned[range.upperBound...].lowercased()
            if markers.contains(where: suffix.localizedStandardContains) {
                cleaned = String(cleaned[..<range.lowerBound])
            }
        }

        while let open = cleaned.lastIndex(of: "("),
              let close = cleaned[open...].firstIndex(of: ")") {
            let fragment = cleaned[open...close].lowercased()
            guard markers.contains(where: fragment.localizedStandardContains) else { break }
            cleaned.removeSubrange(open...close)
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanedArtist(_ artist: String) -> String {
        artist
            .replacing(" & ", with: " ")
            .replacing(" feat. ", with: " ")
            .replacing(" ft. ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private protocol LyricFeverLyricProvider {
    var providerName: String { get }

    func fetchNetworkLyrics(
        trackName: String,
        trackID: String,
        currentlyPlayingArtist: String?,
        currentAlbumName: String?
    ) async throws -> LyricFeverNetworkFetchReturn
}

private struct LyricFeverNetworkFetchReturn {
    let lyrics: [LyricFeverLyricLine]
    let colorData: Int32?

    func processed(withSongName songName: String, duration: Int) -> LyricFeverNetworkFetchReturn {
        let filtered = lyrics.filter { !$0.words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard filtered.count > 1 else {
            return LyricFeverNetworkFetchReturn(lyrics: filtered, colorData: colorData)
        }

        let nowPlayingLine = LyricFeverLyricLine(startTime: Double(duration + 5000), words: "Now Playing: \(songName)")
        return LyricFeverNetworkFetchReturn(lyrics: filtered + [nowPlayingLine], colorData: colorData)
    }
}

private struct LyricFeverLyricLine: Decodable, Hashable {
    let startTimeMS: TimeInterval
    let words: String
    let id = UUID()

    enum CodingKeys: String, CodingKey {
        case startTimeMS = "startTimeMs"
        case words
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringValue = try? container.decode(String.self, forKey: .startTimeMS),
           let time = TimeInterval(stringValue) {
            startTimeMS = time
        } else {
            startTimeMS = try container.decode(TimeInterval.self, forKey: .startTimeMS)
        }
        words = try container.decode(String.self, forKey: .words)
    }

    init(startTime: TimeInterval, words: String) {
        startTimeMS = startTime
        self.words = words
    }
}

private final class LyricFeverLRCLIBLyricProvider: LyricFeverLyricProvider {
    let providerName = "LRCLIB Lyric Provider"

    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "Lyric Fever v3.3 (https://github.com/aviwad/LyricFever)"]
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    func fetchNetworkLyrics(
        trackName: String,
        trackID: String,
        currentlyPlayingArtist: String?,
        currentAlbumName: String?
    ) async throws -> LyricFeverNetworkFetchReturn {
        guard let currentlyPlayingArtist,
              let currentAlbumName,
              !currentlyPlayingArtist.isEmpty,
              !currentAlbumName.isEmpty else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        // Try exact match first
        if let exactURL = makeComponents(path: "/api/get", items: [
            URLQueryItem(name: "artist_name", value: currentlyPlayingArtist),
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "album_name", value: currentAlbumName)
        ]).url {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: URLRequest(url: exactURL))
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                let lrcLyrics = try decoder.decode(LyricFeverLRCLIBLyrics.self, from: data)
                if !lrcLyrics.lyrics.isEmpty {
                    return LyricFeverNetworkFetchReturn(lyrics: lrcLyrics.lyrics, colorData: nil)
                }
            }
        }

        // Fallback: search by track + artist (more lenient)
        guard let searchURL = makeComponents(path: "/api/search", items: [
            URLQueryItem(name: "artist_name", value: currentlyPlayingArtist),
            URLQueryItem(name: "track_name", value: trackName)
        ]).url else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        try Task.checkCancellation()
        let (searchData, searchResponse) = try await session.data(for: URLRequest(url: searchURL))
        guard (searchResponse as? HTTPURLResponse)?.statusCode == 200 else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        let searchResults = try decoder.decode([LyricFeverLRCLIBSearchResult].self, from: searchData)
        // Pick the best match by album name, or first result
        let best = searchResults.first { $0.albumName == currentAlbumName }
            ?? searchResults.first
        guard let best else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        // Fetch synced lyrics for the best match
        guard let lyricURL = makeComponents(path: "/api/get", items: [
            URLQueryItem(name: "id", value: String(best.id))
        ]).url else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        try Task.checkCancellation()
        let (lyricData, lyricResponse) = try await session.data(for: URLRequest(url: lyricURL))
        guard (lyricResponse as? HTTPURLResponse)?.statusCode == 200 else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        let lrcLyrics = try decoder.decode(LyricFeverLRCLIBLyrics.self, from: lyricData)
        return LyricFeverNetworkFetchReturn(lyrics: lrcLyrics.lyrics, colorData: nil)
    }

    private func makeComponents(path: String, items: [URLQueryItem]) -> URLComponents {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "lrclib.net"
        comps.path = path
        comps.queryItems = items
        return comps
    }
}

private final class LyricFeverNetEaseLyricProvider: LyricFeverLyricProvider {
    let providerName = "NetEase Lyric Provider"

    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        ]
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    func fetchNetworkLyrics(
        trackName: String,
        trackID: String,
        currentlyPlayingArtist: String?,
        currentAlbumName: String?
    ) async throws -> LyricFeverNetworkFetchReturn {
        guard let currentlyPlayingArtist,
              let currentAlbumName,
              !trackName.isEmpty else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        guard let searchURL = makeComponents(path: "/search", items: [
            URLQueryItem(
                name: "keywords",
                value: [trackName, currentlyPlayingArtist].filter { !$0.isEmpty }.joined(separator: " ")
            ),
            URLQueryItem(name: "limit", value: "1")
        ]).url else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        try Task.checkCancellation()
        let (searchData, searchResponse) = try await session.data(for: URLRequest(url: searchURL))
        guard (searchResponse as? HTTPURLResponse)?.statusCode == 200 else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        let neteaseSearch = try decoder.decode(LyricFeverNetEaseSearch.self, from: searchData)
        guard let neteaseResult = neteaseSearch.result.songs.first,
              let neteaseArtist = neteaseResult.artists.first else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        let conditions = [
            Self.similarity(trackName, neteaseResult.name) > 0.75,
            Self.similarity(currentlyPlayingArtist, neteaseArtist.name) > 0.75,
            Self.similarity(currentAlbumName, neteaseResult.album.name) > 0.75
        ]

        guard conditions.filter({ $0 }).count >= 2 else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        guard let lyricURL = makeComponents(path: "/lyric", items: [
            URLQueryItem(name: "id", value: String(neteaseResult.id))
        ]).url else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        try Task.checkCancellation()
        let (lyricsData, lyricsResponse) = try await session.data(for: URLRequest(url: lyricURL))
        guard (lyricsResponse as? HTTPURLResponse)?.statusCode == 200 else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        let neteaseLyrics = try decoder.decode(LyricFeverNetEaseLyrics.self, from: lyricsData)
        guard let neteaseLRCString = neteaseLyrics.lrc?.lyric else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        let parser = LyricFeverLyricsParser(lyrics: Self.unescapeHTMLEntities(in: neteaseLRCString))
        guard parser.lyrics.last?.startTimeMS != 0 else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        return LyricFeverNetworkFetchReturn(lyrics: parser.lyrics, colorData: nil)
    }

    private func makeComponents(path: String, items: [URLQueryItem]) -> URLComponents {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "neteasecloudmusicapi-ten-wine.vercel.app"
        comps.path = path
        comps.queryItems = items
        return comps
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let lhs = searchNormalized(lhs)
        let rhs = searchNormalized(rhs)

        guard !lhs.isEmpty, !rhs.isEmpty else { return lhs == rhs ? 1 : 0 }
        if lhs == rhs { return 1 }
        if lhs.localizedStandardContains(rhs) || rhs.localizedStandardContains(lhs) { return 0.86 }

        let distance = levenshtein(lhs, rhs)
        let longest = max(lhs.count, rhs.count)
        let editSimilarity = longest == 0 ? 1 : 1 - (Double(distance) / Double(longest))

        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        let union = lhsTokens.union(rhsTokens).count
        let tokenSimilarity = union == 0 ? 0 : Double(lhsTokens.intersection(rhsTokens).count) / Double(union)

        return max(editSimilarity, tokenSimilarity)
    }

    private static func searchNormalized(_ string: String) -> String {
        let folded = string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }

        return String(scalars)
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhs = Array(lhs)
        let rhs = Array(rhs)

        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)

        for (i, left) in lhs.enumerated() {
            current[0] = i + 1
            for (j, right) in rhs.enumerated() {
                current[j + 1] = min(
                    previous[j + 1] + 1,
                    current[j] + 1,
                    previous[j] + (left == right ? 0 : 1)
                )
            }
            swap(&previous, &current)
        }

        return previous[rhs.count]
    }

    private static func unescapeHTMLEntities(in text: String) -> String {
        text
            .replacing("&apos;", with: "'")
            .replacing("&quot;", with: "\"")
            .replacing("&amp;", with: "&")
            .replacing("&lt;", with: "<")
            .replacing("&gt;", with: ">")
            .replacing("&#39;", with: "'")
            .replacing("&#x27;", with: "'")
            .replacing("\\\n", with: "\n")
    }
}

private final class LyricFeverSpotifyLyricProvider: LyricFeverLyricProvider {
    let providerName = "Spotify Lyric Provider"

    private var storedAccessToken: LyricFeverAccessTokenJSON?
    private var accessToken: LyricFeverAccessTokenJSON? {
        get {
            if let token = storedAccessToken { return token }
            // Restore from UserDefaults for app relaunch persistence
            if let data = UserDefaults.standard.data(forKey: "spotifyLyricsToken"),
               let token = try? JSONDecoder().decode(LyricFeverAccessTokenJSON.self, from: data) {
                storedAccessToken = token
                return token
            }
            return nil
        }
        set {
            storedAccessToken = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "spotifyLyricsToken")
            } else {
                UserDefaults.standard.removeObject(forKey: "spotifyLyricsToken")
            }
        }
    }
    private let session: URLSession
    private let decoder = JSONDecoder()

    var canFetch: Bool {
        !spDcCookie.isEmpty
    }

    private var isAccessTokenAlive: Bool {
        guard let expiration = accessToken?.accessTokenExpirationTimestampMs else { return false }
        return expiration > Date().timeIntervalSince1970 * 1000
    }

    private var spDcCookie: String {
        UserDefaults.standard.string(forKey: "spDcCookie")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_6_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"
        ]
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    func fetchNetworkLyrics(
        trackName: String,
        trackID: String,
        currentlyPlayingArtist: String?,
        currentAlbumName: String?
    ) async throws -> LyricFeverNetworkFetchReturn {
        guard trackID.count == 22 else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        try await generateAccessTokenIfNeeded()
        guard let accessToken,
              let url = URL(string: "https://spclient.wg.spotify.com/color-lyrics/v2/track/\(trackID)?format=json&vocalRemoval=false") else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        var request = URLRequest(url: url)
        request.addValue("WebPlayer", forHTTPHeaderField: "app-platform")
        request.addValue("Bearer \(accessToken.accessToken)", forHTTPHeaderField: "authorization")

        try Task.checkCancellation()
        let (data, _) = try await session.data(for: request)
        guard !data.isEmpty, String(decoding: data, as: UTF8.self) != "too many requests" else {
            return LyricFeverNetworkFetchReturn(lyrics: [], colorData: nil)
        }

        let spotifyParent = try decoder.decode(LyricFeverSpotifyParent.self, from: data)
        return LyricFeverNetworkFetchReturn(
            lyrics: spotifyParent.lyrics.lyrics,
            colorData: Int32(spotifyParent.colors.background)
        )
    }

    private func generateAccessTokenIfNeeded() async throws {
        guard !isAccessTokenAlive else { return }

        guard let serverTimeURL = URL(string: "https://open.spotify.com/api/server-time") else {
            throw URLError(.badURL)
        }

        try Task.checkCancellation()
        let serverTimeData = try await session.data(for: URLRequest(url: serverTimeURL)).0
        let serverTime = try decoder.decode(LyricFeverSpotifyServerTime.self, from: serverTimeData).serverTime
        let currentUnix = Int(Date().timeIntervalSince1970)
        let counter = UInt64(currentUnix / 30)
        let secret = try await secretData()
        let hotp = try Self.hotp(secret: secret, counter: counter)

        let buildVer = "web-player_2025-06-10_1749524883369_eef30f4"
        let buildDate = "2025-06-10"
        guard let url = makeTokenURL(
            hotp: hotp,
            serverTime: serverTime,
            currentUnix: currentUnix,
            buildVer: buildVer,
            buildDate: buildDate
        ) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("sp_dc=\(spDcCookie)", forHTTPHeaderField: "Cookie")

        let data = try await session.data(for: request).0
        accessToken = try? decoder.decode(LyricFeverAccessTokenJSON.self, from: data)
    }

    private func secretData() async throws -> Data {
        guard let url = URL(string: "https://iloveyoulyricfever.github.io/myloveisasecret/mylove.json") else {
            throw URLError(.badURL)
        }

        let data = try await URLSession.shared.data(from: url).0
        let secret = try decoder.decode(LyricFeverSecretVersion.self, from: data).message
        let processed = secret.enumerated().map { index, byte in
            UInt8(byte ^ (index % 33 + 9))
        }
        let processedString = processed.map { String($0) }.joined()

        guard let secretBytes = processedString.data(using: .utf8) else {
            throw LyricFeverSpotifyAccessTokenError.badSecret
        }

        return secretBytes
    }

    private func makeTokenURL(
        hotp: String,
        serverTime: Int,
        currentUnix: Int,
        buildVer: String,
        buildDate: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "open.spotify.com"
        components.path = "/api/token"
        components.queryItems = [
            URLQueryItem(name: "reason", value: "init"),
            URLQueryItem(name: "productType", value: "web-player"),
            URLQueryItem(name: "totp", value: hotp),
            URLQueryItem(name: "totpServer", value: hotp),
            URLQueryItem(name: "totpVer", value: "5"),
            URLQueryItem(name: "sTime", value: String(serverTime)),
            URLQueryItem(name: "cTime", value: String(currentUnix)),
            URLQueryItem(name: "buildVer", value: "{\"\(buildVer)\"}"),
            URLQueryItem(name: "buildDate", value: "{\"\(buildDate)\"}")
        ]
        return components.url
    }

    private static func hotp(secret: Data, counter: UInt64) throws -> String {
        var counter = counter.bigEndian
        let counterData = withUnsafeBytes(of: &counter) { Data($0) }
        let code = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: SymmetricKey(data: secret))
        let data = Data(code)

        guard let last = data.last else {
            throw LyricFeverSpotifyAccessTokenError.badSecret
        }

        let offset = Int(last & 0x0f)
        guard data.indices.contains(offset + 3) else {
            throw LyricFeverSpotifyAccessTokenError.badSecret
        }

        let binary = (UInt32(data[offset] & 0x7f) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])

        return String(format: "%06d", binary % 1_000_000)
    }
}

private final class LyricFeverLyricsParser {
    var lyrics: [LyricFeverLyricLine] = []
    private var offset: TimeInterval = 0

    init(lyrics: String) {
        parse(lyrics: lyrics)
    }

    private func parse(lyrics: String) {
        let lines = lyrics
            .replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: .newlines)

        for line in lines {
            parseLine(line: line)
        }

        self.lyrics.sort { $0.startTimeMS < $1.startTimeMS }
    }

    private func parseLine(line: String) {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        if let offset = parseHeader(prefix: "offset", line: line) {
            self.offset = TimeInterval(offset) ?? 0
            return
        }

        guard !line.hasSuffix("]") else { return }
        lyrics += parseLyric(line: line)
    }

    private func parseHeader(prefix: String, line: String) -> String? {
        guard line.hasPrefix("[\(prefix):"), line.hasSuffix("]") else { return nil }
        let startIndex = line.index(line.startIndex, offsetBy: prefix.count + 2)
        let endIndex = line.index(line.endIndex, offsetBy: -1)
        return String(line[startIndex..<endIndex])
    }

    private func parseLyric(line: String) -> [LyricFeverLyricLine] {
        var remaining = line
        var timestamps: [TimeInterval] = []

        while remaining.hasPrefix("["),
              let closeIndex = remaining.firstIndex(of: "]") {
            let startIndex = remaining.index(after: remaining.startIndex)
            let timestamp = String(remaining[startIndex..<closeIndex])
            if timestamp.contains(":") {
                timestamps.append(timeInterval(from: timestamp))
            }
            remaining.removeSubrange(remaining.startIndex...closeIndex)
            remaining = remaining.trimmingCharacters(in: .whitespaces)
        }

        guard !timestamps.isEmpty, !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return timestamps.map {
            LyricFeverLyricLine(startTime: 1000 * ($0 + offset), words: remaining)
        }
    }

    private func timeInterval(from timestamp: String) -> TimeInterval {
        timestamp
            .components(separatedBy: ":")
            .reversed()
            .enumerated()
            .reduce(0) { partial, item in
                partial + ((TimeInterval(item.element) ?? 0) * pow(60, TimeInterval(item.offset)))
            }
    }
}

private struct LyricFeverLRCLIBLyrics: Decodable {
    let id: Int
    let name: String
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String
    let syncedLyrics: String
    let lyrics: [LyricFeverLyricLine]

    enum CodingKeys: CodingKey {
        case id
        case name
        case trackName
        case artistName
        case albumName
        case duration
        case instrumental
        case plainLyrics
        case syncedLyrics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        trackName = try container.decode(String.self, forKey: .trackName)
        artistName = try container.decode(String.self, forKey: .artistName)
        albumName = try container.decode(String.self, forKey: .albumName)
        duration = (try? container.decode(Double.self, forKey: .duration)) ?? 0
        instrumental = (try? container.decode(Bool.self, forKey: .instrumental)) ?? false

        if instrumental {
            plainLyrics = ""
            syncedLyrics = ""
            lyrics = []
        } else {
            plainLyrics = (try? container.decode(String.self, forKey: .plainLyrics)) ?? ""
            syncedLyrics = (try? container.decode(String.self, forKey: .syncedLyrics)) ?? ""
            lyrics = LyricFeverLyricsParser(lyrics: syncedLyrics).lyrics
        }
    }

}

/// Parsed from LRCLIB /api/search array items.
/// Lighter than full LyricFeverLRCLIBLyrics — just enough to get the id.
private struct LyricFeverLRCLIBSearchResult: Decodable {
    let id: Int
    let name: String
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double
    let instrumental: Bool
}

private struct LyricFeverNetEaseSearch: Decodable {
    let result: Result
    let code: Int?

    struct Result: Decodable {
        let songs: [Song]
        let songCount: Int?

        struct Song: Decodable {
            let name: String
            let id: Int
            let duration: Int?
            let album: Album
            let artists: [Artist]
        }

        struct Album: Decodable {
            let name: String
        }

        struct Artist: Decodable {
            let name: String
        }
    }
}

private struct LyricFeverNetEaseLyrics: Decodable {
    let lrc: Lyric?
    let klyric: Lyric?
    let tlyric: Lyric?
    let lyricUser: User?
    let yrc: Lyric?

    struct User: Decodable {
        let nickname: String?
    }

    struct Lyric: Decodable {
        let lyric: String?
    }
}

private struct LyricFeverSpotifyLyrics: Decodable {
    let downloadDate: Date
    let language: String
    let lyrics: [LyricFeverLyricLine]

    enum CodingKeys: String, CodingKey {
        case lines
        case language
        case syncType
    }

    init(from decoder: Decoder) throws {
        downloadDate = Date()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = (try? container.decode(String.self, forKey: .language)) ?? ""
        if let syncType = try? container.decode(String.self, forKey: .syncType),
           syncType == "LINE_SYNCED",
           let lyrics = try? container.decode([LyricFeverLyricLine].self, forKey: .lines) {
            self.lyrics = lyrics
        } else {
            lyrics = []
        }
    }
}

private struct LyricFeverSpotifyParent: Decodable {
    let lyrics: LyricFeverSpotifyLyrics
    let colors: LyricFeverSpotifyColorData
}

private struct LyricFeverSpotifyColorData: Decodable {
    let background: Int
    let text: Int
    let highlightText: Int
}

private struct LyricFeverAccessTokenJSON: Codable {
    let accessToken: String
    let accessTokenExpirationTimestampMs: TimeInterval
    let isAnonymous: Bool
}

private struct LyricFeverSpotifyServerTime: Decodable {
    let serverTime: Int
}

private struct LyricFeverSecretVersion: Decodable {
    let latestSecretVersion: Int
    let message: [Int]
}

private enum LyricFeverSpotifyAccessTokenError: Error {
    case badSecret
}

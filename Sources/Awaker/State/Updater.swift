import AppKit
import AwakerCore
import Observation

/// Finds new releases on GitHub and installs them in place.
///
/// Releases are published by `.github/workflows/release.yml` when the VERSION file changes.
/// The app is signed ad hoc, so there is no signature to verify: the update is trusted because it
/// comes over HTTPS from this repository's releases, and its bundle identifier is checked before the swap.
@MainActor
@Observable
final class Updater {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case downloading(AppRelease)
        case failed(String)
    }

    static let repository = "grignolalouis/Awaker"

    private(set) var status: Status = .idle

    @ObservationIgnored private var timer: Timer?
    /// Versions already announced by a notification, so each one is announced once.
    @ObservationIgnored private var announced: Set<String> = []
    @ObservationIgnored private let isPreview: Bool
    /// Called just before the app quits to be replaced, so a running session can be resumed afterwards.
    @ObservationIgnored var willRelaunch: () -> Void = {}

    private let checkInterval: TimeInterval = 24 * 3_600

    init(isPreview: Bool = false) {
        self.isPreview = isPreview
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var availableRelease: AppRelease? {
        if case .available(let release) = status { return release }
        return nil
    }

    /// Call once at launch: checks now, then once a day.
    func start() {
        guard !isPreview else { return }
        let timer = Timer(timeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(announce: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await check(announce: true) }
    }

    /// Asks GitHub for the latest release. `announce` posts a notification when one is found
    /// (for the background checks; a check the user asked for shows its result in place).
    func check(announce: Bool = false) async {
        guard !isPreview, status != .checking else { return }
        if case .downloading = status { return }
        let previous = status
        status = .checking
        do {
            // URLSession follows the redirect; the final address carries the tag.
            let page = URL(string: "https://github.com/\(Self.repository)/releases/latest")!
            let (_, response) = try await URLSession.shared.data(from: page)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let landed = response.url else {
                throw UpdateError("GitHub n'a pas répondu comme prévu.")
            }
            // No tag in the final address: the repository has no release yet.
            guard let release = AppRelease(latestReleasePage: landed, repository: Self.repository),
                  release.isNewer(than: currentVersion) else {
                status = .upToDate
                return
            }
            status = .available(release)
            if announce && !announced.contains(release.version) {
                announced.insert(release.version)
                Notifier.post("Awaker \(release.version) est disponible", "Ouvre les Réglages d'Awaker pour l'installer.")
            }
        } catch {
            // A failed check must not hide a release found earlier, nor pass for "up to date".
            if case .available = previous {
                status = previous
            } else {
                status = .failed("Vérification impossible : \(error.localizedDescription)")
            }
        }
    }

    /// Downloads the release, swaps the app bundle and relaunches. A running session resumes after the relaunch.
    func install(_ release: AppRelease) async {
        guard !isPreview else { return }
        status = .downloading(release)
        do {
            let staged = try await stage(release)
            try relaunch(replacingWith: staged)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: Installation

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Downloads the DMG and copies the app out of it, into a folder on the same volume as the installed app
    /// so the final swap is a rename, not a copy.
    private func stage(_ release: AppRelease) async throws -> URL {
        let destination = Bundle.main.bundleURL
        let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                 appropriateFor: destination, create: true)
        do {
            let mount = folder.appendingPathComponent("mount")
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            let (downloaded, _) = try await URLSession.shared.download(from: release.downloadURL)
            let dmg = folder.appendingPathComponent("Awaker.dmg")
            try FileManager.default.moveItem(at: downloaded, to: dmg)

            let staged = folder.appendingPathComponent("Awaker.app")
            try await Task.detached(priority: .userInitiated) {
                try Self.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
                defer { Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
                // ditto keeps the bundle's signature and attributes intact.
                try Self.run("/usr/bin/ditto", [mount.appendingPathComponent("Awaker.app").path, staged.path])
            }.value
            guard Bundle(url: staged)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateError("Le fichier téléchargé n'est pas Awaker.")
            }
            return staged
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Hands the swap to a small shell script that waits for this process to exit, then quits.
    /// The installed app is moved aside, never deleted, until the new one is in place: any failure puts it back.
    private func relaunch(replacingWith staged: URL) throws {
        let destination = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
            throw UpdateError("Awaker ne peut pas se remplacer ici. Déplace-le dans le dossier Applications.")
        }
        // $1: installed app, $2: new app, $3: staging folder to clean up.
        let script = """
        while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done
        if /bin/mv "$1" "$1.old" && /bin/mv "$2" "$1"; then /bin/rm -rf "$1.old"; else /bin/mv "$1.old" "$1" 2>/dev/null; fi
        /bin/rm -rf "$3"
        /usr/bin/open "$1"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "awaker-update", destination.path, staged.path, staged.deletingLastPathComponent().path]
        try process.run()
        willRelaunch()
        NSApp.terminate(nil)
    }

    private nonisolated static func run(_ executable: String, _ arguments: [String]) throws {
        guard Shell.run(executable, arguments).succeeded else {
            throw UpdateError("L'installation a échoué (\(URL(fileURLWithPath: executable).lastPathComponent)).")
        }
    }
}

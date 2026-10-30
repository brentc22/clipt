import Foundation
import CliptCore
import Security

func updateTests() {
let updateTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("clipt-update-tests-\(UUID().uuidString)").resolvingSymlinksInPath()
defer { try? FileManager.default.removeItem(at: updateTmp) }
print("Updates")

T.test("versions: tags parse and compare numerically") {
    T.equal(AppVersion("v0.4.0")?.description, "0.4.0")
    T.equal(AppVersion("0.4")?.description, "0.4.0", "missing parts count as 0:")
    T.expect(AppVersion("1.10.0")! > AppVersion("1.9.9")!, "1.10.0 > 1.9.9")
    T.expect(AppVersion("0.5.0")! > AppVersion("0.4.9")!, "0.5.0 > 0.4.9")
    T.expect(AppVersion("0.4.0") == AppVersion("v0.4"), "0.4.0 == v0.4")
    T.equal(AppVersion("2.0.0-beta.1")?.description, "2.0.0", "pre-release suffix dropped:")
}

T.test("versions: what isn't a version is refused") {
    T.expect(AppVersion("latest") == nil, "latest")
    T.expect(AppVersion("1.2.3.4") == nil, "four parts")
    T.expect(AppVersion("1..2") == nil, "empty part")
    T.expect(AppVersion("") == nil, "empty")
}

func releaseJSON(tag: String, prerelease: Bool = false, assets: [String] = ["Clipt.zip"]) -> Data {
    let list = assets.map { #"{"name":"\#($0)","browser_download_url":"https://github.com/brentc22/clipt/releases/download/v0.5.0/\#($0)"}"# }
    return Data(#"""
    {"tag_name":"\#(tag)","html_url":"https://github.com/brentc22/clipt/releases/tag/\#(tag)",
     "body":"- New icon","draft":false,"prerelease":\#(prerelease),"assets":[\#(list.joined(separator: ","))],
     "author":{"login":"brentc22"}}
    """#.utf8)
}

T.test("release: decodes GitHub's releases/latest and finds the zip") {
    let release = try Release.decode(releaseJSON(tag: "v0.5.0", assets: ["checksums.txt", "Clipt.zip"]))
    T.equal(release.version, AppVersion("0.5.0"))
    T.equal(release.body, "- New icon")
    T.equal(release.zipURL(appName: "Clipt")?.lastPathComponent, "Clipt.zip")
    T.expect(release.zipURL(appName: "Stash") == nil, "another app's zip isn't ours")
}

T.test("update policy: only newer, unskipped, final releases") {
    let current = AppVersion("0.4.0")!
    let newer = try Release.decode(releaseJSON(tag: "v0.5.0"))
    let same = try Release.decode(releaseJSON(tag: "v0.4.0"))
    let beta = try Release.decode(releaseJSON(tag: "v0.6.0", prerelease: true))
    T.expect(UpdatePolicy.shouldOffer(newer, current: current, skipped: nil, userInitiated: false), "newer")
    T.expect(!UpdatePolicy.shouldOffer(same, current: current, skipped: nil, userInitiated: true), "same version")
    T.expect(!UpdatePolicy.shouldOffer(beta, current: current, skipped: nil, userInitiated: true), "prerelease")
    T.expect(!UpdatePolicy.shouldOffer(newer, current: current, skipped: "0.5.0", userInitiated: false),
             "a skipped version stays quiet on automatic checks")
    T.expect(UpdatePolicy.shouldOffer(newer, current: current, skipped: "0.5.0", userInitiated: true),
             "but shows when you check yourself")
    T.expect(UpdatePolicy.shouldOffer(newer, current: current, skipped: "0.4.5", userInitiated: false),
             "an older skipped version doesn't hide a newer one")
}

T.test("update policy: only a check you asked for shows an alert") {
    let current = AppVersion("0.4.0")!
    let newer = try Release.decode(releaseJSON(tag: "v0.5.0"))
    let same = try Release.decode(releaseJSON(tag: "v0.4.0"))
    T.equal(UpdatePolicy.outcome(newer, current: current, skipped: nil, userInitiated: false), .surface)
    T.equal(UpdatePolicy.outcome(newer, current: current, skipped: "0.5.0", userInitiated: false), .quiet)
    T.equal(UpdatePolicy.outcome(same, current: current, skipped: nil, userInitiated: false), .quiet)
    T.equal(UpdatePolicy.outcome(newer, current: current, skipped: nil, userInitiated: true), .offer)
    T.equal(UpdatePolicy.outcome(newer, current: current, skipped: "0.5.0", userInitiated: true), .offer)
    T.equal(UpdatePolicy.outcome(same, current: current, skipped: nil, userInitiated: true), .upToDate)
}

T.test("update policy: at most one check a day") {
    let now = Date()
    T.expect(UpdatePolicy.isCheckDue(lastCheck: nil, now: now), "never checked")
    T.expect(!UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-3600), now: now), "an hour ago")
    T.expect(UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now), "25 hours ago")
}

T.test("versions compare numerically") { T.expect(AppVersion("0.10.0")! > AppVersion("0.9.1")!, "0.10 > 0.9") }

/// The designated requirement of any signed code, ad-hoc included (the installer itself
/// only ever uses the running app's certificate-based one).
func anyRequirement(of app: URL) -> SecRequirement? {
    var code: SecStaticCode?
    var req: SecRequirement?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
          SecCodeCopyDesignatedRequirement(code, [], &req) == errSecSuccess else { return nil }
    return req
}

T.test("requirements: built from text, certificate-based only for the running app") {
    let text = "identifier \"com.brentc22.Clipt\" and certificate leaf = H\"0123456789abcdef0123456789abcdef01234567\""
    T.expect(UpdateInstaller.requirement(fromText: text) != nil, "valid text")
    T.expect(UpdateInstaller.requirement(fromText: "garbage ((") == nil, "invalid text")
    // The test binary is ad-hoc or unsigned, so there is no certificate to compare against.
    T.expect(UpdateInstaller.runningRequirement() == nil, "an ad-hoc running copy has no usable requirement")
}

T.test("download URLs: only https on GitHub's hosts") {
    func ok(_ s: String) -> Bool { UpdateInstaller_isTrusted(s) }
    T.expect(ok("https://github.com/brentc22/clipt/releases/download/v1/Clipt.zip"), "github.com")
    T.expect(ok("https://objects.githubusercontent.com/x/Clipt.zip"), "objects host")
    T.expect(!ok("http://github.com/brentc22/clipt/releases/download/v1/Clipt.zip"), "plain http")
    T.expect(!ok("https://evil.example.com/Clipt.zip"), "another host")
    T.expect(!ok("https://github.com.evil.example.com/Clipt.zip"), "look-alike host")
    T.expect(!ok("file:///tmp/Clipt.zip"), "file URL")
}

func UpdateInstaller_isTrusted(_ s: String) -> Bool {
    let json = Data(#"{"tag_name":"v1.0.0","html_url":"https://github.com/brentc22/clipt","body":null,"draft":false,"prerelease":false,"assets":[{"name":"Clipt.zip","browser_download_url":"\#(s)"}]}"#.utf8)
    return (try? Release.decode(json))?.zipURL(appName: "Clipt") != nil
}

/// Builds an ad-hoc signed fake app and zips it the way a release zip is made.
func fakeRelease(in dir: URL, bundleID: String = "com.brentc22.Clipt", version: String = "0.5.0",
                 tamper: Bool = false, appName: String = "Clipt.app") throws -> (zip: URL, app: URL) {
    let fm = FileManager.default
    try? fm.removeItem(at: dir)
    let app = dir.appendingPathComponent("build").appendingPathComponent(appName)
    try fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    try fm.copyItem(atPath: "/usr/bin/true", toPath: app.appendingPathComponent("Contents/MacOS/Clipt").path)
    let info: NSDictionary = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version,
                              "CFBundleExecutable": "Clipt", "CFBundlePackageType": "APPL"]
    info.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
    try UpdateInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
    if tamper {
        try Data("tampered".utf8).write(to: app.appendingPathComponent("Contents/MacOS/Clipt"))
    }
    let zip = dir.appendingPathComponent("Clipt.zip")
    try UpdateInstaller.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
    return (zip, app)
}

let updateDir = updateTmp.appendingPathComponent("update")
let bundleID = "com.brentc22.Clipt"

func prepareError(requirement: SecRequirement? = nil, _ release: () throws -> (zip: URL, app: URL)) -> UpdateError? {
    do {
        let built = try release()
        guard let required = requirement ?? anyRequirement(of: built.app) else { return .command("requirement", status: -1) }
        _ = try UpdateInstaller.prepare(zip: built.zip, in: updateDir, bundleID: bundleID,
                                        version: AppVersion("0.5.0")!, requiredRequirement: required)
        return nil
    } catch { return error as? UpdateError }
}

T.test("installer: a signed app with the right id, version and identity is accepted") {
    let built = try fakeRelease(in: updateDir)
    guard let required = anyRequirement(of: built.app) else { T.expect(false, "no requirement"); return }
    let app = try UpdateInstaller.prepare(zip: built.zip, in: updateDir, bundleID: bundleID,
                                          version: AppVersion("0.5.0")!, requiredRequirement: required)
    T.equal(app.lastPathComponent, "Clipt.app")
}

T.test("installer: another app, another version or a broken signature is refused") {
    T.equal(prepareError { try fakeRelease(in: updateDir, bundleID: "com.example.Evil") },
            .wrongApp(bundleID: "com.example.Evil"))
    T.equal(prepareError { try fakeRelease(in: updateDir, version: "0.4.9") },
            .wrongVersion(found: "0.4.9", expected: "0.5.0"))
    let anyIdentity = UpdateInstaller.requirement(fromText: "identifier \"\(bundleID)\" and certificate leaf = H\"0123456789abcdef0123456789abcdef01234567\"")!
    let tampered = prepareError(requirement: anyIdentity) { try fakeRelease(in: updateDir, tamper: true) }
    if case .invalidSignature = tampered { T.expect(true, "") } else { T.expect(false, "got \(String(describing: tampered))") }
}

T.test("installer: an app signed by a different identity is refused") {
    let other = UpdateInstaller.requirement(fromText: "identifier \"\(bundleID)\" and certificate leaf = H\"0123456789abcdef0123456789abcdef01234567\"")!
    T.equal(prepareError(requirement: other) { try fakeRelease(in: updateDir) },
            .invalidSignature("signed by a different identity"))
}

/// Zips `names` (each a directory, or a symlink with `links[name]` as target) as one archive.
func zipOf(_ dirName: String, entries: [String: String?]) throws -> URL {
    let fm = FileManager.default
    let dir = updateTmp.appendingPathComponent(dirName)
    try? fm.removeItem(at: dir)
    let root = dir.appendingPathComponent("root")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    for (name, link) in entries {
        if let link {
            try fm.createSymbolicLink(atPath: root.appendingPathComponent(name).path, withDestinationPath: link)
        } else {
            try fm.createDirectory(at: root.appendingPathComponent(name).appendingPathComponent("Contents"),
                                   withIntermediateDirectories: true)
        }
    }
    let zip = dir.appendingPathComponent("a.zip")
    let args = ["-c", "-k", root.path, zip.path]
    try UpdateInstaller.run("/usr/bin/ditto", args)
    return zip
}

func prepareArchiveError(_ zip: URL) -> UpdateError? {
    let required = UpdateInstaller.requirement(fromText: "identifier \"\(bundleID)\" and certificate leaf = H\"0123456789abcdef0123456789abcdef01234567\"")!
    do {
        _ = try UpdateInstaller.prepare(zip: zip, in: updateTmp.appendingPathComponent("arch"), bundleID: bundleID,
                                        version: AppVersion("0.5.0")!, requiredRequirement: required)
        return nil
    } catch { return error as? UpdateError }
}

T.test("installer: the archive must hold exactly one real directory named Clipt.app") {
    T.equal(prepareArchiveError(try zipOf("a1", entries: ["Other.app": nil])), .noAppInArchive)
    T.equal(prepareArchiveError(try zipOf("a2", entries: ["Clipt.app": nil, "Other.app": nil])), .noAppInArchive)
    T.equal(prepareArchiveError(try zipOf("a3", entries: ["Clipt.app": "/Applications/Safari.app"])), .noAppInArchive)
    T.equal(prepareArchiveError(try zipOf("a4", entries: ["stuff.txt": "/etc/hosts"])), .noAppInArchive)
}

T.test("installer: an app whose name carries a forged requirement line is refused (regression)") {
    let legit = try fakeRelease(in: updateDir.appendingPathComponent("legit"))
    guard let required = anyRequirement(of: legit.app), let text = UpdateInstaller.requirementText(required) else {
        T.expect(false, "no requirement"); return
    }
    let evilName = "X\ndesignated => \(text)\nY.app"
    let evil = prepareError(requirement: required) { try fakeRelease(in: updateDir.appendingPathComponent("evil"), appName: evilName) }
    T.equal(evil, .noAppInArchive)
    // And with the name check out of the picture, validation is Security.framework's call:
    let other = UpdateInstaller.requirement(fromText: "identifier \"\(bundleID)\" and certificate leaf = H\"0123456789abcdef0123456789abcdef01234567\"")!
    let forged = prepareError(requirement: other) { try fakeRelease(in: updateDir.appendingPathComponent("forged")) }
    T.equal(forged, .invalidSignature("signed by a different identity"))
}

T.test("installer: a failed swap restores the old app") {
    let fm = FileManager.default
    let dir = updateTmp.appendingPathComponent("failswap")
    try? fm.removeItem(at: dir)
    let installed = dir.appendingPathComponent("Applications/Clipt.app")
    let missing = dir.appendingPathComponent("work/Clipt.app")   // never created: the second mv fails
    try fm.createDirectory(at: installed, withIntermediateDirectories: true)
    try fm.createDirectory(at: missing.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("old".utf8).write(to: installed.appendingPathComponent("marker"))
    let finished = Process()
    finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try finished.run(); finished.waitUntilExit()
    let script = UpdateInstaller.swapScript(pid: finished.processIdentifier, newApp: missing,
                                            destination: installed, relaunch: false)
    do { try UpdateInstaller.run("/bin/sh", ["-c", script]); T.expect(false, "the script should fail") } catch {}
    T.equal(try String(contentsOf: installed.appendingPathComponent("marker"), encoding: .utf8), "old")
    let real = UpdateInstaller.swapScript(pid: 1, newApp: missing, destination: installed)
    T.expect(real.components(separatedBy: "open '").count - 1 == 3, "relaunches after success and after both failures")
    T.expect(!real.contains("--after-update"), "no argument nobody reads")
}

T.test("installer: the swap script replaces the app once the old process is gone") {
    let fm = FileManager.default
    let dir = updateTmp.appendingPathComponent("swap it's here")  // a quote in the path, on purpose
    try? fm.removeItem(at: dir)
    let installed = dir.appendingPathComponent("Applications/Clipt.app")
    let fresh = dir.appendingPathComponent("work/Clipt.app")
    try fm.createDirectory(at: installed, withIntermediateDirectories: true)
    try fm.createDirectory(at: fresh, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: installed.appendingPathComponent("marker"))
    try Data("new".utf8).write(to: fresh.appendingPathComponent("marker"))

    let finished = Process()
    finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try finished.run()
    finished.waitUntilExit()
    let script = UpdateInstaller.swapScript(pid: finished.processIdentifier, newApp: fresh,
                                            destination: installed, relaunch: false)
    try UpdateInstaller.run("/bin/sh", ["-c", script])

    T.equal(try String(contentsOf: installed.appendingPathComponent("marker"), encoding: .utf8), "new")
    T.expect(!fm.fileExists(atPath: fresh.path), "new copy moved, not copied")
    T.expect(!fm.fileExists(atPath: dir.appendingPathComponent("work/previous.app").path), "backup cleaned up")
}
}

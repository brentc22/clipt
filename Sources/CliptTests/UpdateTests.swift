import Foundation
import CliptCore

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
    let list = assets.map { #"{"name":"\#($0)","browser_download_url":"https://example.com/\#($0)"}"# }
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

T.test("update policy: at most one check a day") {
    let now = Date()
    T.expect(UpdatePolicy.isCheckDue(lastCheck: nil, now: now), "never checked")
    T.expect(!UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-3600), now: now), "an hour ago")
    T.expect(UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now), "25 hours ago")
}

T.test("versions compare numerically") { T.expect(AppVersion("0.10.0")! > AppVersion("0.9.1")!, "0.10 > 0.9") }

T.test("designated requirement is parsed from codesign output") {
    let out = "Executable=/Applications/Clipt.app/Contents/MacOS/Clipt\ndesignated => identifier \"com.brentc22.Clipt\" and certificate leaf = H\"ab12\"\n"
    T.equal(UpdateInstaller.designatedRequirement(fromCodesignOutput: out),
            "identifier \"com.brentc22.Clipt\" and certificate leaf = H\"ab12\"")
    let commented = "Executable=/x\n# designated => identifier \"com.brentc22.Clipt\" and certificate leaf = H\"ab12\"\n"
    T.equal(UpdateInstaller.designatedRequirement(fromCodesignOutput: commented),
            "identifier \"com.brentc22.Clipt\" and certificate leaf = H\"ab12\"", "the `# designated =>` form:")
    T.equal(UpdateInstaller.designatedRequirement(fromCodesignOutput: "garbage"), nil)
    T.equal(UpdateInstaller.designatedRequirement(fromCodesignOutput: "designated => \n"), nil)
}

/// Builds an ad-hoc signed fake app and zips it the way a release zip is made.
func fakeRelease(in dir: URL, bundleID: String = "com.brentc22.Clipt", version: String = "0.5.0",
                 tamper: Bool = false) throws -> (zip: URL, app: URL) {
    let fm = FileManager.default
    try? fm.removeItem(at: dir)
    let app = dir.appendingPathComponent("build/Clipt.app")
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

func prepareError(requirement: String? = nil, _ release: () throws -> (zip: URL, app: URL)) -> UpdateError? {
    do {
        let built = try release()
        let required = requirement ?? UpdateInstaller.designatedRequirement(of: built.app) ?? "none"
        _ = try UpdateInstaller.prepare(zip: built.zip, in: updateDir, bundleID: bundleID,
                                        version: AppVersion("0.5.0")!, requiredRequirement: required)
        return nil
    } catch { return error as? UpdateError }
}

T.test("installer: a signed app with the right id, version and identity is accepted") {
    let built = try fakeRelease(in: updateDir)
    let required = UpdateInstaller.designatedRequirement(of: built.app)
    T.expect(required != nil, "the fake app has a designated requirement")
    let app = try UpdateInstaller.prepare(zip: built.zip, in: updateDir, bundleID: bundleID,
                                          version: AppVersion("0.5.0")!, requiredRequirement: required ?? "")
    T.equal(app.lastPathComponent, "Clipt.app")
}

T.test("installer: another app, another version or a broken signature is refused") {
    T.equal(prepareError { try fakeRelease(in: updateDir, bundleID: "com.example.Evil") },
            .wrongApp(bundleID: "com.example.Evil"))
    T.equal(prepareError { try fakeRelease(in: updateDir, version: "0.4.9") },
            .wrongVersion(found: "0.4.9", expected: "0.5.0"))
    let tampered = prepareError { try fakeRelease(in: updateDir, tamper: true) }
    if case .invalidSignature = tampered { T.expect(true, "") } else { T.expect(false, "got \(String(describing: tampered))") }
}

T.test("installer: an app signed by a different identity is refused") {
    let other = prepareError(requirement: "identifier \"\(bundleID)\" and certificate leaf = H\"00\"") {
        try fakeRelease(in: updateDir)
    }
    T.equal(other, .invalidSignature("signed by a different identity"))
}

T.test("installer: a missing app in the archive is refused") {
    let fm = FileManager.default
    let dir = updateTmp.appendingPathComponent("empty")
    try? fm.removeItem(at: dir)
    try fm.createDirectory(at: dir.appendingPathComponent("stuff"), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: dir.appendingPathComponent("stuff/readme.txt"))
    let zip = dir.appendingPathComponent("Clipt.zip")
    try UpdateInstaller.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", dir.appendingPathComponent("stuff").path, zip.path])
    do {
        _ = try UpdateInstaller.prepare(zip: zip, in: dir, bundleID: bundleID, version: AppVersion("0.5.0")!,
                                        requiredRequirement: "x")
        T.expect(false, "should have thrown")
    } catch { T.equal(error as? UpdateError, .noAppInArchive) }
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
    T.expect(UpdateInstaller.swapScript(pid: 1, newApp: fresh, destination: installed)
                .contains("--args --after-update"), "relaunch says an update just happened")
}
}

//
//  AppsSettingsRevampTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import AppKit
import XCTest
@testable import Sapphire

final class AppsSettingsRevampTests: XCTestCase {
    func testSystemAppSymlinkResolvesIntoProtectedSystemRoot() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("InstalledAppDiscovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let systemRoot = root.appendingPathComponent("System", isDirectory: true)
        let safariURL = systemRoot
            .appendingPathComponent("Cryptexes/App/System/Applications/Safari.app", isDirectory: true)
        let applicationsURL = root.appendingPathComponent("Applications", isDirectory: true)
        let safariLinkURL = applicationsURL.appendingPathComponent("Safari.app")
        try fileManager.createDirectory(at: safariURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: applicationsURL, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: safariLinkURL, withDestinationURL: safariURL)

        XCTAssertEqual(
            InstalledAppDiscoveryPolicy.applicationURL(
                for: safariLinkURL,
                isDirectory: true,
                isSymbolicLink: true,
                protectedSystemRoot: systemRoot
            ),
            safariURL.standardizedFileURL
        )
    }

    func testNonSystemAppSymlinkRemainsExcluded() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("InstalledAppDiscovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let systemRoot = root.appendingPathComponent("System", isDirectory: true)
        let externalAppURL = root.appendingPathComponent("External/Linked.app", isDirectory: true)
        let linkURL = root.appendingPathComponent("Applications/Linked.app")
        try fileManager.createDirectory(at: systemRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: externalAppURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: externalAppURL)

        XCTAssertNil(
            InstalledAppDiscoveryPolicy.applicationURL(
                for: linkURL,
                isDirectory: true,
                isSymbolicLink: true,
                protectedSystemRoot: systemRoot
            )
        )
    }

    func testVersionOrderingUsesNumericComponents() {
        XCTAssertEqual(AppVersionOrdering.compare("1.10", "1.9"), .orderedDescending)
        XCTAssertEqual(AppVersionOrdering.compare("0.11", "0.9"), .orderedDescending)
        XCTAssertFalse(AppVersionOrdering.isNewer("0.9", than: "0.11"))
        XCTAssertEqual(AppVersionOrdering.compare("2.73", "2.9"), .orderedDescending)
        XCTAssertEqual(AppVersionOrdering.compare("2.0", "1.99.99"), .orderedDescending)
        XCTAssertEqual(AppVersionOrdering.compare("v3.12.0", "3.11.9"), .orderedDescending)
        XCTAssertEqual(AppVersionOrdering.compare("1.2.0", "1.2"), .orderedSame)
        XCTAssertEqual(
            AppVersionOrdering.compare("1.999999999999999999999999999999", "1.10"),
            .orderedDescending
        )
    }

    func testOlderVendorVersionCannotBecomeAnAvailableUpdate() {
        let pageURL = URL(string: "https://example.test/releases/0.9")
        let reported = InstalledAppUpdateEntry.Status.updateAvailable(
            latestVersion: "0.9",
            downloadURL: nil,
            pageURL: pageURL,
            releaseNotes: nil,
            releaseNotesURL: pageURL
        )

        XCTAssertEqual(
            InstalledAppUpdatesChecker.validatedStatus(reported, currentVersion: "0.11"),
            .upToDate(latestVersion: "0.11")
        )
    }

    func testResponseCapturedBeforeInPlaceUpdateCannotRemainAvailable() {
        let staleResponse = InstalledAppUpdateEntry.Status.updateAvailable(
            latestVersion: "0.11",
            downloadURL: nil,
            pageURL: nil,
            releaseNotes: nil,
            releaseNotesURL: nil
        )

        XCTAssertEqual(
            InstalledAppUpdatesChecker.validatedStatus(
                staleResponse,
                currentVersion: "0.11",
                demoteEquivalentUpdate: true
            ),
            .upToDate(latestVersion: "0.11")
        )
    }

    func testHomebrewReceiptCannotOverrideInstalledVersion() {
        XCTAssertFalse(
            HomebrewUpdateDecision.shouldOffer(
                latestVersion: "0.9",
                currentVersion: "0.11",
                receiptIsOutdated: true
            )
        )
        XCTAssertFalse(
            HomebrewUpdateDecision.shouldOffer(
                latestVersion: "0.11",
                currentVersion: "0.11",
                receiptIsOutdated: true
            )
        )
        XCTAssertTrue(
            HomebrewUpdateDecision.shouldOffer(
                latestVersion: "0.12",
                currentVersion: "0.11",
                receiptIsOutdated: false
            )
        )
        XCTAssertTrue(
            HomebrewUpdateDecision.shouldOffer(
                latestVersion: nil,
                currentVersion: "rolling",
                receiptIsOutdated: true
            )
        )
    }

    func testInstalledVersionReaderSeesAnInPlaceUpdate() throws {
        let fileManager = FileManager.default
        let appURL = fileManager.temporaryDirectory
            .appendingPathComponent("InstalledVersionReader-\(UUID().uuidString).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        defer { try? fileManager.removeItem(at: appURL) }
        try fileManager.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        func writeInfo(version: String, build: String) throws {
            let info: [String: Any] = [
                "CFBundleShortVersionString": version,
                "CFBundleVersion": build,
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: info,
                format: .binary,
                options: 0
            )
            try data.write(to: infoURL, options: .atomic)
        }

        try writeInfo(version: "0.9", build: "9")
        XCTAssertEqual(
            InstalledAppBundleVersionReader.read(at: appURL),
            InstalledAppBundleVersions(currentVersion: "0.9", currentBuildVersion: "9")
        )

        try writeInfo(version: "0.11", build: "11")
        XCTAssertEqual(
            InstalledAppBundleVersionReader.read(at: appURL),
            InstalledAppBundleVersions(currentVersion: "0.11", currentBuildVersion: "11")
        )
    }

    func testSapphireOrderingUsesHistoricalDecimalMarketingVersions() {
        XCTAssertEqual(SapphireVersionOrdering.compare("2.73", "2.9"), .orderedAscending)
        XCTAssertEqual(SapphireVersionOrdering.compare("2.9", "2.73"), .orderedDescending)
        XCTAssertEqual(SapphireVersionOrdering.compare("2.90", "2.9"), .orderedSame)
        XCTAssertEqual(SapphireVersionOrdering.compare("2.9.1", "2.9"), .orderedDescending)
        XCTAssertEqual(SapphireVersionOrdering.compare("2.9-rc.2", "2.9"), .orderedAscending)
        XCTAssertEqual(SapphireVersionOrdering.compare("2.9+42", "2.9+7"), .orderedSame)

        let newestRelease = ["2.73", "2.8", "2.9"].max {
            SapphireVersionOrdering.compare($0, $1) == .orderedAscending
        }
        XCTAssertEqual(newestRelease, "2.9")
    }

    func testVersionOrderingHandlesPrereleasesAndBuildMetadata() {
        XCTAssertEqual(AppVersionOrdering.compare("2.0.0", "2.0.0-rc.2"), .orderedDescending)
        XCTAssertEqual(AppVersionOrdering.compare("2.0.0-rc.10", "2.0.0-rc.2"), .orderedDescending)
        XCTAssertEqual(AppVersionOrdering.compare("2.0.0-beta.2", "2.0.0-beta.11"), .orderedAscending)
        XCTAssertEqual(AppVersionOrdering.compare("2.0.0+42", "2.0.0+7"), .orderedSame)
    }

    func testAppcastDoesNotReplaceIncompatibleStableReleaseWithBeta() {
        let futureStable = AppcastItem(
            version: "3.0.0",
            shortVersion: "3.0.0",
            downloadURL: nil,
            releaseNotes: nil,
            releaseNotesURL: nil,
            minimumSystemVersion: "999.0",
            isPrerelease: false
        )
        let compatibleBeta = AppcastItem(
            version: "4.0.0-beta.1",
            shortVersion: "4.0.0-beta.1",
            downloadURL: nil,
            releaseNotes: nil,
            releaseNotesURL: nil,
            minimumSystemVersion: nil,
            isPrerelease: true
        )

        XCTAssertNil(AppcastParser.latestItem(in: [futureStable, compatibleBeta]))
        XCTAssertEqual(AppcastParser.latestItem(in: [compatibleBeta]), compatibleBeta)
    }

    func testGitHubReleaseDecodesNullableNameAndOptionalDigest() throws {
        let json = """
        [{
          "name": null,
          "tag_name": "v2.10.0",
          "body": null,
          "html_url": "https://github.com/cshariq/Sapphire/releases/tag/v2.10.0",
          "prerelease": false,
          "draft": false,
          "published_at": "2026-09-12T10:00:00Z",
          "assets": [{
            "name": "Sapphire-universal.zip",
            "browser_download_url": "https://github.com/cshariq/Sapphire/releases/download/v2.10.0/Sapphire-universal.zip",
            "size": 1234,
            "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "content_type": "application/zip"
          }]
        }]
        """

        let releases = try JSONDecoder().decode([GitHubRelease].self, from: Data(json.utf8))
        XCTAssertEqual(releases.first?.marketingVersion, "2.10.0")
        XCTAssertEqual(releases.first?.assets.first?.size, 1234)
    }

    func testSapphireUpdaterChoosesZipInsteadOfPackage() {
        let package = GitHubReleaseAsset(
            name: "Sapphire.pkg",
            browserDownloadUrl: URL(string: "https://github.com/u7-u7/Sapphire-CN/releases/download/v3.0-cn.9-preview/Sapphire.pkg")!,
            size: 1_000,
            digest: "sha256:" + String(repeating: "a", count: 64),
            contentType: "application/octet-stream"
        )
        let archive = GitHubReleaseAsset(
            name: "Sapphire.zip",
            browserDownloadUrl: URL(string: "https://github.com/u7-u7/Sapphire-CN/releases/download/v3.0-cn.9-preview/Sapphire.zip")!,
            size: 1_000,
            digest: "sha256:" + String(repeating: "b", count: 64),
            contentType: "application/zip"
        )
        let release = GitHubRelease(
            name: "Sapphire 3.0",
            tagName: "3.0",
            body: nil,
            htmlUrl: nil,
            prerelease: false,
            draft: false,
            publishedAt: nil,
            assets: [package, archive]
        )

        XCTAssertEqual(UpdateChecker.preferredUpdateAsset(in: release), archive)
    }

    func testTransactionalAppBundleReplacementKeepsDestinationAvailable() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("UpdateReplacement-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let installed = root.appendingPathComponent("Sapphire.app", isDirectory: true)
        let staged = root.appendingPathComponent(".Sapphire-update.app", isDirectory: true)
        try fileManager.createDirectory(at: installed, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: installed.appendingPathComponent("version"))
        try Data("new".utf8).write(to: staged.appendingPathComponent("version"))

        try UpdateChecker.atomicallyReplaceAppBundle(installedURL: installed, stagedURL: staged)

        XCTAssertTrue(fileManager.fileExists(atPath: installed.path))
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("version")), "new")
        XCTAssertFalse(fileManager.fileExists(atPath: staged.path))
    }

    func testIdentifierValidationRejectsPathInjection() {
        XCTAssertTrue(AppSecurityValidator.isSafeIdentifier("com.example.Useful-App"))
        XCTAssertFalse(AppSecurityValidator.isSafeIdentifier("../Library/Caches"))
        XCTAssertFalse(AppSecurityValidator.isSafeIdentifier("/Applications/Test.app"))
        XCTAssertFalse(AppSecurityValidator.isSafeIdentifier("com.example..app"))
        XCTAssertFalse(AppSecurityValidator.isSafeIdentifier("com.example:app"))
    }

    func testArtifactScannerFindsIdentifierFilesWithoutSubstringMatches() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("AppsSettingsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let applicationURL = root.appendingPathComponent("Applications/Example.app", isDirectory: true)
        try fileManager.createDirectory(
            at: applicationURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.cleanup",
            "CFBundleName": "Example",
            "CFBundleVersion": "1",
            "CFBundlePackageType": "APPL",
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: applicationURL.appendingPathComponent("Contents/Info.plist"))

        let userLibrary = root.appendingPathComponent("Library", isDirectory: true)
        let exactPaths = [
            "Application Support/com.example.cleanup",
            "Caches/com.example.cleanup",
            "Preferences/com.example.cleanup.plist",
            "Preferences/ByHost/com.example.cleanup.123E4567-E89B-12D3-A456-426614174000.plist",
            "Saved Application State/com.example.cleanup.savedState",
            "Containers/com.example.cleanup",
            "HTTPStorages/com.example.cleanup",
            "LaunchAgents/com.example.cleanup.plist",
        ]
        for relativePath in exactPaths {
            let url = userLibrary.appendingPathComponent(relativePath)
            if url.pathExtension == "plist" {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("test".utf8).write(to: url)
            } else {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
        try fileManager.createDirectory(
            at: userLibrary.appendingPathComponent("Caches/com.example.cleanup-other"),
            withIntermediateDirectories: true
        )
        let nestedVendorSupport = userLibrary
            .appendingPathComponent("Application Support/Example Vendor/com.example.cleanup", isDirectory: true)
        try fileManager.createDirectory(at: nestedVendorSupport, withIntermediateDirectories: true)
        let siblingPreference = userLibrary.appendingPathComponent("Preferences/com.example.cleanup.other.plist")
        try Data("sibling".utf8).write(to: siblingPreference)
        let siblingByHostPreference = userLibrary.appendingPathComponent("Preferences/ByHost/com.example.cleanup.other.plist")
        try Data("sibling".utf8).write(to: siblingByHostPreference)

        let app = InstalledApp(
            id: applicationURL.path,
            name: "Example",
            bundleIdentifier: "com.example.cleanup",
            url: applicationURL,
            size: 0,
            isSystem: false,
            resourceIdentifier: AppUninstaller.currentResourceIdentifier(at: applicationURL),
            version: "1"
        )
        let artifacts = AppArtifactScanner.scan(
            app: app,
            configuration: .init(userLibrary: userLibrary, systemLibrary: nil),
            fileManager: fileManager
        )
        let paths = Set(artifacts.map { $0.url.standardizedFileURL.path })

        XCTAssertTrue(paths.contains(applicationURL.standardizedFileURL.path))
        for relativePath in exactPaths {
            XCTAssertTrue(paths.contains(userLibrary.appendingPathComponent(relativePath).standardizedFileURL.path))
        }
        XCTAssertFalse(paths.contains(userLibrary.appendingPathComponent("Caches/com.example.cleanup-other").path))
        XCTAssertFalse(paths.contains(siblingPreference.path))
        XCTAssertFalse(paths.contains(siblingByHostPreference.path))
        XCTAssertTrue(paths.contains(nestedVendorSupport.standardizedFileURL.path))
        XCTAssertTrue(artifacts.filter { !$0.isApplication }.allSatisfy { $0.confidence == .ambiguous })
    }

    func testSharedBundleIdentifierNeverPreselectsRelatedData() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("AppsSettingsSharedID-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Applications/Duplicate.app", isDirectory: true)
        try fileManager.createDirectory(at: appURL.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.duplicate",
            "CFBundleName": "Duplicate",
            "CFBundleVersion": "1",
            "CFBundlePackageType": "APPL",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        let library = root.appendingPathComponent("Library", isDirectory: true)
        let cache = library.appendingPathComponent("Caches/com.example.duplicate", isDirectory: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)

        let app = InstalledApp(
            id: appURL.path,
            name: "Duplicate",
            bundleIdentifier: "com.example.duplicate",
            url: appURL,
            size: 0,
            isSystem: false,
            resourceIdentifier: AppUninstaller.currentResourceIdentifier(at: appURL),
            version: "1"
        )
        let artifacts = AppArtifactScanner.scan(
            app: app,
            identifierOwnership: .shared,
            configuration: .init(userLibrary: library, systemLibrary: nil),
            fileManager: fileManager
        )

        XCTAssertEqual(
            artifacts.first { $0.url.standardizedFileURL.path == cache.standardizedFileURL.path }?.confidence,
            .ambiguous
        )
        XCTAssertEqual(
            artifacts.filter { $0.confidence == .exact }.map { $0.url.standardizedFileURL.path },
            [appURL.standardizedFileURL.path]
        )
    }

    func testResourceIdentifierIsStableAcrossReads() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppsSettingsIdentity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let first = AppUninstaller.currentResourceIdentifier(at: url)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, AppUninstaller.currentResourceIdentifier(at: url))
    }

    func testAllowedRootComparisonUsesPathComponents() {
        let root = URL(fileURLWithPath: "/Library")
        XCTAssertTrue(AppUninstaller.isDescendant(URL(fileURLWithPath: "/Library/Caches/com.example.app"), of: root))
        XCTAssertFalse(AppUninstaller.isDescendant(URL(fileURLWithPath: "/LibraryEvil/com.example.app"), of: root))
        XCTAssertFalse(AppUninstaller.isDescendant(root, of: root))
    }

    func testVSCodeProductMetadataRequiresSecureStructuredFields() throws {
        let valid = Data(#"{"updateUrl":"https:
        let parsed = InstalledAppUpdateSourceDetector.parseVSCodeProduct(data: valid)
        XCTAssertEqual(parsed?.baseURL.absoluteString, "https://update.example.test")
        XCTAssertEqual(parsed?.quality, "stable")

        let insecure = Data(#"{"updateUrl":"http:
        XCTAssertNil(InstalledAppUpdateSourceDetector.parseVSCodeProduct(data: insecure))
    }

    func testJSONUpdateManifestParsesVendorAndSquirrelFormats() {
        let vendor = Data(#"{"version":"15.1.0","release_notes":"Fixes","release_notes_url":"https:
        XCTAssertEqual(
            JSONUpdateManifestParser.parse(data: vendor),
            ParsedJSONUpdateManifest(
                version: "15.1.0",
                releaseNotes: "Fixes",
                releaseNotesURL: URL(string: "https://example.test/releases/15.1.0")
            )
        )

        let squirrel = Data(#"{"currentRelease":"3.2.1","releases":[{"version":"3.2.1","updateTo":{"notes":"Safe update","url":"https:
        XCTAssertEqual(JSONUpdateManifestParser.parse(data: squirrel)?.version, "3.2.1")
        XCTAssertEqual(JSONUpdateManifestParser.parse(data: squirrel)?.releaseNotes, "Safe update")
    }

    func testAndroidStudioParserUsesStableChannelOnly() {
        let xml = Data("""
        <products><product>
          <channel status="release" url="https://developer.android.com/studio/releases">
            <build number="AI-251.10.20" version="Stable | 2025.1.2"/>
          </channel>
          <channel status="beta" url="https://developer.android.com/studio/preview">
            <build number="AI-999.1.1" version="Preview | 2099.1.1"/>
          </channel>
        </product></products>
        """.utf8)
        let release = AndroidStudioUpdateParser.latestStableRelease(data: xml)
        XCTAssertEqual(release?.buildNumber, "AI-251.10.20")
        XCTAssertEqual(release?.displayVersion, "2025.1.2")
    }

    func testJetBrainsCatalogDoesNotAssumeResponseKeyMatchesProductCode() {
        let catalog = Data("""
        {
          "IIU": [
            {"version":"2026.1", "build":"261.100", "notesLink":"https://www.jetbrains.com/idea/whatsnew/", "whatsnew":null},
            {"version":"2025.3", "build":"253.10", "notesLink":null, "whatsnew":null}
          ]
        }
        """.utf8)

        XCTAssertEqual(
            JetBrainsReleaseParser.latestRelease(data: catalog),
            ParsedJetBrainsRelease(
                version: "2026.1",
                notesLink: "https://www.jetbrains.com/idea/whatsnew/"
            )
        )
    }

    func testEdgeCatalogAndBlenderPageParsers() {
        let edge = Data(#"[{"Product":"Stable","Releases":[{"ProductVersion":"152.0.1.0","Platform":"Windows"},{"ProductVersion":"153.0.2.0","Platform":"MacOS"},{"ProductVersion":"153.0.1.0","Platform":"MacOS"}]}]"#.utf8)
        XCTAssertEqual(MicrosoftEdgeCatalogParser.latestVersion(data: edge, channel: .stable), "153.0.2.0")

        let html = #"<a href="blender-5.1.3-windows-x64.zip"></a><a href="blender-5.2.1-macos-arm64.dmg"></a><a href="blender-5.2.0-macos-arm64.dmg"></a>"#
        XCTAssertEqual(BlenderUpdateParser.latestVersion(in: html), "5.2.1")
    }

    func testElectronFeedParserAcceptsQuotedSecureValues() {
        let yaml = Data("""
        provider: 'github'
        owner: "trusted-vendor"
        repo: 'desktop-app'
        """.utf8)
        XCTAssertEqual(
            InstalledAppUpdateSourceDetector.parseElectronFeed(data: yaml),
            .github(owner: "trusted-vendor", repo: "desktop-app")
        )
    }

    func testArchiveValidationAllowsInternalFrameworkSymlinks() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SafeUpdateArchive-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let framework = root.appendingPathComponent(
            "Sapphire.app/Contents/Frameworks/Example.framework",
            isDirectory: true
        )
        let version = framework.appendingPathComponent("Versions/A", isDirectory: true)
        try fileManager.createDirectory(at: version, withIntermediateDirectories: true)
        try Data("signed payload".utf8).write(to: version.appendingPathComponent("Example"))
        try fileManager.createSymbolicLink(
            atPath: framework.appendingPathComponent("Versions/Current").path,
            withDestinationPath: "A"
        )
        try fileManager.createSymbolicLink(
            atPath: framework.appendingPathComponent("Example").path,
            withDestinationPath: "Versions/Current/Example"
        )

        let archive = try makeZip(of: "Sapphire.app", in: root)
        XCTAssertNoThrow(try UpdateChecker.validateArchiveEntries(archive))
    }

    func testArchiveValidationRejectsEscapingSymlink() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("UnsafeUpdateArchive-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let app = root.appendingPathComponent("Sapphire.app", isDirectory: true)
        try fileManager.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: app.appendingPathComponent("safe"))
        try fileManager.createSymbolicLink(
            atPath: app.appendingPathComponent("escape").path,
            withDestinationPath: "../../outside"
        )

        let archive = try makeZip(of: "Sapphire.app", in: root)
        XCTAssertThrowsError(try UpdateChecker.validateArchiveEntries(archive))
    }

    private func makeZip(of item: String, in directory: URL) throws -> URL {
        let archive = directory.appendingPathComponent("update.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-qry", archive.path, item]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "AppsSettingsRevampTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Could not create the update archive fixture."]
            )
        }
        return archive
    }
}
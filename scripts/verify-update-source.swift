// Run with python3 scripts/verify-update-source.py; uses actual updater types.
var checks = 0
func expect(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
let tag = "v3.0-cn.9-preview"
let name = "Sapphire-CN-3.0-cn.9-preview-arm64-update.zip"
let github = URL(string:"https://github.com/u7-u7/Sapphire-CN/releases/download/\(tag)/\(name)")!
let mirror = URL(string:"https://sapphire-cn.oss-cn-hangzhou.aliyuncs.com/releases/\(tag)/\(name)")!
func asset(_ url: URL?, digest: String? = "sha256:" + String(repeating:"a",count:64)) -> GitHubReleaseAsset {
 GitHubReleaseAsset(name:name,browserDownloadUrl:github,size:100,digest:digest,contentType:"application/zip",mirrorDownloadUrl:url)
}
expect(SapphireUpdateSource.downloadURLs(for:asset(mirror)) == [mirror,github], "OSS first, GitHub fallback")
expect(SapphireUpdateSource.downloadURLs(for:asset(nil)) == [github], "Old feed stays compatible")
let bad = [mirror.absoluteString.replacingOccurrences(of:"https:",with:"http:"),mirror.absoluteString+"?x=1",mirror.absoluteString+"#x",mirror.absoluteString.replacingOccurrences(of:"sapphire-cn.oss-",with:"other.oss-"),mirror.absoluteString.replacingOccurrences(of:tag,with:"v3.0-cn.8-preview"),mirror.absoluteString.replacingOccurrences(of:name,with:"evil.zip"),mirror.absoluteString.replacingOccurrences(of:"aliyuncs.com/",with:"aliyuncs.com.evil.org/"),mirror.absoluteString.replacingOccurrences(of:"aliyuncs.com/",with:"aliyuncs.com:444/"),mirror.absoluteString.replacingOccurrences(of:"https://",with:"https://user:pass@")]
for text in bad {
 let url=URL(string:text)!
 expect(SapphireUpdateSource.downloadURLs(for:asset(url)) == [github],"Reject invalid mirror")
 expect(!SapphireUpdateSource.isTrustedDownloadURL(url,for:asset(mirror)),"Reject invalid final URL")
}
expect(SapphireUpdateSource.downloadURLs(for:asset(mirror,digest:nil)) == [github],"No mirror without digest")
expect(SapphireUpdateSource.downloadURLs(for:asset(mirror,digest:"sha256:bad")) == [github],"Malformed digest")
expect(SapphireUpdateSource.isTrustedDownloadURL(mirror,for:asset(mirror)),"Exact mirror trusted")
expect(!SapphireUpdateSource.isTrustedDownloadURL(mirror,for:asset(nil)),"Mirror absent from feed rejected")
expect(SapphireUpdateSource.isTrustedDownloadURL(URL(string:"https://release-assets.githubusercontent.com/a?sig=123")!,for:asset(mirror)),"GitHub CDN remains supported")
expect(!SapphireUpdateSource.isTrustedDownloadURL(URL(string:"http://release-assets.githubusercontent.com/a")!,for:asset(mirror)),"No HTTP redirect")
expect(!SapphireUpdateSource.isTrustedDownloadURL(URL(string:"https://evilgithubusercontent.com/a")!,for:asset(mirror)),"No CDN suffix confusion")
let encoded=try JSONEncoder().encode(asset(mirror))
expect(try JSONDecoder().decode(GitHubReleaseAsset.self,from:encoded)==asset(mirror),"Mirror survives candidate persistence")
let legacy=try JSONEncoder().encode(asset(nil))
expect(try JSONDecoder().decode(GitHubReleaseAsset.self,from:legacy).mirrorDownloadUrl==nil,"Legacy JSON decodes")
expect(SapphireUpdateSource.metadataURLs.count==2 && SapphireUpdateSource.metadataURLs[0].host==mirror.host && SapphireUpdateSource.metadataURLs[1].host=="raw.githubusercontent.com","Metadata OSS first")
print("PASS: \(checks) updater routing and compatibility checks")

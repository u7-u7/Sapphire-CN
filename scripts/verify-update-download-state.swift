// Run by verify-update-source.py. Only session creation and UI are stubbed;
// the callback, fallback and cancellation methods come directly from UpdateChecker.
enum HarnessStatus { case downloading(progress: Double), available, error(String) }
class DownloadHarness {
    var downloadSession: URLSession?
    var downloadTask: URLSessionDownloadTask?
    var downloadPolicyFailure: String?
    var remainingDownloadURLs = [URL]()
    var downloadGeneration: UInt64 = 0
    var status: HarnessStatus = .downloading(progress: 0)
    var starts = 0
    func startNextDownload() {
        remainingDownloadURLs.removeFirst()
        downloadSession = URLSession(configuration: .ephemeral)
        starts += 1
    }
    func applyStatus(_ status: HarnessStatus) { self.status = status }
    func restoreAvailableDownloadState() { status = .available }
    // ACTUAL_CALLBACKS
}
let offline = URLError(.cannotConnectToHost)
let harness = DownloadHarness()
let firstSession = URLSession(configuration: .ephemeral)
harness.downloadSession = firstSession
harness.remainingDownloadURLs = [github]
harness.urlSession(firstSession, task: firstSession.downloadTask(with: mirror), didCompleteWithError: offline)
expect(harness.starts == 1 && harness.remainingDownloadURLs.isEmpty, "Transport failure starts one fallback")
let fallbackSession = harness.downloadSession!
expect(fallbackSession !== firstSession, "Old completion retains new session")
harness.urlSession(firstSession, task: firstSession.downloadTask(with: mirror), didCompleteWithError: URLError(.cancelled))
expect(harness.downloadSession === fallbackSession && harness.starts == 1, "Late old callback leaves fallback untouched")
harness.urlSession(fallbackSession, task: fallbackSession.downloadTask(with: github), didCompleteWithError: offline)
expect(harness.starts == 1 && harness.downloadSession == nil, "Fallback failure does not retry forever")
if case .error = harness.status { expect(true, "Fallback failure reported") } else { fatalError("Missing error") }
let cancelled = DownloadHarness()
let cancelSession = URLSession(configuration: .ephemeral)
cancelled.downloadSession = cancelSession
cancelled.remainingDownloadURLs = [github]
cancelled.cancelDownload()
expect(cancelled.remainingDownloadURLs.isEmpty && cancelled.downloadGeneration == 1, "Cancel clears remaining sources and invalidates verification")
cancelled.urlSession(cancelSession, task: cancelSession.downloadTask(with: mirror), didCompleteWithError: URLError(.cancelled))
expect(cancelled.starts == 0, "Cancel never starts GitHub fallback")
if case .available = cancelled.status { expect(true, "Cancelled candidate can be retried") } else { fatalError("Candidate lost") }
let oversized = DownloadHarness()
let sizeSession = URLSession(configuration: .ephemeral)
oversized.downloadSession = sizeSession
oversized.remainingDownloadURLs = [github]
oversized.downloadPolicyFailure = "size limit"
oversized.urlSession(sizeSession, task: sizeSession.downloadTask(with: mirror), didCompleteWithError: URLError(.cancelled))
expect(oversized.starts == 0, "Policy failure cannot be bypassed by fallback")
if case .error(let error) = oversized.status { expect(error == "size limit", "Policy error preserved") } else { fatalError("Policy error lost") }
print("PASS: 10 download fallback/cancellation checks; no HTTP requests performed")

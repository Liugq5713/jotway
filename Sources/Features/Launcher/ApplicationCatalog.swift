import Foundation

/// 已安装应用的共享目录。扫描只运行一次，本地意图识别消费这份应用身份。
@MainActor
final class ApplicationCatalog {
    private(set) var applications: [InstalledApplication]?
    private(set) var isLoading = false
    var changed: () -> Void = {}
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let scan: @Sendable () -> [InstalledApplication]

    init(applications: [InstalledApplication]? = nil,
         scan: @escaping @Sendable () -> [InstalledApplication] = { ApplicationCatalog.load() }) {
        self.applications = applications
        self.scan = scan
    }

    func preload() {
        guard applications == nil, !isLoading else { return }
        isLoading = true
        let token = UUID()
        generation = token
        let scan = scan
        task = Task { [weak self] in
            let load = Task.detached(priority: .userInitiated) { scan() }
            let applications = await withTaskCancellationHandler {
                await load.value
            } onCancel: { load.cancel() }
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.replaceApplications(applications)
        }
        changed()
    }

    /// 扫描完成或外部目录快照更新时原子替换，旧扫描结果不再有效。
    func replaceApplications(_ applications: [InstalledApplication]) {
        cancelLoading()
        self.applications = applications
        changed()
    }

    func cancelLoading() {
        generation = UUID()
        task?.cancel()
        task = nil
        isLoading = false
    }

    isolated deinit { task?.cancel() }

    nonisolated static func isLaunchable(_ url: URL, bundleIdentifier: String?) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path), let bundle = Bundle(url: url) else { return false }
        return bundleIdentifier == nil || bundle.bundleIdentifier == bundleIdentifier
    }

    nonisolated static func load(from directories: [URL]? = nil) -> [InstalledApplication] {
        let fileManager = FileManager.default
        let roots = directories ?? fileManager.urls(
            for: .applicationDirectory, in: [.userDomainMask, .localDomainMask, .systemDomainMask]
        ) + [
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
        ]
        var urls: [URL] = []
        for root in roots {
            guard !Task.isCancelled else { return [] }
            if root.pathExtension.lowercased() == "app" {
                urls.append(root)
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: root, includingPropertiesForKeys: [.localizedNameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                guard !Task.isCancelled else { return [] }
                urls.append(url)
                enumerator.skipDescendants()
            }
        }
        var seen: Set<URL> = []
        var hiCopies: [(application: InstalledApplication, version: String)] = []
        var applications = urls.compactMap { url -> InstalledApplication? in
            guard !Task.isCancelled else { return nil }
            let url = url.resolvingSymlinksInPath()
            guard seen.insert(url).inserted, let bundle = Bundle(url: url),
                  let packageType = bundle.infoDictionary?["CFBundlePackageType"] as? String,
                  packageType == "APPL" || packageType == "FNDR" else { return nil }
            let filename = url.deletingPathExtension().lastPathComponent
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? filename
            var names = [name, filename] + [bundle.infoDictionary?["CFBundleName"] as? String,
                                          bundle.infoDictionary?["CFBundleDisplayName"] as? String].compactMap { $0 }
            if let localized = try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName {
                names.append(localized)
            }
            // 即使系统语言是英文，也能用应用自带的中文名搜索，例如 微信 / WeChat。
            for locale in bundle.localizations where locale.hasPrefix("zh") || locale.hasPrefix("en") {
                guard let file = bundle.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: locale),
                      let data = try? Data(contentsOf: file),
                      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { continue }
                names += [info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String].compactMap { $0 }
            }
            // Some system bundles omit one locale. Bind this fallback to an observed Notes identity.
            if bundle.bundleIdentifier == "com.apple.Notes", bundle.executableURL?.lastPathComponent == "Notes" {
                names += ["Notes", "备忘录"]
            }
            let application = InstalledApplication(url: url, name: name, searchNames: Array(Set(names)),
                                                   bundleIdentifier: bundle.bundleIdentifier)
            // hi ships under both filenames. Only its known production identity shares aliases and a launch target.
            if bundle.bundleIdentifier == "com.electron.redcity", bundle.infoDictionary?["CFBundleExecutable"] as? String == "REDcity" {
                guard let executable = bundle.executableURL, fileManager.isExecutableFile(atPath: executable.path) else { return nil }
                let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
                hiCopies.append((application, version))
                return nil
            }
            return application
        }
        let preferredHi = hiCopies.sorted {
            let order = $0.version.compare($1.version, options: .numeric)
            if order != .orderedSame { return order == .orderedDescending }
            let left = $0.application.url.lastPathComponent.lowercased() == "hi-latest-pkg.app"
            let right = $1.application.url.lastPathComponent.lowercased() == "hi-latest-pkg.app"
            if left != right { return left }
            return $0.application.url.path < $1.application.url.path
        }.first
        if let preferredHi {
            let names = hiCopies.flatMap { [$0.application.name] + $0.application.searchNames }
                + ["hi", "hi-latest-pkg", "REDcity"]
            applications.append(InstalledApplication(url: preferredHi.application.url, name: "hi",
                searchNames: Array(Set(names)).sorted(), bundleIdentifier: preferredHi.application.bundleIdentifier))
        }
        return applications.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.url.path < $1.url.path : order == .orderedAscending
        }
    }
}

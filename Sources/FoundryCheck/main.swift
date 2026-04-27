// foundry-check
//
// A self-contained CLI that scrapes the Microsoft Foundry Model Region
// Availability page and reports which models are available in a given set
// of regions. Optionally diffs against a cached previous run to flag models
// that became available since the last check.
//
// Usage:
//   foundry-check \
//     --regions swedencentral,westeurope,germanywestcentral,francecentral \
//     [--url https://foundry-models.azurewebsites.net/] \
//     [--deployment data-zone-standard] \
//     [--cache ~/Library/Application\ Support/BarKeeper/foundry-cache.json] \
//     [--format json|text]
//
// Exit codes:
//   0  success (even if 0 models matched)
//   1  network or parse error
//   2  invalid arguments

import Foundation

// MARK: - Argument parsing

struct CLIArgs {
    var url: String = "https://foundry-models.azurewebsites.net/"
    var regions: [String] = []
    var deployment: String? = nil       // forwarded as ?deployment=... if set
    var cachePath: String? = nil
    var format: String = "json"          // json|text
    var verbose: Bool = false
}

func parseArgs(_ argv: [String]) -> CLIArgs {
    var args = CLIArgs()
    var i = 1
    while i < argv.count {
        let key = argv[i]
        let next: () -> String? = {
            i += 1
            return i < argv.count ? argv[i] : nil
        }
        switch key {
        case "--url":         if let v = next() { args.url = v }
        case "--regions":     if let v = next() { args.regions = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        case "--deployment":  if let v = next() { args.deployment = v }
        case "--cache":       if let v = next() { args.cachePath = (v as NSString).expandingTildeInPath }
        case "--format":      if let v = next() { args.format = v }
        case "--verbose", "-v": args.verbose = true
        case "-h", "--help":
            printHelp()
            exit(0)
        default:
            FileHandle.standardError.write(Data("Unknown argument: \(key)\n".utf8))
            exit(2)
        }
        i += 1
    }
    if args.regions.isEmpty {
        FileHandle.standardError.write(Data("--regions is required (comma-separated list of Azure region names)\n".utf8))
        exit(2)
    }
    return args
}

func printHelp() {
    let help = """
    foundry-check — list Microsoft Foundry models available in given Azure regions

    OPTIONS:
      --regions <list>        Comma-separated Azure region names (required).
      --url <url>             Source page (default: https://foundry-models.azurewebsites.net/).
      --deployment <slug>     Deployment type slug, forwarded as query param.
      --cache <path>          JSON cache file. Models not present in the previous run are flagged "isNew".
      --format <json|text>    Output format (default: json).
      --verbose, -v           Verbose logging to stderr.
      -h, --help              Show this help.
    """
    print(help)
}

// MARK: - HTTP fetch

// Slugs for the foundry-models site map a deployment slug to a path.
// e.g. data-zone-standard -> /datazonestandard
private let deploymentPathMap: [String: String] = [
    "standard": "/standard",
    "global-standard": "/globalstandard",
    "data-zone-standard": "/datazonestandard",
    "global-batch": "/globalbatch",
    "data-zone-batch": "/datazonebatch",
    "provisioned": "/provisioned",
    "global-provisioned-managed": "/globalprovisionedmanaged",
    "data-zone-provisioned": "/datazoneprovisioned",
    "fine-tuning-standard": "/standardfinetune",
    "fine-tuning-global-standard": "/globalstandardfinetune",
    "fine-tuning-developer-tier": "/developertier",
    "priority-global-standard": "/priorityglobalstandard",
    "priority-data-zone-standard": "/prioritydatazonestandard"
]

func fetch(urlString: String, deployment: String?) throws -> String {
    var resolved = urlString
    if let deployment, let path = deploymentPathMap[deployment] {
        // Append the deployment path to the base host.
        if let base = URL(string: urlString),
           let host = base.host {
            let scheme = base.scheme ?? "https"
            resolved = "\(scheme)://\(host)\(path)"
        }
    }
    guard let url = URL(string: resolved) else {
        throw NSError(domain: "foundry-check", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(resolved)"])
    }

    let semaphore = DispatchSemaphore(value: 0)
    var resultData: Data?
    var resultError: Error?

    var request = URLRequest(url: url)
    request.setValue("foundry-check/1.0", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 30

    let task = URLSession.shared.dataTask(with: request) { data, _, error in
        resultData = data
        resultError = error
        semaphore.signal()
    }
    task.resume()
    semaphore.wait()

    if let resultError { throw resultError }
    guard let data = resultData, let html = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "foundry-check", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty response"])
    }
    return html
}

// MARK: - HTML table parsing
//
// The Foundry availability page renders a single large <table>. Header rows
// contain model names and release dates. Body rows are one Azure region each
// with "✅" or "-" cells indicating availability.

struct ParsedTable {
    var modelNames: [String]
    var releaseDates: [String]   // parallel to modelNames; may contain empty strings
    var rows: [(region: String, cells: [String])]
}

func parseTable(html: String) throws -> ParsedTable {
    // Extract first <table>...</table>
    guard let tableRange = html.range(of: #"<table[\s\S]*?</table>"#, options: .regularExpression) else {
        throw parseErr("No <table> element found")
    }
    let table = String(html[tableRange])

    // Pull <thead> and <tbody> separately so we can distinguish header from body
    // and avoid date-row heuristics.
    let theadRows = extractRows(in: table, between: "thead") ?? []
    let tbodyRows = extractRows(in: table, between: "tbody") ?? extractAllRows(in: table)

    guard theadRows.count >= 1 else { throw parseErr("No <thead> rows") }

    let headerCells = expandedCells(in: theadRows[0])
    // First column is "Region" or empty; drop it.
    let modelNames = Array(headerCells.dropFirst())

    var releaseDates: [String] = Array(repeating: "", count: modelNames.count)
    if theadRows.count >= 2 {
        let secondCells = expandedCells(in: theadRows[1])
        let dropped = Array(secondCells.dropFirst())
        for i in 0..<min(dropped.count, releaseDates.count) {
            if dropped[i].range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil {
                releaseDates[i] = dropped[i]
            }
        }
    }

    var bodyRows: [(String, [String])] = []
    for row in tbodyRows {
        let c = expandedCells(in: row)
        guard let region = c.first, !region.isEmpty else { continue }
        bodyRows.append((region.lowercased(), Array(c.dropFirst())))
    }

    return ParsedTable(modelNames: modelNames, releaseDates: releaseDates, rows: bodyRows)
}

/// Extract the inner content of <thead>...</thead> or <tbody>...</tbody> and
/// return its <tr> rows.
private func extractRows(in html: String, between tag: String) -> [String]? {
    guard let range = html.range(of: "<\(tag)[\\s\\S]*?</\(tag)>", options: .regularExpression) else {
        return nil
    }
    return extractAllRows(in: String(html[range]))
}

private func extractAllRows(in html: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: #"<tr[\s\S]*?</tr>"#) else { return [] }
    let ns = html as NSString
    return regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        .map { ns.substring(with: $0.range) }
}

/// Returns the cells of a row, with `colspan="N"` expanded to N copies.
private func expandedCells(in row: String) -> [String] {
    let pattern = #"<t[hd]([^>]*)>([\s\S]*?)</t[hd]>"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = row as NSString
    let matches = regex.matches(in: row, range: NSRange(location: 0, length: ns.length))
    var out: [String] = []
    for m in matches {
        let attrs = ns.substring(with: m.range(at: 1))
        let value = stripHTML(ns.substring(with: m.range(at: 2)))
        var span = 1
        if let colRange = attrs.range(of: #"colspan\s*=\s*"?(\d+)"?"#, options: .regularExpression) {
            let str = String(attrs[colRange])
            if let n = Int(str.filter(\.isNumber)) { span = max(1, n) }
        }
        for _ in 0..<span { out.append(value) }
    }
    return out
}

private func stripHTML(_ s: String) -> String {
    var out = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    out = out.replacingOccurrences(of: "&amp;", with: "&")
              .replacingOccurrences(of: "&lt;", with: "<")
              .replacingOccurrences(of: "&gt;", with: ">")
              .replacingOccurrences(of: "&nbsp;", with: " ")
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func parseErr(_ msg: String) -> NSError {
    NSError(domain: "foundry-check", code: 10, userInfo: [NSLocalizedDescriptionKey: msg])
}

// MARK: - Domain model

struct ModelAvailability: Codable {
    var name: String
    var releaseDate: String
    var availableIn: [String]
    var isNew: Bool
}

struct Report: Codable {
    var deployment: String?
    var checkedAt: String
    var sourceURL: String
    var regions: [String]
    var models: [ModelAvailability]
    var newSinceLastCheck: [String]
}

func buildReport(table: ParsedTable, regions: [String], deployment: String?, sourceURL: String,
                 previousModelNames: Set<String>) -> Report {
    let wantedRegions = Set(regions.map { $0.lowercased() })
    let isAvailable: (String) -> Bool = { cell in
        // The page uses ✅ for available; "-" for not.
        cell.contains("✅") || cell.lowercased() == "yes" || cell.lowercased() == "true"
    }

    // For each model column, collect which of the wanted regions have it.
    // Merge duplicate columns (e.g. colspan headers) by OR-ing availability.
    var byModel: [String: (date: String, regions: Set<String>)] = [:]
    for (idx, modelName) in table.modelNames.enumerated() where !modelName.isEmpty {
        var available: [String] = []
        for (region, cells) in table.rows where wantedRegions.contains(region) {
            if idx < cells.count, isAvailable(cells[idx]) {
                available.append(region)
            }
        }
        let date = idx < table.releaseDates.count ? table.releaseDates[idx] : ""
        var entry = byModel[modelName] ?? (date: "", regions: [])
        if entry.date.isEmpty { entry.date = date }
        entry.regions.formUnion(available)
        byModel[modelName] = entry
    }

    var models: [ModelAvailability] = []
    for (name, entry) in byModel where !entry.regions.isEmpty {
        models.append(ModelAvailability(
            name: name,
            releaseDate: entry.date,
            availableIn: entry.regions.sorted(),
            isNew: !previousModelNames.contains(name)
        ))
    }

    // Sort: new first, then by release date desc, then by name.
    models.sort { lhs, rhs in
        if lhs.isNew != rhs.isNew { return lhs.isNew && !rhs.isNew }
        if lhs.releaseDate != rhs.releaseDate { return lhs.releaseDate > rhs.releaseDate }
        return lhs.name < rhs.name
    }

    let iso = ISO8601DateFormatter()
    return Report(
        deployment: deployment,
        checkedAt: iso.string(from: Date()),
        sourceURL: sourceURL,
        regions: regions,
        models: models,
        newSinceLastCheck: models.filter(\.isNew).map(\.name)
    )
}

// MARK: - Cache

func loadPreviousModelNames(cachePath: String?) -> Set<String> {
    guard let cachePath, FileManager.default.fileExists(atPath: cachePath),
          let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)),
          let decoded = try? JSONDecoder().decode(Report.self, from: data)
    else { return [] }
    return Set(decoded.models.map(\.name))
}

func saveCache(report: Report, cachePath: String?) {
    guard let cachePath else { return }
    let dir = (cachePath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(report) {
        try? data.write(to: URL(fileURLWithPath: cachePath), options: .atomic)
    }
}

// MARK: - Output

func renderJSON(_ report: Report) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(report),
          let s = String(data: data, encoding: .utf8) else { return "{}" }
    return s
}

func renderText(_ report: Report) -> String {
    var lines: [String] = []
    lines.append("Foundry Models — \(report.deployment ?? "default") — \(report.regions.joined(separator: ", "))")
    lines.append("Checked: \(report.checkedAt)")
    lines.append("")
    if !report.newSinceLastCheck.isEmpty {
        lines.append("🆕 New since last check:")
        for name in report.newSinceLastCheck { lines.append("  • \(name)") }
        lines.append("")
    }
    for m in report.models {
        let badge = m.isNew ? "🆕" : "  "
        let date = m.releaseDate.isEmpty ? "" : " (\(m.releaseDate))"
        lines.append("\(badge) \(m.name)\(date) — \(m.availableIn.joined(separator: ", "))")
    }
    if report.models.isEmpty {
        lines.append("(no models available in the requested regions)")
    }
    return lines.joined(separator: "\n")
}

// MARK: - Main

let args = parseArgs(CommandLine.arguments)
do {
    if args.verbose { FileHandle.standardError.write(Data("Fetching \(args.url)…\n".utf8)) }
    let html = try fetch(urlString: args.url, deployment: args.deployment)
    let table = try parseTable(html: html)
    if args.verbose {
        FileHandle.standardError.write(Data("Parsed \(table.modelNames.count) models, \(table.rows.count) regions\n".utf8))
    }
    let prev = loadPreviousModelNames(cachePath: args.cachePath)
    let report = buildReport(
        table: table,
        regions: args.regions,
        deployment: args.deployment,
        sourceURL: args.url,
        previousModelNames: prev
    )
    saveCache(report: report, cachePath: args.cachePath)
    switch args.format {
    case "text": print(renderText(report))
    default:     print(renderJSON(report))
    }
    exit(0)
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}

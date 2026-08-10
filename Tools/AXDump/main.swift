import AppKit
import ApplicationServices

// Records what the accessibility API answers about the windows on this machine right
// now, one JSON file per window, as fixtures for the admission gate
// (`WindowSnapshot.isAdmissible`). Nothing here imports the app's own code: the point is
// to capture what macOS says, not what OttoWM makes of it.
//
//   make axdump                 every window of every regular application
//   make axdump ARGS="Safari"   only the applications whose name contains Safari
//
// The `admissible` field is the recorder's guess and the one thing a human has to
// review before committing the file: it is the expectation the test suite then holds
// the gate to. An existing file is never overwritten, delete it to re-record.

let arguments = Array(CommandLine.arguments.dropFirst())

guard let directory = arguments.first else {
    FileHandle.standardError.write(Data("usage: axdump <directory> [application name ...]\n".utf8))
    exit(EXIT_FAILURE)
}

let nameFilters = Array(arguments.dropFirst())

// Behind the lock screen every window of every application answers as the application
// itself, with no buttons and no id, so a run there records nothing but blanks.
let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
guard (session["CGSSessionScreenIsLocked"] as? Int ?? 0) == 0 else {
    FileHandle.standardError.write(Data("the screen is locked, no window can be read through it\n".utf8))
    exit(EXIT_FAILURE)
}

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("""
    axdump has no Accessibility permission, it cannot read a single window. Grant it to \
    the terminal running make.\n
    """.utf8))
    exit(EXIT_FAILURE)
}

// The window title is printed while recording so whoever runs this knows which window
// each file is, and deliberately not written to it: what the gate reads is here, and a
// fixture is committed to a public repository.
struct Dump: Encodable {
    let app: String
    let note: String
    let role: String
    let subrole: String
    let hasCloseButton: Bool
    let hasMinimizeButton: Bool
    let hasZoomButton: Bool
    let hasFullScreenButton: Bool
    let isFullScreen: Bool
    let isMinimized: Bool
    let id: UInt32
    let admissible: Bool
}

@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func windowId(of element: AXUIElement) -> CGWindowID {
    var id: CGWindowID = 0
    _AXUIElementGetWindow(element, &id)
    return id
}

func slug(_ text: String) -> String {
    let slug = text.lowercased()
        .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
        .joined()
        .split(separator: "-")
        .joined(separator: "-")
    return slug.isEmpty ? "untitled" : String(slug.prefix(40))
}

func dump(_ element: AXUIElement, of app: NSRunningApplication) -> (dump: Dump, title: String) {
    let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
    let hasCloseButton = attribute(element, kAXCloseButtonAttribute) != nil
    let hasMinimizeButton = attribute(element, kAXMinimizeButtonAttribute) != nil

    let dumped = Dump(
        app: app.localizedName ?? "",
        note: "",
        role: attribute(element, kAXRoleAttribute) as? String ?? "",
        subrole: subrole,
        hasCloseButton: hasCloseButton,
        hasMinimizeButton: hasMinimizeButton,
        hasZoomButton: attribute(element, kAXZoomButtonAttribute) != nil,
        hasFullScreenButton: attribute(element, kAXFullScreenButtonAttribute) != nil,
        isFullScreen: attribute(element, "AXFullScreen") as? Bool ?? false,
        isMinimized: attribute(element, kAXMinimizedAttribute) as? Bool ?? false,
        id: windowId(of: element),
        admissible: subrole == kAXStandardWindowSubrole || (hasCloseButton && hasMinimizeButton)
    )

    return (dumped, attribute(element, kAXTitleAttribute) as? String ?? "")
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

let applications = NSWorkspace.shared.runningApplications
    .filter { $0.activationPolicy == .regular }
    .filter { app in
        nameFilters.isEmpty || nameFilters.contains { app.localizedName?.localizedCaseInsensitiveContains($0) == true }
    }

var recorded = 0

for app in applications {
    let windows = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute)
        as? [AXUIElement] ?? []

    for (index, window) in windows.enumerated() {
        let (dumped, title) = dump(window, of: app)
        let name = "\(slug(dumped.app))-\(slug(dumped.subrole.isEmpty ? dumped.role : dumped.subrole))-\(index + 1).json"
        let path = "\(directory)/\(name)"

        guard !FileManager.default.fileExists(atPath: path) else {
            print("kept \(name), delete it to re-record")
            continue
        }
        guard let json = try? encoder.encode(dumped) else { continue }

        try? json.write(to: URL(fileURLWithPath: path))
        print("recorded \(name) subrole=\(dumped.subrole) admissible=\(dumped.admissible) title=\(title)")
        recorded += 1
    }
}

print("\(recorded) window(s) recorded into \(directory), review the admissible field of each before committing")

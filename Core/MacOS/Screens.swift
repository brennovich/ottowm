/// The first display is the primary one, the display at the origin of the arrangement. The
/// active display is the one with the menu bar, which follows the focused window and a click
/// on a display's desktop.
struct Screens {
    let all: () -> [Display]
    let active: () -> DisplayID?
}

/// Only plain Command+Tab belongs to CmdTabPlus. All other key events pass through.
public enum ShortcutPolicy {
    public static func handles(keyCode: Int64, command: Bool, shift: Bool, control: Bool, option: Bool) -> Bool {
        keyCode == 48 && command && !shift && !control && !option
    }
}

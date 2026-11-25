//@ pragma UseQApplication
import QtQuick
import Quickshell

ShellRoot {
    Lock { id: lock }

    PowerMenu { lock: lock }

    QuickSettings { lock: lock }

    DatePanel {}

    Settings {}

    Music {}

    NotificationPopups {}

    Osd {}

    Overview {}

    HotCorner {}

    Switcher {}

    PolkitPrompt {}

    ClipboardPicker {}

    ShortcutsHelp {}

    TitleMenu {}

    Variants {
        model: Quickshell.screens
        Scope {
            id: perScreen
            required property var modelData
            Wallpaper { screen: perScreen.modelData }
            Bar { screen: perScreen.modelData }
        }
    }
}
